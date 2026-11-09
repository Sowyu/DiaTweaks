#import "StdPatch/StdPatch.h"

extern DPPatch DPSidebarOnRight;

static char DPToolbarFrameKey, DPIconKey;

static BOOL DPIsSidebarButton(NSView *view) {
    return DPHasLabel(view, @"Toggle sidebar");
}

// With the sidebar on the right, its toolbar button moves to the toolbar's right end, beside the sidebar, and shows the
// sidebar on that side. The items after it move along by the button's place, so the row stays evenly spaced.
static void DPPlaceSidebarButton(NSView *button) {
    NSView *row = button.superview;
    NSRect buttonFrame = [DPDiaValue(button, &DPToolbarFrameKey, @(button.frame)) rectValue];
    BOOL move = DPSidebarOnRight.on && !button.hidden && NSWidth(buttonFrame) > 0;
    CGFloat next = CGFLOAT_MAX;
    for (NSView *item in row.subviews) {
        NSRect frame = [DPDiaValue(item, &DPToolbarFrameKey, @(item.frame)) rectValue];
        if (NSWidth(frame) > 0 && NSMinX(frame) > NSMaxX(buttonFrame)) next = MIN(next, NSMinX(frame));
    }
    CGFloat shift = next == CGFLOAT_MAX ? 0 : next - NSMinX(buttonFrame);
    for (NSView *item in row.subviews) {
        NSRect dia = [DPDiaValue(item, &DPToolbarFrameKey, @(item.frame)) rectValue], ours = dia;
        if (move && item == button) ours.origin.x = NSWidth(row.bounds) - NSMaxX(dia);
        else if (move && NSMinX(dia) > NSMaxX(buttonFrame)) ours.origin.x -= shift;
        DPOverride(item, &DPToolbarFrameKey, @(dia), @(ours));
        if (!NSEqualRects(item.frame, ours) && DPMayAdjust(item)) item.frame = ours;
    }

    NSImageView *icon = (NSImageView *)DPSubview(button, "NSImageView");
    NSImage *dia = DPDiaValue(icon, &DPIconKey, icon.image), *ours = dia;
    if (move && dia) {
        NSImage *right = [NSImage imageWithSystemSymbolName:@"sidebar.right" accessibilityDescription:dia.accessibilityDescription];
        ours = (dia.symbolConfiguration ? [right imageWithSymbolConfiguration:dia.symbolConfiguration] : right) ?: dia;
        ours.template = dia.template;
    }
    DPOverride(icon, &DPIconKey, dia, ours);
    if (icon && icon.image != ours) icon.image = ours;
}

static void DPPlaceSidebarButtonIn(NSView *toolbar) {
    NSView *button = DPFindView(toolbar, ^BOOL(NSView *view) { return DPIsSidebarButton(view); });
    if (button) DPPlaceSidebarButton(button);
}

static void DPToolbar_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPToolbar_layout, self);
    DPPlaceSidebarButtonIn(self);
}

void DPApplySidebarButton(void) {
    for (NSView *toolbar in DPFindViews(DPDiaToolbar)) DPPlaceSidebarButtonIn(toolbar);
}

void DPInstallSidebarButton(void) {
    DPHook(DPDiaToolbar, @selector(layout), (IMP)DPToolbar_layout);
}
