#import "private.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>

// Keep the private ABI here. Shape coordinates and placement follow Dinky's
// local-shape implementation; do not add JankyBorders' global-shape transform.
static void *sky(void) {
    static void *handle;
    if (!handle) handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
    return handle;
}
#define SYM(name, type) ((type)dlsym(sky(), name))
typedef int (*Connection)(void);
typedef int (*Region)(CGRect *, CFTypeRef *);
typedef int (*NewWindow)(int, int, float, float, CFTypeRef, uint32_t *);
typedef int (*Window)(int, uint32_t);
typedef CFTypeRef (*Transaction)(int);
typedef int (*Order)(CFTypeRef, uint32_t, int, uint32_t);
typedef int (*Move)(CFTypeRef, uint32_t, CGPoint);
typedef int (*Commit)(CFTypeRef, int);
typedef int (*Update)(int);
typedef CGContextRef (*Context)(int, uint32_t, CFDictionaryRef);
static int cid(void) { return SYM("SLSMainConnectionID", Connection)(); }

static WinMuxWindowClosedCallback closedCallback;
static WinMuxWindowServerChangedCallback missionControlCallback;
static void missionControlChanged(uint32_t event, void *data, size_t length, void *context) {
    (void)context;
    uint32_t window = 0;
    size_t offset = (event == 1325 || event == 1326) ? sizeof(uint64_t) : 0;
    if (data && length >= offset + sizeof(window))
        memcpy(&window, (const char *)data + offset, sizeof(window));
    // SkyLight can invoke notify procs on AppKit's event thread. Swift's
    // registered closures are MainActor-isolated: cross that boundary here.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (missionControlCallback) missionControlCallback(event, window);
    });
}

bool winmux_watch_mission_control(WinMuxWindowServerChangedCallback callback) {
    typedef int (*Register)(void *, uint32_t, void *);
    Register registerNotify = sky() ? SYM("SLSRegisterNotifyProc", Register) : NULL;
    if (!registerNotify) return false;
    missionControlCallback = callback;
    // WindowManager's display-sized overview window is ordered in/out on
    // macOS 27. Also observe creation and level/size changes during transition.
    const uint32_t events[] = {1204, 1325, 1326, 723, 806, 807, 808, 815, 816, 811};
    bool success = true;
    for (unsigned i = 0; i < sizeof(events) / sizeof(events[0]); ++i)
        if (registerNotify((void *)missionControlChanged, events[i], NULL)) success = false;
    return success;
}
static void nativeWindowClosed(uint32_t event, void *data, size_t length, void *context) {
    (void)context;
    // JankyBorders events.h: close (804) carries a window id; destroy
    // (1326) carries a uint64 Space id followed by a uint32 window id.
    size_t offset = event == 1326 ? sizeof(uint64_t) : 0;
    if (!data || length < offset + sizeof(uint32_t)) return;
    uint32_t window;
    memcpy(&window, (const char *)data + offset, sizeof(window));
    // 1326 can also mean "left this Space", not destruction of the window.
    if (event == 1326 && winmux_window_exists(window)) return;
    if (window) dispatch_async(dispatch_get_main_queue(), ^{
        if (closedCallback) closedCallback(window);
    });
}

bool winmux_watch_window_closures(WinMuxWindowClosedCallback callback) {
    typedef int (*Register)(void *, uint32_t, void *);
    Register registerNotify = sky() ? SYM("SLSRegisterNotifyProc", Register) : NULL;
    if (!registerNotify) return false;
    closedCallback = callback;
    int closeResult = registerNotify((void *)nativeWindowClosed, 804, NULL);
    int destroyResult = registerNotify((void *)nativeWindowClosed, 1326, NULL);
    return !closeResult && !destroyResult;
}

void winmux_watch_windows(const uint32_t *windows, int count) {
    typedef int (*Request)(int, const uint32_t *, int);
    Request request = sky() ? SYM("SLSRequestNotificationsForWindows", Request) : NULL;
    if (request && windows && count > 0) request(cid(), windows, count);
}

