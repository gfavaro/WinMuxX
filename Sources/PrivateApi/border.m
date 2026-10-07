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

static bool createWindow(float scale, uint32_t *identifier) {
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
    if (result || !window) {
        if (window) SYM("SLSReleaseWindow", Window)(cid(), window);
        return false;
    }
    typedef int (*Resolution)(int, uint32_t, double);
    typedef int (*Opacity)(int, uint32_t, bool);
    typedef int (*Tags)(int, uint32_t, uint64_t *, int);
    typedef int (*Shadow)(uint32_t, CFDictionaryRef);
    uint64_t tags = (1ULL << 1) | (1ULL << 9);
    if (SYM("SLSSetWindowResolution", Resolution)(cid(), window, scale) ||
        SYM("SLSSetWindowOpacity", Opacity)(cid(), window, false) ||
        SYM("SLSSetWindowTags", Tags)(cid(), window, &tags, 64)) {
        SYM("SLSReleaseWindow", Window)(cid(), window);
        return false;
    }
    Shadow shadow = SYM("SLSWindowSetShadowProperties", Shadow);
    if (shadow) shadow(window, (__bridge CFDictionaryRef)@{@"com.apple.WindowShadowDensity": @0});
    *identifier = window;
    return true;
}

struct WinMuxBorder { uint32_t windows[4]; CGRect pieces[4]; float scale; };

CGRect winmux_border_piece(CGSize size, float radius, float width, float scale, int index) {
    if (index < 0 || index >= 4 || size.width <= 0 || size.height <= 0 || width <= 0) return CGRectZero;
    scale = MAX(1, scale);
    // Include the final antialiased pixel rather than clipping at a fractional edge.
    size.width = ceil(size.width * scale) / scale;
    size.height = ceil(size.height * scale) / scale;
    // Shared boundaries land on backing pixels. Corner bands contain all curvature.
    CGFloat requestedBand = ceil((MAX(0, radius) + width + 1 / scale) * scale) / scale;
    CGFloat band = MIN(requestedBand, floor(size.height * scale / 2) / scale);
    CGFloat bottomStart = size.height <= requestedBand * 2 ? band : floor((size.height - band) * scale) / scale;
    CGFloat bottomBand = size.height - bottomStart;
    CGFloat middle = MAX(0, bottomStart - band);
    CGFloat requestedEdge = ceil((width + 1 / scale) * scale) / scale;
    CGFloat edge = MIN(requestedEdge, floor(size.width * scale / 2) / scale);
    CGFloat rightStart = size.width <= requestedEdge * 2 ? edge : floor((size.width - edge) * scale) / scale;
    switch (index) {
        case 0: return CGRectMake(0, 0, size.width, band);
        case 1: return CGRectMake(0, size.height - bottomBand, size.width, bottomBand);
        case 2: return CGRectMake(0, band, edge, middle);
        default: return CGRectMake(rightStart, band, size.width - rightStart, middle);
    }
}

bool winmux_border_create(float scale, WinMuxBorderHandle *handle) {
    if (!handle) return false;
    *handle = NULL;
    WinMuxBorderHandle result = calloc(1, sizeof(struct WinMuxBorder));
    if (!result) return false;
    result->scale = scale;
    for (int i = 0; i < 4; ++i) {
        if (!createWindow(scale, &result->windows[i])) {
            winmux_border_destroy(result);
            return false;
        }
    }
    *handle = result;
    return true;
}

uint32_t winmux_border_window_id(WinMuxBorderHandle border, int index) {
    return border && index >= 0 && index < 4 ? border->windows[index] : 0;
}

static void placePiece(CFTypeRef transaction, uint32_t border, uint32_t target, CGPoint origin, bool above) {
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
}

static void roundedRect(CGMutablePathRef path, CGRect rect, CGFloat radius) {
    radius = MAX(0, MIN(radius, MIN(rect.size.width, rect.size.height) / 2));
    CGPathAddRoundedRect(path, NULL, rect, radius, radius);
}

void winmux_border_draw(CGContextRef context, CGSize size, CGRect piece, float radius, uint32_t rgba, float width) {
    CGRect local = { CGPointZero, piece.size };
    CGRect bounds = { CGPointZero, size };
    CGContextClearRect(context, local);
    CGContextSaveGState(context);
    CGContextClipToRect(context, local);
    CGContextTranslateCTM(context, -piece.origin.x, -piece.origin.y);
    CGMutablePathRef ring = CGPathCreateMutable();
    roundedRect(ring, bounds, radius + width);
    CGRect inner = CGRectInset(bounds, width, width);
    if (!CGRectIsEmpty(inner)) roundedRect(ring, inner, radius);
    CGContextSetRGBFillColor(context, ((rgba >> 24) & 255) / 255.0,
        ((rgba >> 16) & 255) / 255.0, ((rgba >> 8) & 255) / 255.0, (rgba & 255) / 255.0);
    CGContextAddPath(context, ring);
    CGContextEOFillPath(context);
    CGPathRelease(ring);
    CGContextRestoreGState(context);
}

