#import "StdPatch/StdPatch.h"

extern DPPatch DPSidebarOnRight;

static char DPFrameKey, DPDiaFrameKey;
static NSHashTable<NSView *> *DPMirrored;

// Dia lays the window out with the sidebar on the left. Each of these views is flipped across its parent as Dia places
// it: the page, the sidebar, the sidebar's resize edge inside it, and the window backgrounds behind them.
static BOOL DPShouldMirror(NSView *view) {
    if (DPIsKind(view, DPDiaWindowBackgroundTile)) return DPIsKind(view.superview, DPDiaWindowBackground);
    return YES;
}

static void DPMirror_setFrame(NSView *self, SEL _cmd, NSRect frame) {
    // A frame Dia hands back as it read it is still ours, so it doesn't flip again.
    NSRect dia = [DPDiaValue(self, &DPFrameKey, @(frame)) rectValue], ours = dia;
    NSView *superview = self.superview;
    if (DPSidebarOnRight.on && superview && DPShouldMirror(self)) ours.origin.x = NSWidth(superview.bounds) - NSMaxX(dia);
    DPOverride(self, &DPFrameKey, @(dia), @(ours));
    DPSet(self, &DPDiaFrameKey, @(dia));  // Another patch may change ours further, so turning off starts from this.
    [DPMirrored addObject:self];
    DPCallOriginal(DPMirror_setFrame, self, ours);
}

// Dia widens the sidebar by how far its resize edge is dragged to the right, so on the right that distance flips.
static BOOL DPMirrorsPan(NSGestureRecognizer *pan) {
    return DPSidebarOnRight.on && DPIsKind(pan.view, DPDiaSidebarResize) && pan.view.window;
}

static NSPoint DPPan_translationInView(NSPanGestureRecognizer *self, SEL _cmd, NSView *view) {
    NSPoint point = DPCallOriginal(DPPan_translationInView, self, view);
    if (DPMirrorsPan(self)) point.x = -point.x;
    return point;
}

static void DPApplySidebarOnRight(DPPatch *patch) {
    for (NSView *view in DPMirrored.allObjects) {
        view.frame = [DPGet(view, &DPDiaFrameKey) rectValue];
        view.superview.needsLayout = YES;
    }
}

static NSString *DPVerifySidebarOnRight(DPPatch *patch) {
    for (NSView *sidebar in DPFindViews(DPDiaSidebarRoot)) {
        NSView *page = DPSubview(sidebar.superview, DPDiaContentContainer);
        if (!page || sidebar.hidden || NSWidth(sidebar.frame) < 1 || NSMaxX(sidebar.frame) <= 0) continue;
        BOOL right = NSMidX(sidebar.frame) > NSMidX(page.frame);
        if (right != patch->on) return right ? @"the sidebar is on the right" : @"the sidebar is on the left";
    }
    return nil;
}

static void DPInstallSidebarOnRight(void) {
    DPMirrored = [NSHashTable weakObjectsHashTable];
    for (const char *const *name = DPClasses(DPDiaContentContainer, DPDiaSidebarRoot, DPDiaSidebarResize, DPDiaWindowBackgroundTile); *name; name++)
        DPHook(*name, @selector(setFrame:), (IMP)DPMirror_setFrame);
    DPHookClass(NSPanGestureRecognizer.class, @selector(translationInView:), (IMP)DPPan_translationInView);
}

DP_PATCH(DPSidebarOnRight) {
    .key = @"sidebarOnRight",
    .title = @"Sidebar on Right",
    .detail = @"Put the sidebar on the right side of the window, with the page on the left.",
    .symbol = @"sidebar.right",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaContentContainer, DPDiaSidebarRoot, DPDiaSidebarResize, DPDiaWindowBackground, DPDiaWindowBackgroundTile),
    .install = DPInstallSidebarOnRight,
    .apply = DPApplySidebarOnRight,
    .verify = DPVerifySidebarOnRight,
};