bool winmux_window_exists(uint32_t window) {
    typedef int (*Bounds)(int, uint32_t, CGRect *);
    Bounds bounds = sky() ? SYM("SLSGetWindowBounds", Bounds) : NULL;
    Connection connection = sky() ? SYM("SLSMainConnectionID", Connection) : NULL;
    if (!bounds || !connection) return true; // Preserve AX fallback on unsupported systems.
    CGRect frame;
    return bounds(connection(), window, &frame) == kCGErrorSuccess;
}

bool winmux_window_frame(uint32_t window, CGRect *frame) {
    typedef int (*Bounds)(int, uint32_t, CGRect *);
    Bounds bounds = sky() ? SYM("SLSGetWindowBounds", Bounds) : NULL;
    Connection connection = sky() ? SYM("SLSMainConnectionID", Connection) : NULL;
    if (!frame || !bounds || !connection) return false;
    CGRect nativeFrame;
    if (bounds(connection(), window, &nativeFrame) != kCGErrorSuccess) return false;
    *frame = nativeFrame;
    return true;
}

bool winmux_border_create(float scale, WinMuxBorderWindowID *identifier) {
    if (!identifier || !sky()) return false;
    const char *required[] = {
        "SLSMainConnectionID", "CGSNewRegionWithRect", "SLSNewWindow",
        "SLSReleaseWindow", "SLSSetWindowShape", "SLWindowContextCreate",
        "SLSDisableUpdate", "SLSReenableUpdate", "SLSTransactionCreate",
        "SLSTransactionMoveWindowWithGroup", "SLSTransactionOrderWindow",
        "SLSTransactionCommit", "SLSSetWindowResolution", "SLSSetWindowOpacity",
        "SLSSetWindowTags", "SLSFlushWindowContentRegion"
    };
    for (unsigned i = 0; i < sizeof(required) / sizeof(required[0]); ++i)
        if (!dlsym(sky(), required[i])) return false;
    CGRect bounds = CGRectMake(0, 0, 1, 1);
    CFTypeRef region = NULL;
    if (SYM("CGSNewRegionWithRect", Region)(&bounds, &region) || !region) return false;
    uint32_t window = 0;
    int result = SYM("SLSNewWindow", NewWindow)(cid(), 2, -9999, -9999, region, &window);
    CFRelease(region);
    if (result || !window) return false;
    typedef int (*Resolution)(int, uint32_t, double);
    typedef int (*Opacity)(int, uint32_t, bool);
    typedef int (*Tags)(int, uint32_t, uint64_t *, int);
    typedef int (*Shadow)(uint32_t, CFDictionaryRef);
    SYM("SLSSetWindowResolution", Resolution)(cid(), window, scale);
    SYM("SLSSetWindowOpacity", Opacity)(cid(), window, false);
    uint64_t tags = (1ULL << 1) | (1ULL << 9);
    SYM("SLSSetWindowTags", Tags)(cid(), window, &tags, 64);
    Shadow shadow = SYM("SLSWindowSetShadowProperties", Shadow);
    if (shadow) shadow(window, (__bridge CFDictionaryRef)@{@"com.apple.WindowShadowDensity": @0});
    *identifier = window;
    return true;
}

static void place(uint32_t border, uint32_t target, CGPoint origin, bool above, bool synchronous) {
    typedef CFArrayRef (*Spaces)(int, int, CFArrayRef);
    Spaces spaces = SYM("SLSCopySpacesForWindows", Spaces);
    if (spaces) {
        CFArrayRef list = spaces(cid(), 7, (__bridge CFArrayRef)@[@(target)]);
        uint64_t space = 0;
        if (list && CFArrayGetCount(list))
            CFNumberGetValue(CFArrayGetValueAtIndex(list, 0), kCFNumberSInt64Type, &space);
        if (list) CFRelease(list);
        if (space) winmux_border_move_to_space(border, space);
    }
    CFTypeRef transaction = SYM("SLSTransactionCreate", Transaction)(cid());
    if (!transaction) return;
    SYM("SLSTransactionMoveWindowWithGroup", Move)(transaction, border, origin);
    typedef int (*GetLevel)(int, uint32_t, int64_t *);
    typedef int (*SetLevel)(CFTypeRef, uint32_t, int);
    typedef int32_t (*GetSubLevel)(int, uint32_t);
    GetLevel getLevel = SYM("SLSGetWindowLevel", GetLevel);
    SetLevel setLevel = SYM("SLSTransactionSetWindowLevel", SetLevel);
    int64_t level = 0;
    if (getLevel && setLevel && !getLevel(cid(), target, &level))
        setLevel(transaction, border, (int)level);
    GetSubLevel getSubLevel = SYM("SLSGetWindowSubLevel", GetSubLevel);
    SetLevel setSubLevel = SYM("SLSTransactionSetWindowSubLevel", SetLevel);
    if (getSubLevel && setSubLevel)
        setSubLevel(transaction, border, getSubLevel(cid(), target));
    SYM("SLSTransactionOrderWindow", Order)(transaction, border, above ? 1 : -1, target);
    SYM("SLSTransactionCommit", Commit)(transaction, synchronous);
    CFRelease(transaction);
}

