#ifndef private_header_h
#define private_header_h

#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>
#import <stdint.h>

typedef struct WinMuxBorder *WinMuxBorderHandle;
bool winmux_border_create(float scale, WinMuxBorderHandle *handle);
bool winmux_border_update(WinMuxBorderHandle border, uint32_t target, CGRect frame,
                         float radius, uint32_t rgba, float width, bool above, CGPathRef path);
bool winmux_border_move(WinMuxBorderHandle border, uint32_t target, CGRect frame,
                       float width, bool above);
void winmux_border_hide(WinMuxBorderHandle border);
void winmux_border_destroy(WinMuxBorderHandle border);
uint32_t winmux_border_window_id(WinMuxBorderHandle border, int index);
void winmux_border_draw(CGContextRef context, CGSize size, CGRect piece, float radius, uint32_t rgba, float width);
void winmux_border_draw_path(CGContextRef context, CGRect piece, CGPathRef path, uint32_t rgba);
CGRect winmux_border_piece(CGSize size, float radius, float width, float scale, int index);
// WindowServer liveness, independent of AX's cached window enumeration.
bool winmux_window_exists(uint32_t window);
bool winmux_window_frame(uint32_t window, CGRect *frame);
typedef void (*WinMuxWindowClosedCallback)(uint32_t window);
bool winmux_watch_window_closures(WinMuxWindowClosedCallback callback);
void winmux_watch_windows(const uint32_t *windows, int count);
typedef void (*WinMuxWindowServerChangedCallback)(uint32_t event, uint32_t window);
bool winmux_watch_mission_control(WinMuxWindowServerChangedCallback callback);

// Raw trackpad frames: copied summaries only, no private pointers exposed to Swift.
typedef void (*WinMuxTouchFrameCallback)(uint64_t generation, uint64_t device, int32_t fingers,
                                       double x, double y, double timestamp, uint64_t contacts);
typedef void (*WinMuxTouchTopologyCallback)(void);
int winmux_touch_start(uint64_t generation, WinMuxTouchFrameCallback callback);
void winmux_touch_stop(void);
bool winmux_touch_watch_topology(WinMuxTouchTopologyCallback callback);
void winmux_touch_unwatch_topology(void);

// Potential alternative 1?
// func allWindowsOnCurrentMacOsSpace() {
//     let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
//     let windowsListInfo = CGWindowListCopyWindowInfo(options, CGWindowID(0))
//     let infoList = windowsListInfo as! [[String:Any]]
//     let windows = infoList.filter { $0["kCGWindowLayer"] as! Int == 0 }
//     print(windows.count)
//     for window in windows {
//             print(window)
//             print("Name: \(window["kCGWindowOwnerName"].unsafelyUnwrapped)")
//             print("PID: \(window["kCGWindowOwnerPID"].unsafelyUnwrapped)")
//             print("window ID: \(window["kCGWindowNumber"])")
//             print("---")
//     }
// }
//
// Alternative 2:
// @_silgen_name("_AXUIElementGetWindow")
// @discardableResult
// func _AXUIElementGetWindow(_ axUiElement: AXUIElement, _ id: inout CGWindowID) -> AXError
AXError _AXUIElementGetWindow(AXUIElementRef element, uint32_t *identifier);

#endif
