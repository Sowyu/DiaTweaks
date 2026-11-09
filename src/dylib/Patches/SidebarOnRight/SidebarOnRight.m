#import "StdPatch/StdPatch.h"

extern DPPatch DPSidebarOnRight;

static char DPFrameKey, DPDiaFrameKey;
static NSHashTable<NSView *> *DPMirrored;
static BOOL DPInMouseMonitor;

// Dia lays the window out with the sidebar on the left. Each of these views is flipped across its parent as Dia places
// it: the page, the sidebar, the sidebar's resize edge inside it, the sidebar that floats out while it's hidden, and the
// window backgrounds behind them.
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

// While the sidebar is hidden, Dia floats it out when a mouse-moved monitor finds the cursor at the window's left edge.
// That monitor reads the cursor's place on screen, so inside mouse-moved monitors the cursor is mirrored across the
// Dia window it's over.
static id DPEvent_addLocalMonitor(id self, SEL _cmd, NSEventMask mask, NSEvent *(^handler)(NSEvent *)) {
    if (mask != NSEventMaskMouseMoved || !handler) return DPCallOriginal(DPEvent_addLocalMonitor, self, mask, handler);
    return DPCallOriginal(DPEvent_addLocalMonitor, self, mask, ^NSEvent *(NSEvent *event) {
        BOOL outer = DPInMouseMonitor;
        DPInMouseMonitor = YES;
        NSEvent *result = handler(event);
        DPInMouseMonitor = outer;
        return result;
    });
}

static NSPoint DPEvent_mouseLocation(id self, SEL _cmd) {
    NSPoint point = DPCallOriginal(DPEvent_mouseLocation, self);
    if (!DPInMouseMonitor || !DPSidebarOnRight.on) return point;
    for (NSWindow *window in NSApp.orderedWindows) {
        if (!NSPointInRect(point, window.frame)) continue;
        if (DPIsKind(window, DPDiaWindow)) point.x = NSMinX(window.frame) + NSMaxX(window.frame) - point.x;
        break;
    }
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
    for (const char *const *name = DPClasses(DPDiaContentContainer, DPDiaSidebarRoot, DPDiaSidebarResize, DPDiaFloatingSidebar, DPDiaWindowBackgroundTile); *name; name++)
        DPHook(*name, @selector(setFrame:), (IMP)DPMirror_setFrame);
    DPHookClass(NSPanGestureRecognizer.class, @selector(translationInView:), (IMP)DPPan_translationInView);
    DPHookClass(object_getClass(NSEvent.class), @selector(addLocalMonitorForEventsMatchingMask:handler:), (IMP)DPEvent_addLocalMonitor);
    DPHookClass(object_getClass(NSEvent.class), @selector(mouseLocation), (IMP)DPEvent_mouseLocation);
}

DP_PATCH(DPSidebarOnRight) {
    .key = @"sidebarOnRight",
    .title = @"Sidebar on Right",
    .detail = @"Put the sidebar on the right side of the window, with the page on the left.",
    .symbol = @"sidebar.right",
    .tint = @"systemTealColor",
    .section = @"Sidebar & Tab Bar",
    .classes = DPClasses(DPDiaContentContainer, DPDiaSidebarRoot, DPDiaSidebarResize, DPDiaFloatingSidebar, DPDiaWindow, DPDiaWindowBackground, DPDiaWindowBackgroundTile),
    .install = DPInstallSidebarOnRight,
    .apply = DPApplySidebarOnRight,
    .verify = DPVerifySidebarOnRight,
};
