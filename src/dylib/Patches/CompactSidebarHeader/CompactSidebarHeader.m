#import "StdPatch/StdPatch.h"

extern DPPatch DPCompactSidebarHeader;
static const CGFloat DPHeaderTrim = 10;
static const CGFloat DPTopTabsButtonInset = 14;  // Where Dia puts the window buttons, from the window's corner, with tabs at the top.
static NSHashTable<NSView *> *DPSidebars;
static char DPHeaderFrameKey, DPButtonsKey;

static NSRect DPLaidOutHeader(NSView *header) {
    return [DPDiaValue(header, &DPHeaderFrameKey, @(header.frame)) rectValue];
}

// The close button's frame from the window's top left corner.
static NSRect DPCloseButtonInWindow(NSView *lights) {
    NSView *close = DPFindView(lights, ^BOOL(NSView *v) { return [v isKindOfClass:NSButton.class] && v == [v.window standardWindowButton:NSWindowCloseButton]; });
    if (!close || !lights.window) return NSZeroRect;
    NSRect r = [close convertRect:close.bounds toView:nil];
    r.origin.y = NSHeight(lights.window.contentView.superview.bounds) - NSMaxY(r);
    return r;
}

// Move the buttons as Dia sets their row, not after the header's layout. Moving them afterwards makes Dia lay the
// header out again, which puts them back, and the two take turns until the layout guard gives up: that is the jitter
// while the sidebar is resized. Rewriting the frame inside the setter leaves the value Dia ends the pass with, so
// there is nothing left for it to lay out again. The frame arriving is Dia's; the close button still sits where the
// last one put it, so the extra move of this frame is added before measuring.
static void DPButtonsRow_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    NSView *lights = DPGet(self, &DPButtonsKey);
    NSWindow *window = self.window;
    if (DPCompactSidebarHeader.on && lights && window && !(window.styleMask & NSWindowStyleMaskFullScreen)) {
        NSRect old = self.frame, close = DPCloseButtonInWindow(lights);
        BOOL flipped = self.superview.isFlipped;
        close.origin.x += frame.origin.x - NSMinX(old);
        close.origin.y += flipped ? frame.origin.y - NSMinY(old) : NSMinY(old) - frame.origin.y;
        CGFloat dx = DPTopTabsButtonInset - NSMinX(close), dy = DPTopTabsButtonInset - NSMinY(close);
        if (!NSIsEmptyRect(close) && fabs(dx) <= 6 && fabs(dy) <= 6) {
            frame.origin.x += dx;
            frame.origin.y += flipped ? dy : -dy;
        }
    }
    DPCallOriginal(DPButtonsRow_setFrame, self, frame);
}

// With tabs at the top Dia moves the window buttons into the corner; the compact header puts them in the same spot. A
// sidebar floating over the page has them elsewhere, so only buttons already near the corner move. This only notes
// which row holds them, so the setter above knows which of Dia's stacks to move.
static void DPHeader_layout(NSView *self, SEL _cmd) {
    NSView *lights = DPFindView(self, ^BOOL(NSView *v) { return DPIsKind(v, DPDiaTrafficLights); }), *row = lights.superview;
    if (lights && row != self) DPSet(row, &DPButtonsKey, lights);
    DPCallOriginal(DPHeader_layout, self);
}

// Dia lays the header and the view under it out as if the header still had its full height. Trimming them after that
// pass makes Dia lay them out again, which puts the content back and makes it jump by DPHeaderTrim while the sidebar
// opens or resizes. Rewriting the frames inside the setters leaves Dia's own layout with the trimmed values, so there
// is nothing left to correct afterwards.
static void DPCompactFrame_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    if (DPCompactSidebarHeader.on && DPSidebars) {
        if (DPIsKind(self, DPDiaSidebarHeader)) {
            NSArray *values = DPGet(self, &DPHeaderFrameKey);
            if (!values || ![values[1] isEqual:[NSValue valueWithRect:frame]]) {
                NSRect laidOut = frame;
                frame.size.height = MAX(0, NSHeight(laidOut) - DPHeaderTrim);
                DPOverride(self, &DPHeaderFrameKey, [NSValue valueWithRect:laidOut], [NSValue valueWithRect:frame]);
            }
        } else if ([DPSidebars containsObject:self.superview]) {
            NSView *header = DPSubview(self.superview, DPDiaSidebarHeader);
            NSRect laidOut = header ? DPLaidOutHeader(header) : NSZeroRect;
            if (header && !NSIsEmptyRect(laidOut) && fabs(NSMinY(frame) - NSMaxY(laidOut)) < 0.5) {
                frame.origin.y = MAX(0, NSMaxY(laidOut) - DPHeaderTrim);
                frame.size.height += DPHeaderTrim;
            }
        }
    }
    DPCallOriginal(DPCompactFrame_setFrame, self, frame);
}

