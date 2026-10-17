#import "private.h"
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
#import <math.h>
#import <stdatomic.h>
#import <string.h>

// Private ABI stays behind a small C boundary. No borrowed contact pointers leave it.
typedef int (*ContactFrame)(void *, const void *, int, double, int, void *);
static CFArrayRef (*deviceList)(void);
static int (*deviceStart)(void *, int);
static int (*deviceStop)(void *);
static int (*registerFrame)(void *, ContactFrame, void *);
static int (*unregisterFrame)(void *, ContactFrame);
static CFArrayRef retainedDevices, availableDevices;
static _Atomic(WinMuxTouchFrameCallback) receiver;
static IONotificationPortRef topologyPort;
static io_iterator_t addedDevices, removedDevices;
static WinMuxTouchTopologyCallback topologyReceiver;

static int contactFrame(void *device, const void *bytes, int count, double timestamp, int frame, void *context) {
    WinMuxTouchFrameCallback callback = atomic_load_explicit(&receiver, memory_order_acquire);
    if (!callback) return 0;
    int active = 0;
    double x = 0, y = 0;
    uint64_t identities = 0;
    bool valid = count >= 0 && count <= 32 && isfinite(timestamp) && (count == 0 || bytes);
    if (valid) for (int i = 0; i < count; i++) {
        const char *contact = (const char *)bytes + i * 96;
        int32_t state, identifier;
        float px, py;
        memcpy(&state, contact + 20, sizeof(state));
        if (state != 4) continue;
        memcpy(&identifier, contact + 16, sizeof(identifier));
        memcpy(&px, contact + 32, sizeof(px));
        memcpy(&py, contact + 36, sizeof(py));
        if (!isfinite(px) || !isfinite(py) || px < 0 || px > 1 || py < 0 || py > 1) { valid = false; break; }
        active++;
        x += px; y += py;
        // Order-independent contact identity: changing fingers cancels recognition.
        uint64_t identity = ((uint64_t)(uint32_t)identifier + 1) * UINT64_C(0x9e3779b97f4a7c15);
        identity ^= identity >> 27;
        identities += identity * UINT64_C(0xbf58476d1ce4e5b9);
    }
    callback((uint64_t)(uintptr_t)context, (uint64_t)(uintptr_t)device, valid ? active : -1,
             active ? x / active : 0, active ? y / active : 0, timestamp, identities);
    return 0;
}

static bool loadTouchAPI(void) {
    if (deviceList) return true;
    static void *library;
    if (!library) library = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY | RTLD_LOCAL);
    if (!library) return false;
    deviceList = dlsym(library, "MTDeviceCreateList");
    deviceStart = dlsym(library, "MTDeviceStart");
    deviceStop = dlsym(library, "MTDeviceStop");
    registerFrame = dlsym(library, "MTRegisterContactFrameCallbackWithRefcon");
    unregisterFrame = dlsym(library, "MTUnregisterContactFrameCallback");
    if (deviceList && deviceStart && deviceStop && registerFrame && unregisterFrame) return true;
    deviceList = NULL;
    return false;
}

// Start/stop are main-thread operations; callbacks can arrive on driver threads.
void winmux_touch_stop(void) {
    atomic_store_explicit(&receiver, NULL, memory_order_release);
    if (!retainedDevices) return;
    for (CFIndex i = 0; i < CFArrayGetCount(retainedDevices); i++) {
        void *device = (void *)CFArrayGetValueAtIndex(retainedDevices, i);
        if (device) { unregisterFrame(device, contactFrame); deviceStop(device); }
    }
    CFRelease(retainedDevices);
    retainedDevices = NULL;
    if (availableDevices) { CFRelease(availableDevices); availableDevices = NULL; }
}

int winmux_touch_start(uint64_t generation, WinMuxTouchFrameCallback callback) {
    winmux_touch_stop();
    if (!loadTouchAPI()) return -1;
    CFArrayRef devices = deviceList();
    if (!devices) return 0;
    CFMutableArrayRef registered = CFArrayCreateMutable(NULL, 0, NULL);
    atomic_store_explicit(&receiver, callback, memory_order_release);
    for (CFIndex i = 0; i < CFArrayGetCount(devices); i++) {
        void *device = (void *)CFArrayGetValueAtIndex(devices, i);
        if (!device) continue;
        if (registerFrame(device, contactFrame, (void *)(uintptr_t)generation)) {
            CFArrayAppendValue(registered, device);
            deviceStart(device, 0);
        }
    }
    availableDevices = devices;
    retainedDevices = registered;
    return (int)CFArrayGetCount(registered);
}

static void topologyChanged(void *context, io_iterator_t iterator) {
    io_object_t device;
    while ((device = IOIteratorNext(iterator))) IOObjectRelease(device);
    if (topologyReceiver) topologyReceiver();
}

void winmux_touch_unwatch_topology(void) {
    topologyReceiver = NULL;
    if (addedDevices) { IOObjectRelease(addedDevices); addedDevices = 0; }
    if (removedDevices) { IOObjectRelease(removedDevices); removedDevices = 0; }
    if (topologyPort) { IONotificationPortDestroy(topologyPort); topologyPort = NULL; }
}

bool winmux_touch_watch_topology(WinMuxTouchTopologyCallback callback) {
    winmux_touch_unwatch_topology();
    topologyPort = IONotificationPortCreate(kIOMainPortDefault);
    if (!topologyPort) return false;
    IONotificationPortSetDispatchQueue(topologyPort, dispatch_get_main_queue());
    kern_return_t added = IOServiceAddMatchingNotification(topologyPort, kIOFirstMatchNotification,
        IOServiceMatching("AppleMultitouchDevice"), topologyChanged, NULL, &addedDevices);
    kern_return_t removed = IOServiceAddMatchingNotification(topologyPort, kIOTerminatedNotification,
        IOServiceMatching("AppleMultitouchDevice"), topologyChanged, NULL, &removedDevices);
    // Drain initial matches to arm notifications without triggering a restart loop.
    if (added == KERN_SUCCESS) topologyChanged(NULL, addedDevices);
    if (removed == KERN_SUCCESS) topologyChanged(NULL, removedDevices);
    if (added != KERN_SUCCESS || removed != KERN_SUCCESS) { winmux_touch_unwatch_topology(); return false; }
    topologyReceiver = callback;
    return true;
}
