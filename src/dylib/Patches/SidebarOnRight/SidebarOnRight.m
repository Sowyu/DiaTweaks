#import "StdPatch/StdPatch.h"
#include <mach-o/dyld.h>

extern DPPatch DPSidebarOnRight;
void DPInstallSidebarPopups(void);
void DPInstallSidebarButton(void);
void DPApplySidebarButton(void);

static char DPFrameKey, DPDiaFrameKey;
static NSHashTable<NSView *> *DPMirrored;

// Dia lays the window out with the sidebar on the left. Each of these views is flipped across its parent as Dia places
// it: the page, the sidebar, the sidebar's resize edge inside it, the sidebar that floats out while it's hidden, and the
// window backgrounds behind them.
static BOOL DPFloatsRight(void);

static BOOL DPShouldMirror(NSView *view) {
    if (DPIsKind(view, DPDiaWindowBackgroundTile)) return DPIsKind(view.superview, DPDiaWindowBackground);
    if (DPIsKind(view, DPDiaFloatingSidebar)) return DPFloatsRight();  // It floats out on the side its hover check watches.
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

// While the sidebar is hidden, Dia floats it out when its hover check finds the cursor at the window's left edge, run
// from a mouse monitor and from a timer. Only the hover check's reads of the cursor are mirrored across the window, so
// the right edge opens it and nothing else in Dia sees a mirrored cursor. Dia's code has no symbols, so the reads are
// known by where they return to in one Dia build; on any other build the hidden sidebar keeps floating out on the left.
// ponytail: pinned to one Dia build, find the new return addresses with a call-stack log of +[NSEvent mouseLocation]
// when Dia updates.
static uintptr_t DPHoverReads[3];

static BOOL DPFloatsRight(void) {
    return DPSidebarOnRight.on && DPHoverReads[0];
}

static BOOL DPIsHoverRead(uintptr_t address) {
    for (int i = 0; i < 3; i++) if (address == DPHoverReads[i]) return YES;
    return NO;
}

static NSPoint DPEvent_mouseLocation(id self, SEL _cmd) {
    NSPoint point = DPCallOriginal(DPEvent_mouseLocation, self);
    if (!DPFloatsRight() || !DPIsHoverRead((uintptr_t)__builtin_return_address(0))) return point;
    // The check also counts the cursor past the window's edge, up to the screen's, so the window is the frontmost one
    // level with the cursor rather than one under it.
    for (NSWindow *window in NSApp.orderedWindows) {
        if (!window.isVisible || point.y < NSMinY(window.frame) || point.y > NSMaxY(window.frame)) continue;
        if (DPIsKind(window, DPDiaWindow)) point.x = NSMinX(window.frame) + NSMaxX(window.frame) - point.x;
        break;
    }
    return point;
}

static void DPFindHoverReads(void) {
    // Dia build: where the hover check's reads return to in Dia's executable.
    NSDictionary<NSString *, NSArray<NSNumber *> *> *reads = @{ @"90312" : @[ @0x8cd5e0, @0x8cd5f8, @0x8e062c ] };
    NSArray<NSNumber *> *offsets = reads[NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"]];
    if (!offsets || ![@(_dyld_get_image_name(0)) hasSuffix:@"/Contents/MacOS/Dia"]) return;
    for (int i = 0; i < 3; i++) DPHoverReads[i] = (uintptr_t)_dyld_get_image_header(0) + offsets[i].unsignedLongValue;
}

static void DPApplySidebarOnRight(DPPatch *patch) {
    for (NSView *view in DPMirrored.allObjects) {
        view.frame = [DPGet(view, &DPDiaFrameKey) rectValue];
        view.superview.needsLayout = YES;
    }
    DPApplySidebarButton();
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
    DPFindHoverReads();
    if (DPHoverReads[0]) DPHookClass(object_getClass(NSEvent.class), @selector(mouseLocation), (IMP)DPEvent_mouseLocation);
    DPInstallSidebarPopups();
    DPInstallSidebarButton();
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