static void DPSidebar_viewWillLayout(NSViewController *self, SEL _cmd) {
    [DPSidebars addObject:self.view];
    for (NSView *sub in self.view.subviews)
        DPHookClass([sub class], @selector(setFrame:), (IMP)DPCompactFrame_setFrame);
    DPCallOriginal(DPSidebar_viewWillLayout, self);
}

static void DPSidebar_viewDidLayout(NSViewController *self, SEL _cmd) {
    DPCallOriginal(DPSidebar_viewDidLayout, self);
    [DPSidebars addObject:self.view];
}

static void DPInstallCompactSidebarHeader(void) {
    DPSidebars = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaSidebarController, @selector(viewWillLayout), (IMP)DPSidebar_viewWillLayout);
    DPHook(DPDiaSidebarController, @selector(viewDidLayout), (IMP)DPSidebar_viewDidLayout);
    DPHook(DPDiaSidebarHeader, @selector(layout), (IMP)DPHeader_layout);
    DPHook(DPDiaSidebarHeader, @selector(setFrame:), (IMP)DPCompactFrame_setFrame);
    DPHookClass(NSStackView.class, @selector(setFrame:), (IMP)DPButtonsRow_setFrame);
}

static void DPApplyCompactSidebarHeader(DPPatch *patch) { DPRelayoutViews(DPSidebars); }

// A sidebar that isn't open passes: with tabs at the top there's no header.
static NSString *DPVerifyCompactSidebarHeader(DPPatch *patch) {
    for (NSView *header in DPFindViews(DPDiaSidebarHeader)) {
        if (header.hiddenOrHasHiddenAncestor || !header.superview.isFlipped) continue;
        CGFloat trimmed = NSHeight(DPLaidOutHeader(header)) - NSHeight(header.frame);
        if (fabs(trimmed - (patch->on ? DPHeaderTrim : 0)) > 0.5) return patch->on ? @"header is full height" : @"header is still trimmed";
        NSView *lights = DPFindView(header, ^BOOL(NSView *v) { return DPIsKind(v, DPDiaTrafficLights); });
        NSRect close = lights ? DPCloseButtonInWindow(lights) : NSZeroRect;
        BOOL cornered = fabs(NSMinX(close) - DPTopTabsButtonInset) < 0.5 && fabs(NSMinY(close) - DPTopTabsButtonInset) < 0.5;
        BOOL fullScreen = (header.window.styleMask & NSWindowStyleMaskFullScreen) != 0;
        if (patch->on && !fullScreen && !NSIsEmptyRect(close) && !cornered) return @"window buttons aren't where top tabs put them";
    }
    return nil;
}

DP_PATCH(DPCompactSidebarHeader) {
    .key = @"compactSidebarHeader",
    .order = 76,
    .section = @"Sidebar & Tab Bar",
    .title = @"Compact Sidebar Header",
    .detail = @"Move the pinned tabs up into the empty space under the window buttons.",
    .symbol = @"arrow.up.to.line.square.fill",
    .tint = @"systemTealColor",
    .classes = DPClasses(DPDiaSidebarController, DPDiaSidebarHeader, DPDiaTrafficLights),
    .install = DPInstallCompactSidebarHeader,
    .apply = DPApplyCompactSidebarHeader,
    .verify = DPVerifyCompactSidebarHeader,
};