static void syncBorderSpace(WinMuxBorderHandle border, uint32_t target) {
    typedef CFArrayRef (*Spaces)(int, int, CFArrayRef);
    typedef int (*MoveSpace)(int, CFArrayRef, uint64_t);
    Spaces spaces = SYM("SLSCopySpacesForWindows", Spaces);
    MoveSpace move = SYM("SLSMoveWindowsToManagedSpace", MoveSpace);
    if (!spaces || !move) return;
    CFArrayRef list = spaces(cid(), 7, (__bridge CFArrayRef)@[@(target)]);
    uint64_t space = 0;
    if (list && CFArrayGetCount(list))
        CFNumberGetValue(CFArrayGetValueAtIndex(list, 0), kCFNumberSInt64Type, &space);
    if (list) CFRelease(list);
    if (space) move(cid(), (__bridge CFArrayRef)@[@(border->windows[0]), @(border->windows[1]),
                                              @(border->windows[2]), @(border->windows[3])], space);
}

static bool placeBorder(WinMuxBorderHandle border, uint32_t target, CGPoint origin, bool above, bool synchronous) {
    syncBorderSpace(border, target);
    CFTypeRef transaction = SYM("SLSTransactionCreate", Transaction)(cid());
    if (!transaction) return false;
    for (int i = 0; i < 4; ++i) {
        if (CGRectIsEmpty(border->pieces[i])) {
            SYM("SLSTransactionOrderWindow", Order)(transaction, border->windows[i], 0, 0);
        } else {
            CGPoint point = CGPointMake(origin.x + border->pieces[i].origin.x, origin.y + border->pieces[i].origin.y);
            placePiece(transaction, border->windows[i], target, point, above);
        }
    }
    int result = SYM("SLSTransactionCommit", Commit)(transaction, synchronous);
    CFRelease(transaction);
    if (result != 0) return false;
    // Small edge windows can be constrained independently at display boundaries.
    // A successful transaction does not guarantee the requested placement.
    for (int i = 0; i < 4; ++i) {
        if (CGRectIsEmpty(border->pieces[i])) continue;
        CGRect actual;
        CGPoint expected = CGPointMake(origin.x + border->pieces[i].origin.x,
                                       origin.y + border->pieces[i].origin.y);
        if (!winmux_window_frame(border->windows[i], &actual) ||
            fabs(actual.origin.x - expected.x) > 1 || fabs(actual.origin.y - expected.y) > 1)
            return false;
    }
    return true;
}

bool winmux_border_update(WinMuxBorderHandle border, uint32_t target, CGRect frame,
                          float radius, uint32_t rgba, float width, bool above) {
    if (!border) return false;
    CGRect outer = CGRectInset(frame, -width, -width);
    CGRect bounds = { CGPointZero, outer.size };
    typedef int (*Shape)(int, uint32_t, float, float, CFTypeRef);
    typedef int (*Flush)(int, uint32_t, void *);
    SYM("SLSDisableUpdate", Update)(cid());
    bool success = true;
    for (int i = 0; i < 4 && success; ++i) {
        CGRect piece = winmux_border_piece(bounds.size, radius, width, border->scale, i);
        border->pieces[i] = piece;
        if (CGRectIsEmpty(piece)) continue;
        CGRect local = { CGPointZero, piece.size };
        CFTypeRef region = NULL;
        success = !SYM("CGSNewRegionWithRect", Region)(&local, &region) && region;
        if (!success) break;
        success = !SYM("SLSSetWindowShape", Shape)(cid(), border->windows[i], 0, 0, region);
        CFRelease(region);
        if (!success) break;
        // Allocate only this edge's backing surface, after reshaping.
        CGContextRef context = SYM("SLWindowContextCreate", Context)(cid(), border->windows[i], NULL);
        if (!context) { success = false; break; }
        winmux_border_draw(context, bounds.size, piece, radius, rgba, width);
        CGContextFlush(context);
        CGContextRelease(context);
        success = !SYM("SLSFlushWindowContentRegion", Flush)(cid(), border->windows[i], NULL);
    }
    if (success) success = placeBorder(border, target, outer.origin, above, true);
    if (!success) winmux_border_hide(border);
    SYM("SLSReenableUpdate", Update)(cid());
    return success;
}

bool winmux_border_move(WinMuxBorderHandle border, uint32_t target, CGRect frame, float width, bool above) {
    return border && placeBorder(border, target, CGRectInset(frame, -width, -width).origin, above, true);
}

void winmux_border_hide(WinMuxBorderHandle border) {
    if (!border) return;
    CFTypeRef transaction = SYM("SLSTransactionCreate", Transaction)(cid());
    if (!transaction) return;
    for (int i = 0; i < 4; ++i)
        if (border->windows[i]) SYM("SLSTransactionOrderWindow", Order)(transaction, border->windows[i], 0, 0);
    SYM("SLSTransactionCommit", Commit)(transaction, true);
    CFRelease(transaction);
}

void winmux_border_destroy(WinMuxBorderHandle border) {
    if (!border) return;
    Window release = sky() ? SYM("SLSReleaseWindow", Window) : NULL;
    if (release) for (int i = 0; i < 4; ++i) if (border->windows[i]) release(cid(), border->windows[i]);
    free(border);
}
