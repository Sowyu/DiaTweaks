#import "CompactCommandBar.h"

static char DPFullSizeKey, DPRadiusKey, DPShadowRadiusKey;

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

static CGFloat DPPageRadius(NSWindow *window);

// The shadow and outline draw from the shadow view's own radius, which Dia sets again after the panel lays out, so it
// changes just before the shadow view draws from it.
static void DPRoundShadow(NSView *shadow) {
    NSView *panel = shadow.superview;
    CGFloat *radius = DPIsKind(panel, DPDiaAssistantPanel) ? DPIvar(shadow, "cornerRadius") : NULL;
    if (!radius) return;
    CGFloat page = DPCompactCommandBar.on && DPTrimsPanel(panel) ? DPPageRadius(shadow.window) : 0;
    NSNumber *dia = DPDiaValue(shadow, &DPShadowRadiusKey, @(*radius)), *ours = page > 0 && dia.doubleValue > 0 ? @(page) : dia;
    DPOverride(shadow, &DPShadowRadiusKey, dia, ours);
    *radius = ours.doubleValue;
}

static void DPShadow_layout(NSView *self, SEL _cmd) {
    DPRoundShadow(self);
    DPCallOriginal(DPShadow_layout, self);
}

static void DPShadow_updateLayer(NSView *self, SEL _cmd) {
    DPRoundShadow(self);
    DPCallOriginal(DPShadow_updateLayer, self);
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
        if (DPIsKind(sub, DPDiaShadowView)) continue;  // Rounded as it lays itself out, below.
        NSNumber *dia = DPDiaValue(layer, &DPRadiusKey, @(layer.cornerRadius)), *ours = page > 0 && dia.doubleValue > 0 ? @(page) : dia;
        DPOverride(layer, &DPRadiusKey, dia, ours);
        if (layer.cornerRadius != ours.doubleValue) layer.cornerRadius = ours.doubleValue;
    }
    for (NSView *sub in self.subviews) if (DPIsKind(sub, DPDiaShadowView)) sub.needsLayout = YES;
}

void DPInstallNewTabLayout(void) {
    DPHook(DPDiaAssistantPanel, @selector(setFrameSize:), (IMP)DPAssistantPanel_setFrameSize);
    DPHook(DPDiaAssistantPanel, @selector(layout), (IMP)DPAssistantPanel_layout);
    DPHook(DPDiaShadowView, @selector(layout), (IMP)DPShadow_layout);
    DPHook(DPDiaShadowView, @selector(updateLayer), (IMP)DPShadow_updateLayer);
}
