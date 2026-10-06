#ifndef private_header_h
#define private_header_h

#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>
#import <stdint.h>

typedef uint32_t WinMuxBorderWindowID;
bool winmux_border_create(float scale, WinMuxBorderWindowID *identifier);
void winmux_border_update(WinMuxBorderWindowID border, uint32_t target, CGRect frame,
                          float radius, uint32_t rgba, float width, bool above);
void winmux_border_move(WinMuxBorderWindowID border, uint32_t target, CGRect frame,
                        float width, bool above);
void winmux_border_move_to_space(WinMuxBorderWindowID border, uint64_t space);
void winmux_border_hide(WinMuxBorderWindowID border);
void winmux_border_destroy(WinMuxBorderWindowID border);
// WindowServer liveness, independent of AX's cached window enumeration.
bool winmux_window_exists(uint32_t window);
bool winmux_window_frame(uint32_t window, CGRect *frame);
typedef void (*WinMuxWindowClosedCallback)(uint32_t window);
bool winmux_watch_window_closures(WinMuxWindowClosedCallback callback);
void winmux_watch_windows(const uint32_t *windows, int count);
typedef void (*WinMuxWindowServerChangedCallback)(uint32_t event, uint32_t window);
bool winmux_watch_mission_control(WinMuxWindowServerChangedCallback callback);

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
