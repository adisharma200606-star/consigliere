#import "include/RotationBridge.h"

#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/graphics/IOGraphicsTypes.h>
#import <dlfcn.h>

// CGDisplayIOServicePort is still exported by ApplicationServices, but recent SDK headers no longer
// declare it (it was quietly deprecated).
extern io_service_t CGDisplayIOServicePort(CGDirectDisplayID display);

// System Settings rotates the screen through private classes, MPDisplay and MPDisplayMgr, in a private
// framework, MonitorPanel. None of them is in a public header, so the compiler has no idea these methods
// exist. This category is a white lie that fixes that: it tells the compiler "some class somewhere
// implements these", which is all Objective-C needs to let us write ordinary message sends below. At run
// time the real MonitorPanel implementations run; nothing here overrides anything. Every call is guarded
// by respondsToSelector:, so a macOS update that renames one of them fails politely instead of crashing.
@interface NSObject (ConsigliereMonitorPanel)
- (instancetype)initWithCGSDisplayID:(CGDirectDisplayID)displayID;
- (void)setOrientation:(NSInteger)orientation;
- (NSInteger)orientation;
- (BOOL)canChangeOrientation;
- (id)displayWithID:(CGDirectDisplayID)displayID;
- (NSArray *)displays;
- (CGDirectDisplayID)displayID;
@end

static void ConsigliereSetError(char **outError, NSString *message) {
    if (outError != NULL) {
        free(*outError);
        const char *utf8 = message.UTF8String ?: "unknown rotation error";
        *outError = strdup(utf8);
    }
}

static BOOL ConsigliereLoadMonitorPanel(void) {
    static void *handle;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        handle = dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel",
                        RTLD_LAZY | RTLD_LOCAL);
    });
    return handle != NULL;
}

/// A fresh MPDisplay for this ID, or nil.
static id ConsigliereFreshDisplay(CGDirectDisplayID displayID) {
    if (!ConsigliereLoadMonitorPanel()) { return nil; }
    Class cls = NSClassFromString(@"MPDisplay");
    if (cls == Nil || ![cls instancesRespondToSelector:@selector(initWithCGSDisplayID:)]) { return nil; }
    return [[cls alloc] initWithCGSDisplayID:displayID];
}

/// The MPDisplay that MonitorPanel's own manager keeps for this ID (how System Settings gets it), or nil.
/// The manager is kept alive for the life of the app: making a new one per request would make it
/// re-read every display each time, and it may need to stay around to finish applying a change.
static id ConsigliereManagedDisplay(CGDirectDisplayID displayID) {
    if (!ConsigliereLoadMonitorPanel()) { return nil; }
    static id manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = NSClassFromString(@"MPDisplayMgr");
        if (cls != Nil) {
            @try { manager = [[cls alloc] init]; } @catch (NSException *e) { manager = nil; }
        }
    });
    if (manager == nil) { return nil; }

    @try {
        if ([manager respondsToSelector:@selector(displayWithID:)]) {
            id display = [manager displayWithID:displayID];
            if (display != nil) { return display; }
        }
        if ([manager respondsToSelector:@selector(displays)]) {
            for (id display in [manager displays]) {
                if ([display respondsToSelector:@selector(displayID)] && [display displayID] == displayID) {
                    return display;
                }
            }
        }
    } @catch (NSException *e) {
        NSLog(@"Consigliere: [rotate] MPDisplayMgr lookup raised %@: %@", e.name, e.reason);
    }
    return nil;
}

static int32_t ConsigliereRotateWithPanel(CGDirectDisplayID displayID, int32_t degrees, BOOL viaManager, char **outError) {
    if (!ConsigliereLoadMonitorPanel()) {
        ConsigliereSetError(outError, @"MonitorPanel is not on this Mac");
        return 2;
    }
    id display = viaManager ? ConsigliereManagedDisplay(displayID) : ConsigliereFreshDisplay(displayID);
    if (display == nil) {
        ConsigliereSetError(outError, viaManager ? @"MonitorPanel's display manager does not know this screen"
                                               : @"MonitorPanel would not open this screen");
        return 3;
    }
    if (![display respondsToSelector:@selector(setOrientation:)]) {
        ConsigliereSetError(outError, @"MonitorPanel no longer has setOrientation:");
        return 4;
    }
    @try {
        [display setOrientation:(NSInteger)degrees];
        return 0;
    } @catch (NSException *exception) {
        ConsigliereSetError(outError, exception.reason ?: @"MonitorPanel raised an exception");
        return 5;
    }
}

/// The old way: ask the framebuffer directly. Apple Silicon usually ignores it, which is why it is last.
static int32_t ConsigliereRotateWithIOKit(CGDirectDisplayID displayID, int32_t degrees, char **outError) {
    const IOOptionBits kIOFBSetTransform = 0x00000400;
    IOOptionBits transform;
    switch (degrees) {
        case 0: transform = kIOScaleRotate0; break;
        case 90: transform = kIOScaleRotate90; break;
        case 180: transform = kIOScaleRotate180; break;
        case 270: transform = kIOScaleRotate270; break;
        default:
            ConsigliereSetError(outError, @"degrees must be 0, 90, 180 or 270");
            return 1;
    }
    io_service_t service = CGDisplayIOServicePort(displayID);
    if (service == MACH_PORT_NULL) {
        ConsigliereSetError(outError, @"no IOKit service for this screen");
        return 6;
    }
    kern_return_t result = IOServiceRequestProbe(service, kIOFBSetTransform | (transform << 16));
    if (result != KERN_SUCCESS) {
        ConsigliereSetError(outError, [NSString stringWithFormat:@"IOKit refused (0x%x)", result]);
        return 7;
    }
    return 0;
}

int32_t ConsigliereRotate(uint32_t displayID, int32_t degrees, int32_t method, char **outError) {
    if (outError != NULL) { *outError = NULL; }
    if (displayID == 0 || (degrees != 0 && degrees != 90 && degrees != 180 && degrees != 270)) {
        ConsigliereSetError(outError, @"invalid screen or angle");
        return 1;
    }
    switch (method) {
        case 0: return ConsigliereRotateWithPanel(displayID, degrees, NO, outError);
        case 1: return ConsigliereRotateWithPanel(displayID, degrees, YES, outError);
        case 2: return ConsigliereRotateWithIOKit(displayID, degrees, outError);
    }
    ConsigliereSetError(outError, @"unknown method");
    return 1;
}

int32_t ConsigliereCanRotate(uint32_t displayID) {
    @try {
        id display = ConsigliereFreshDisplay(displayID);
        if (display == nil || ![display respondsToSelector:@selector(canChangeOrientation)]) { return -1; }
        return [display canChangeOrientation] ? 1 : 0;
    } @catch (NSException *e) {
        return -1;
    }
}
