#import "StdPatch/StdPatch.h"

extern DPPatch DPCompactMode;

static NSHashTable<NSWindow *> *DPCollapsed;  // Windows whose sidebar compact mode put away, so it brings them back.
#define DPDiaSidebarList "_TtC10TabSidebar15SidebarRootView"

static NSDictionary *DPDefaultCompactShortcut(void) {
    return @{ @"keyCode" : @8, @"modifiers" : @(NSEventModifierFlagControl | NSEventModifierFlagOption), @"key" : @"C" };
}

static BOOL DPHides(NSString *part) {
    NSString *hides = DPChoice(&DPCompactMode);
    return DPCompactMode.on && ([hides isEqual:@"both"] || [hides isEqual:part]);
}

// Docked, rather than floating out over the page while it's put away.
static BOOL DPSidebarDocked(NSWindow *window) {
    for (NSView *sidebar in DPFindViews(DPDiaSidebarRoot)) {
        if (sidebar.window != window || sidebar.isHiddenOrHasHiddenAncestor || NSWidth(sidebar.frame) < 1) continue;
        BOOL floating = NO;
        for (NSView *view = sidebar.superview; view && !floating; view = view.superview) floating = DPIsKind(view, DPDiaFloatingSidebar);
        if (!floating) return YES;
    }
    return NO;
}

// Dia's own toolbar button, so the sidebar still floats out when the mouse reaches its edge.
static void DPToggleSidebar(NSWindow *window) {
    NSView *button = DPFindView(window.contentView.superview, ^BOOL(NSView *view) { return DPHasLabel(view, @"Toggle sidebar"); });
    [button accessibilityPerformPress];
}

static void DPCompactWindow(NSWindow *window) {
    if (!DPIsKind(window, DPDiaWindow) || !window.isVisible) return;
    BOOL hide = DPHides(@"sidebar"), docked = DPSidebarDocked(window);
    if (hide && docked) {
        [DPCollapsed addObject:window];
        DPToggleSidebar(window);
    } else if (!hide && [DPCollapsed containsObject:window]) {
        [DPCollapsed removeObject:window];
        if (!docked) DPToggleSidebar(window);
    }
}

// The toolbar hides with Hide Toolbar and comes back on hover, both just while compact mode is on, so your own
// settings for them come back with it off.
static void DPApplyCompactMode(DPPatch *patch) {
    for (NSWindow *window in NSApp.windows) DPCompactWindow(window);
    DPPatch *hide = DPPatchNamed(@"hideToolbar"), *reveal = DPPatchNamed(@"revealToolbarOnHover");
    if (!hide || !reveal || hide->unavailable) return;
    BOOL toolbar = DPHides(@"toolbar");
    if (hide->on != (toolbar || DPSavedOn(hide))) DPSetPatch(hide, toolbar || DPSavedOn(hide), NO);
    if (reveal->on != (toolbar || DPSavedOn(reveal))) DPSetPatch(reveal, toolbar || DPSavedOn(reveal), NO);
}

static void DPSetCompact(BOOL on, NSString *hides) {
    if (hides) DPSetChoice(&DPCompactMode, hides);
    if (DPCompactMode.on != on) DPSetPatch(&DPCompactMode, on, YES);
    else DPApplyCompactMode(&DPCompactMode);
    [NSNotificationCenter.defaultCenter postNotificationName:DPPatchesDidChangeNotification object:nil];
}

// Like Zen's, on the sidebar's right-click menu.
static NSMenuItem *DPCompactMenu(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Compact Mode"];
    NSMenuItem *enable = DPMenuItem(@"Enable Compact Mode", ^{ DPSetCompact(!DPCompactMode.on, nil); });
    enable.state = DPCompactMode.on ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:enable];
    [menu addItem:NSMenuItem.separatorItem];
    for (NSArray<NSString *> *choice in @[ @[ @"Hide Sidebar", @"sidebar" ], @[ @"Hide Toolbar", @"toolbar" ], @[ @"Hide Both", @"both" ] ]) {
        NSMenuItem *item = DPMenuItem(choice[0], ^{ DPSetCompact(DPCompactMode.on, choice[1]); });
        item.state = [DPChoice(&DPCompactMode) isEqual:choice[1]] ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Compact Mode" action:nil keyEquivalent:@""];
    item.submenu = menu;
    return item;
}

static NSMenu *DPSidebar_menuForEvent(NSView *self, SEL _cmd, NSEvent *event) {
    NSMenu *menu = DPCallOriginal(DPSidebar_menuForEvent, self, event);
    if (!menu || DPCompactMode.unavailable) return menu;
    [menu insertItem:NSMenuItem.separatorItem atIndex:0];
    [menu insertItem:DPCompactMenu() atIndex:0];
    return menu;
}

static NSMenu *DPCompactChoices(void) {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Hide"];
    for (NSArray *choice in @[ @[ @"Sidebar", @"sidebar" ], @[ @"Toolbar", @"toolbar" ], @[ @"Sidebar and Toolbar", @"both" ] ]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:choice[0] action:nil keyEquivalent:@""];
        item.representedObject = choice[1];
        [menu addItem:item];
    }
    return menu;
}

static void DPInstallCompactMode(void) {
    DPCollapsed = [NSHashTable weakObjectsHashTable];
    DPHook(DPDiaSidebarRoot, @selector(menuForEvent:), (IMP)DPSidebar_menuForEvent);
    DPHook(DPDiaSidebarList, @selector(menuForEvent:), (IMP)DPSidebar_menuForEvent);
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        if (event.isARepeat || !DPShortcutMatches(event, &DPCompactMode)) return event;
        DPSetCompact(!DPCompactMode.on, nil);
        return nil;
    }];
    // A window opened or brought back while compact mode is on gets it too.
    [NSNotificationCenter.defaultCenter addObserverForName:NSWindowDidBecomeMainNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        if (DPCompactMode.on) DPCompactWindow(note.object);
    }];
    DPOnLaunch(^{ dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ DPApplyCompactMode(&DPCompactMode); }); });
}

DP_PATCH(DPCompactMode) {
    .key = @"compactMode",
    .title = @"Compact Mode",
    .detail = @"Hide the sidebar, the toolbar or both, like Zen, and bring each back by moving to its edge. Turn it on and off with ⌃⌥C or from the sidebar’s right-click menu.",
    .symbol = @"arrow.down.right.and.arrow.up.left",
    .tint = @"systemBrownColor",
    .section = @"Window",
    .choice = @"compactModeHides",
    .defaultChoice = @"both",
    .choices = DPCompactChoices,
    .shortcut = @"compactModeShortcut",
    .defaultShortcut = DPDefaultCompactShortcut,
    .classes = DPClasses(DPDiaSidebarRoot, DPDiaSidebarList, DPDiaFloatingSidebar, DPDiaWindow),
    .install = DPInstallCompactMode,
    .apply = DPApplyCompactMode,
};