static void roundedRect(CGMutablePathRef path, CGRect rect, CGFloat radius) {
    radius = MAX(0, MIN(radius, MIN(rect.size.width, rect.size.height) / 2));
    CGPathAddRoundedRect(path, NULL, rect, radius, radius);
}

void winmux_border_update(uint32_t border, uint32_t target, CGRect frame,
                          float radius, uint32_t rgba, float width, bool above) {
    if (!border) return;
    CGRect outer = CGRectInset(frame, -width, -width);
    CGRect bounds = { CGPointZero, outer.size };
    CFTypeRef region = NULL;
    if (SYM("CGSNewRegionWithRect", Region)(&bounds, &region) || !region) return;
    typedef int (*Shape)(int, uint32_t, float, float, CFTypeRef);
    typedef int (*Flush)(int, uint32_t, void *);
    SYM("SLSDisableUpdate", Update)(cid());
    SYM("SLSSetWindowShape", Shape)(cid(), border, 0, 0, region);
    // A context created before reshape can retain the previous backing surface.
    CGContextRef context = SYM("SLWindowContextCreate", Context)(cid(), border, NULL);
    if (context) {
        CGMutablePathRef ring = CGPathCreateMutable();
        roundedRect(ring, bounds, radius + width);
        roundedRect(ring, CGRectInset(bounds, width, width), radius);
        CGContextClearRect(context, bounds);
        CGContextSetRGBFillColor(context, ((rgba >> 24) & 255) / 255.0,
            ((rgba >> 16) & 255) / 255.0, ((rgba >> 8) & 255) / 255.0, (rgba & 255) / 255.0);
        CGContextAddPath(context, ring);
        CGContextEOFillPath(context);
        CGPathRelease(ring);
        CGContextFlush(context);
        CGContextRelease(context);
        SYM("SLSFlushWindowContentRegion", Flush)(cid(), border, NULL);
        place(border, target, outer.origin, above, true);
    } else {
        winmux_border_hide(border);
    }
    SYM("SLSReenableUpdate", Update)(cid());
    CFRelease(region);
}

void winmux_border_move(uint32_t border, uint32_t target, CGRect frame, float width, bool above) {
    if (border) place(border, target, CGRectInset(frame, -width, -width).origin, above, false);
}

void winmux_border_move_to_space(uint32_t border, uint64_t space) {
    typedef int (*MoveSpace)(int, CFArrayRef, uint64_t);
    MoveSpace move = SYM("SLSMoveWindowsToManagedSpace", MoveSpace);
    if (border && space && move) move(cid(), (__bridge CFArrayRef)@[@(border)], space);
}

void winmux_border_hide(uint32_t border) {
    if (!border) return;
    CFTypeRef transaction = SYM("SLSTransactionCreate", Transaction)(cid());
    if (!transaction) return;
    SYM("SLSTransactionOrderWindow", Order)(transaction, border, 0, 0);
    SYM("SLSTransactionCommit", Commit)(transaction, true);
    CFRelease(transaction);
}

void winmux_border_destroy(uint32_t border) {
    Window release = SYM("SLSReleaseWindow", Window);
    if (border && release) release(cid(), border);
}
