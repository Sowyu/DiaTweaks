#import "CompactCommandBar.h"

static char DPFullSizeKey, DPRadiusKey;

// The panel is also Dia's chat.
BOOL DPTrimsPanel(NSView *panel) {
    return DPIsKind(panel.superview.superview, DPDiaNewTabPage) || DPIsKind(panel.superview, "DPCommandBarOverlay");
}

// Command bar sets the size again as it lays out, so a trimmed size maps back to the full one.
static void DPAssistantPanel_setFrameSize(NSView *self, SEL _cmd, NSSize size) {
    NSValue *full = DPDiaValue(self, &DPFullSizeKey, [NSValue valueWithSize:size]);
    NSSize compact = DPTrimsPanel(self) ? DPCompactSize(self, full.sizeValue) : full.sizeValue;
    DPOverride(self, &DPFullSizeKey, full, [NSValue valueWithSize:compact]);
    DPSetTrim(self, full.sizeValue.height - compact.height);
    DPCallOriginal(DPAssistantPanel_setFrameSize, self, compact);
}

static CGFloat DPPageRadius(NSWindow *window) {
    for (NSView *container in DPFindViews(DPDiaContentContainer))
        if (container.window == window)
            for (NSView *sub in container.subviews) if (sub.layer.masksToBounds && sub.layer.cornerRadius > 0) return sub.layer.cornerRadius;
    return 0;
}

// Dia rounds the bar for the taller box it draws on the new tab page, so compacted it would be rounder than anything
// else in the window. Its outer layers take the page's corners instead.
static void DPAssistantPanel_layout(NSView *self, SEL _cmd) {
    DPCallOriginal(DPAssistantPanel_layout, self);
    CGFloat page = DPCompactCommandBar.on && DPTrimsPanel(self) ? DPPageRadius(self.window) : 0;
    for (NSView *sub in self.subviews) {
        CALayer *layer = sub.layer;
        if (!layer || !NSEqualSizes(sub.frame.size, self.bounds.size)) continue;
        NSNumber *dia = DPDiaValue(layer, &DPRadiusKey, @(layer.cornerRadius)), *ours = page > 0 && dia.doubleValue > 0 ? @(page) : dia;
        DPOverride(layer, &DPRadiusKey, dia, ours);
        if (layer.cornerRadius != ours.doubleValue) layer.cornerRadius = ours.doubleValue;
    }
}

void DPInstallNewTabLayout(void) {
    DPHook(DPDiaAssistantPanel, @selector(setFrameSize:), (IMP)DPAssistantPanel_setFrameSize);
    DPHook(DPDiaAssistantPanel, @selector(layout), (IMP)DPAssistantPanel_layout);
}
