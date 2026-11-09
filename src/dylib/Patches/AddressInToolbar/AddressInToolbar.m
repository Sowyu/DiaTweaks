#import "StdPatch/StdPatch.h"

extern DPPatch DPAddressInToolbar;

static const CGFloat DPInset = 10;  // Between the popover's edge and its bar, so the bar's text lines up with the field's.

// The address field ⌘L's popover opens over: a visible one in the same window whose row the popover's top reaches.
static NSView *DPFieldUnder(NSView *popover) {
    NSView *root = popover.superview;
    if (!root || !popover.window) return nil;
    for (NSView *field in DPFindViews(DPDiaAddressField)) {
        if (field.window != popover.window || field.isHiddenOrHasHiddenAncestor || NSWidth(field.frame) < 1) continue;
        NSRect row = [field convertRect:field.bounds toView:root], frame = popover.frame;
        CGFloat top = root.isFlipped ? NSMinY(frame) : NSMaxY(frame), rowTop = root.isFlipped ? NSMinY(row) : NSMaxY(row);
        if (fabs(top - rowTop) < 40) return field;
    }
    return nil;
}

// Dia's popover runs from left of the field to the window's edge. Like Zen, it covers just the field instead.
static NSRect DPOverField(NSView *popover, NSRect frame) {
    NSView *field = DPAddressInToolbar.on ? DPFieldUnder(popover) : nil;
    if (!field) return frame;
    NSRect row = [field convertRect:field.bounds toView:popover.superview];
    frame.origin.x = NSMinX(row) - DPInset;
    frame.size.width = NSWidth(row) + 2 * DPInset;
    return frame;
}

static void DPPopover_setFrameOrigin(NSView *self, SEL _cmd, NSPoint origin) {
    DPCallOriginal(DPPopover_setFrameOrigin, self, DPOverField(self, (NSRect){ origin, self.frame.size }).origin);
}

static void DPPopover_setFrameSize(NSView *self, SEL _cmd, NSSize size) {
    NSRect frame = DPOverField(self, (NSRect){ self.frame.origin, size });
    DPCallOriginal(DPPopover_setFrameSize, self, frame.size);
    if (NSMinX(self.frame) != NSMinX(frame)) [self setFrameOrigin:self.frame.origin];
}

static void DPApplyAddressInToolbar(DPPatch *patch) {
    for (NSView *popover in DPFindViews(DPDiaPopover)) popover.superview.needsLayout = YES;
}

static void DPInstallAddressInToolbar(void) {
    DPHook(DPDiaPopover, @selector(setFrameOrigin:), (IMP)DPPopover_setFrameOrigin);
    DPHook(DPDiaPopover, @selector(setFrameSize:), (IMP)DPPopover_setFrameSize);
}

DP_PATCH(DPAddressInToolbar) {
    .key = @"addressInToolbar",
    .title = @"Edit Address in Toolbar",
    .detail = @"Open the address bar right over the address field, the same width, like Zen, instead of a popover that runs to the window’s edge.",
    .symbol = @"character.cursor.ibeam",
    .tint = @"systemIndigoColor",
    .section = @"Toolbar",
    .classes = DPClasses(DPDiaPopover, DPDiaAddressField),
    .install = DPInstallAddressInToolbar,
    .apply = DPApplyAddressInToolbar,
};
