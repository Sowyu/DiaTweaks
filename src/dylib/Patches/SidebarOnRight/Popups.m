#import "StdPatch/StdPatch.h"

extern DPPatch DPSidebarOnRight;

// Dia opens some panels from the sidebar toward the page, which is to the sidebar's right when it's on the left. On the
// right they'd open past the window's edge: a panel beside the sidebar, like a pinned tab's card, moves to its other
// side, and one that starts over the sidebar, like Recent tabs, moves back inside the window.
static NSRect DPSidebarOnScreen(NSWindow *window) {
    for (const char *const *name = DPClasses(DPDiaSidebarRoot, DPDiaFloatingSidebar); *name; name++)
        for (NSView *sidebar in DPFindViews(*name))
            if (sidebar.window == window && !sidebar.isHiddenOrHasHiddenAncestor && NSIntersectsRect(sidebar.frame, sidebar.superview.bounds))
                return [window convertRectToScreen:[sidebar convertRect:sidebar.bounds toView:nil]];
    return NSZeroRect;
}

static NSRect DPPopupFrame(NSWindow *popup, NSRect frame) {
    NSWindow *window = popup.parentWindow ?: NSApp.keyWindow;
    if (!DPSidebarOnRight.on || !DPIsKind(window, DPDiaWindow)) return frame;
    NSRect sidebar = DPSidebarOnScreen(window);
    if (!NSIsEmptyRect(sidebar) && NSMinX(frame) >= NSMaxX(sidebar) - 1) frame.origin.x = NSMinX(sidebar) + NSMaxX(sidebar) - NSMaxX(frame);
    else if (NSMaxX(frame) > NSMaxX(window.frame)) frame.origin.x = NSMaxX(window.frame) - NSWidth(frame);
    return frame;
}

static void DPPopup_setFrame(NSWindow *self, SEL _cmd, NSRect frame, BOOL display) {
    DPCallOriginal(DPPopup_setFrame, self, DPPopupFrame(self, frame), display);
}

static void DPPopup_setFrameOrigin(NSWindow *self, SEL _cmd, NSPoint origin) {
    DPCallOriginal(DPPopup_setFrameOrigin, self, DPPopupFrame(self, (NSRect){ origin, self.frame.size }).origin);
}

static void DPPopup_setFrameTopLeftPoint(NSWindow *self, SEL _cmd, NSPoint point) {
    NSRect frame = DPPopupFrame(self, NSMakeRect(point.x, point.y - NSHeight(self.frame), NSWidth(self.frame), NSHeight(self.frame)));
    DPCallOriginal(DPPopup_setFrameTopLeftPoint, self, NSMakePoint(NSMinX(frame), NSMaxY(frame)));
}

void DPInstallSidebarPopups(void) {
    for (const char *const *name = DPClasses(DPDiaOverflowMenu, DPDiaPinnedTabCard, DPDiaDropdownPanel); *name; name++) {
        DPHook(*name, @selector(setFrame:display:), (IMP)DPPopup_setFrame);
        DPHook(*name, @selector(setFrameOrigin:), (IMP)DPPopup_setFrameOrigin);
        DPHook(*name, @selector(setFrameTopLeftPoint:), (IMP)DPPopup_setFrameTopLeftPoint);
    }
}
