#import "StdPatch/StdPatch.h"

extern DPPatch DPToolbarOnWindow;

static char DPShadowFrameKey, DPPageRadiusKey, DPContainerFrameKey, DPFieldColorKey;
static const CGFloat DPWindowGap = 6;  // Dia's padding around the page.
static const char *DPDiaPageArea = "_TtC18GesturalNavigation38GesturalNavigationEventInterceptorView";

// The toolbar in the same pane as `view`, if it's showing at the top of that pane.
static NSView *DPToolbarAbove(NSView *view) {
    NSView *toolbar = DPFindView(view.superview, ^BOOL(NSView *candidate) { return DPIsKind(candidate, DPDiaToolbar); });
    return toolbar && !toolbar.isHiddenOrHasHiddenAncestor && toolbar.alphaValue > 0 && NSHeight(toolbar.frame) > 0 ? toolbar : nil;
}

// Like Zen, the toolbar sits on the window, and the page's card starts under it. The card's fill, shadow and outline
// come from shadow views as tall as the card, so each starts below the toolbar instead.
static void DPShadow_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    NSRect dia = [DPDiaValue(self, &DPShadowFrameKey, @(frame)) rectValue], ours = dia;
    NSView *toolbar = DPToolbarOnWindow.on && NSEqualSizes(dia.size, self.superview.bounds.size) ? DPToolbarAbove(self) : nil;
    if (toolbar) {
        CGFloat height = NSHeight(toolbar.frame);
        ours.size.height -= height;
        if (self.superview.isFlipped) ours.origin.y += height;
    }
    DPOverride(self, &DPShadowFrameKey, @(dia), @(ours));
    DPCallOriginal(DPShadow_setFrame, self, ours);
}

// On the window, the toolbar's row runs from the window's top edge to the card, so the window's padding above the page
// goes and the bar sits as far from the window's edge as from the card.
static NSRect DPContainerFrame(NSView *container, NSRect dia) {
    NSView *superview = container.superview;
    CGFloat top = superview.isFlipped ? NSMinY(dia) - NSMinY(superview.bounds) : NSMaxY(superview.bounds) - NSMaxY(dia);
    NSView *toolbar = DPFindView(container, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaToolbar); });
    if (DPToolbarOnWindow.on && superview && fabs(top - DPWindowGap) < 0.5 && toolbar && !toolbar.isHiddenOrHasHiddenAncestor && toolbar.alphaValue > 0) {
        dia.size.height += DPWindowGap;
        if (superview.isFlipped) dia.origin.y -= DPWindowGap;
    }
    return dia;
}

static void DPContainer_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    NSRect dia = [DPDiaValue(self, &DPContainerFrameKey, @(frame)) rectValue], ours = DPContainerFrame(self, dia);
    DPOverride(self, &DPContainerFrameKey, @(dia), @(ours));
    DPCallOriginal(DPContainer_setFrame, self, ours);
}

// The toolbar can come and go, as Hide Toolbar shows it on hover, so the card and the page's padding follow it.
static void DPRefreshShadows(NSView *toolbar) {
    for (NSView *view = toolbar.superview; view; view = view.superview) {
        for (NSView *sibling in view.subviews)
            if (DPIsKind(sibling, DPDiaShadowView)) sibling.frame = [DPDiaValue(sibling, &DPShadowFrameKey, @(sibling.frame)) rectValue];
        if (!DPIsKind(view, DPDiaContentContainer)) continue;
        // Dia places the container again, so a patch that moves it, like Sidebar on Right, sees Dia's own frame.
        NSArray<NSValue *> *frames = DPGet(view, &DPContainerFrameKey);
        NSRect want = frames ? DPContainerFrame(view, frames[0].rectValue) : view.frame;
        if (frames && (NSHeight(want) != NSHeight(frames[1].rectValue))) view.superview.needsLayout = YES;
        break;
    }
}

// Dia fills the address field with the page's color, which looks like a hole on the window, so it takes a light tint of
// the text color instead, like the window's other controls. Dia sets that color again on its own, on hover and as pages
// load, so the field's layer gets a subclass of its own that keeps Dia's latest color and shows the tint while this is on.
static CGColorRef DPFieldColor(CALayer *layer, CGColorRef dia) {
    NSView *fill = (NSView *)layer.delegate;
    if (!DPToolbarOnWindow.on || ![fill isKindOfClass:NSView.class]) return dia;
    __block CGColorRef tint = dia;
    [fill.effectiveAppearance performAsCurrentDrawingAppearance:^{ tint = [NSColor.labelColor colorWithAlphaComponent:0.08].CGColor; }];
    return tint;
}

