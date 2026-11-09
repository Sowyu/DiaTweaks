#import "StdPatch/StdPatch.h"

extern DPPatch DPSidebarOnRight;
CGFloat DPPageShift(NSWindow *window);

static char DPPopoverOriginKey;

// Dia opens some panels from the sidebar toward the page, which is to the sidebar's right when it's on the left. On the
// right they'd open past the window's edge: a panel beside what it opened from, like a pinned tab's card beside the
// sidebar or History beside Recent tabs, moves to that thing's other side, and one that starts over the sidebar, like
// Recent tabs, moves back inside the window.
static BOOL DPIsPopup(NSWindow *window) {
    return DPIsKind(window, DPDiaOverflowMenu) || DPIsKind(window, DPDiaPinnedTabCard) || DPIsKind(window, DPDiaDropdownPanel);
}

static NSRect DPSidebarOnScreen(NSWindow *window) {
    for (const char *const *name = DPClasses(DPDiaSidebarRoot, DPDiaFloatingSidebar); *name; name++)
        for (NSView *sidebar in DPFindViews(*name))
            if (sidebar.window == window && !sidebar.isHiddenOrHasHiddenAncestor && NSIntersectsRect(sidebar.frame, sidebar.superview.bounds))
                return [window convertRectToScreen:[sidebar convertRect:sidebar.bounds toView:nil]];
    return NSZeroRect;
}

static NSRect DPPopupFrame(NSWindow *popup, NSRect frame) {
    NSWindow *window = popup.parentWindow;
    while (window && !DPIsKind(window, DPDiaWindow)) window = window.parentWindow;  // A panel opened from another panel.
    window = window ?: NSApp.mainWindow;
    if (!DPSidebarOnRight.on || !DPIsKind(window, DPDiaWindow)) return frame;
    NSRect from = DPSidebarOnScreen(window);
    for (NSWindow *other in NSApp.orderedWindows)
        if (other != popup && other.isVisible && DPIsPopup(other) && NSMaxX(other.frame) <= NSMinX(frame) + 1 && NSMaxX(other.frame) > NSMinX(frame) - 40) {
            from = other.frame;
            break;
        }
    if (!NSIsEmptyRect(from) && NSMinX(frame) >= NSMaxX(from) - 1) frame.origin.x = NSMinX(from) + NSMaxX(from) - NSMaxX(frame);
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

// Dia places ⌘L's popover from where it thinks the address field is, as if the sidebar were still on the left, so it
// moves with the page. Edit Address in Toolbar places it over the field itself instead.
static void DPAddressPopover_setFrameOrigin(NSView *self, SEL _cmd, NSPoint origin) {
    NSPoint dia = [DPDiaValue(self, &DPPopoverOriginKey, [NSValue valueWithPoint:origin]) pointValue], ours = dia;
    DPPatch *inToolbar = DPPatchNamed(@"addressInToolbar");
    if (DPSidebarOnRight.on && !(inToolbar && inToolbar->on) && DPIsKind(self.window, DPDiaWindow)) ours.x += DPPageShift(self.window);
    DPOverride(self, &DPPopoverOriginKey, [NSValue valueWithPoint:dia], [NSValue valueWithPoint:ours]);
    DPCallOriginal(DPAddressPopover_setFrameOrigin, self, ours);
}

void DPInstallSidebarPopups(void) {
    DPHook(DPDiaPopover, @selector(setFrameOrigin:), (IMP)DPAddressPopover_setFrameOrigin);
    for (const char *const *name = DPClasses(DPDiaOverflowMenu, DPDiaPinnedTabCard, DPDiaDropdownPanel); *name; name++) {
        DPHook(*name, @selector(setFrame:display:), (IMP)DPPopup_setFrame);
        DPHook(*name, @selector(setFrameOrigin:), (IMP)DPPopup_setFrameOrigin);
        DPHook(*name, @selector(setFrameTopLeftPoint:), (IMP)DPPopup_setFrameTopLeftPoint);
    }
}