static void DPFieldLayer_setBackgroundColor(CALayer *self, SEL _cmd, CGColorRef color) {
    DPSet(self, &DPFieldColorKey, (__bridge id)color);
    IMP set = class_getMethodImplementation(class_getSuperclass(object_getClass(self)), _cmd);
    ((void (*)(id, SEL, CGColorRef))set)(self, _cmd, DPFieldColor(self, color));
}

static void DPTintField(NSView *toolbar) {
    NSView *field = DPFindView(toolbar, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaAddressField); });
    CALayer *layer = DPSubview(field, "ARCUI.FlippedView").layer;
    if (!layer) return;
    Class base = object_getClass(layer);
    NSString *baseName = NSStringFromClass(base);
    if ([baseName hasPrefix:@"NSKVONotifying_"]) {  // Already a runtime subclass, which isn't safe to swap.
        layer.backgroundColor = DPFieldColor(layer, layer.backgroundColor);
        return;
    }
    if (![baseName hasPrefix:@"DPTintedField_"]) {
        NSString *name = [@"DPTintedField_" stringByAppendingString:baseName];
        Class tinted = NSClassFromString(name);
        if (!tinted) {
            tinted = objc_allocateClassPair(base, name.UTF8String, 0);
            class_addMethod(tinted, @selector(setBackgroundColor:), (IMP)DPFieldLayer_setBackgroundColor, "v@:^{CGColor=}");
            objc_registerClassPair(tinted);
        }
        DPSet(layer, &DPFieldColorKey, (__bridge id)layer.backgroundColor);
        object_setClass(layer, tinted);
    }
    layer.backgroundColor = (__bridge CGColorRef)DPGet(layer, &DPFieldColorKey);
}

static void DPToolbar_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPToolbar_layout, self);
    BOOL on = DPToolbarOnWindow.on;
    // Its background and the line Dia draws under it once the page scrolls. Faded rather than hidden, which Dia sets itself.
    for (NSView *sub in self.subviews)
        if (DPIsKind(sub, "ARCUI.BackgroundColorView") && sub.alphaValue != (on ? 0 : 1)) sub.alphaValue = on ? 0 : 1;
    DPRefreshShadows(self);
    DPTintField(self);
    // The page under the toolbar is rounded like the card it now starts.
    NSView *page = DPSubview(self.superview, DPDiaPageArea);
    CALayer *layer = page.layer;
    if (!layer) return;
    CGFloat card = 0;
    for (NSView *view = self.superview; view && !card; view = view.superview) if (view.layer.masksToBounds) card = view.layer.cornerRadius;
    NSNumber *dia = DPDiaValue(layer, &DPPageRadiusKey, @(layer.cornerRadius)), *ours = on ? @(card) : dia;
    DPOverride(layer, &DPPageRadiusKey, dia, ours);
    layer.cornerRadius = ours.doubleValue;
    layer.masksToBounds = on || dia.doubleValue > 0;
    layer.cornerCurve = kCACornerCurveContinuous;
}

static void DPApplyToolbarOnWindow(DPPatch *patch) {
    for (NSView *toolbar in DPFindViews(DPDiaToolbar)) {
        toolbar.needsLayout = YES;
        DPRefreshShadows(toolbar);
    }
}

static void DPInstallToolbarOnWindow(void) {
    DPHook(DPDiaShadowView, @selector(setFrame:), (IMP)DPShadow_setFrame);
    DPHook(DPDiaToolbar, @selector(layout), (IMP)DPToolbar_layout);
    DPHook(DPDiaContentContainer, @selector(setFrame:), (IMP)DPContainer_setFrame);
}

DP_PATCH(DPToolbarOnWindow) {
    .key = @"toolbarOnWindow",
    .title = @"Toolbar on Window",
    .detail = @"Put the toolbar on the window’s background, like Zen, with the page’s rounded card starting under it.",
    .symbol = @"menubar.rectangle",
    .tint = @"systemIndigoColor",
    .section = @"Toolbar",
    .classes = DPClasses(DPDiaToolbar, DPDiaShadowView, DPDiaContentContainer),
    .install = DPInstallToolbarOnWindow,
    .apply = DPApplyToolbarOnWindow,
};
