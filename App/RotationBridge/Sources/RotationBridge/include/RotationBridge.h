#ifndef CONSIGLIERE_ROTATION_BRIDGE_H
#define CONSIGLIERE_ROTATION_BRIDGE_H

#include <stdint.h>

/// The ways this bridge knows to ask macOS to rotate a display, passed as `method`. ScreenRotator tries
/// them in this order and checks after each one whether the screen really turned, because a "success"
/// from any of them only means "macOS did not complain", not "the screen moved".
///   0  MonitorPanel, a fresh MPDisplay made from the display's ID (what Rotator and Pivot do).
///   1  MonitorPanel, the MPDisplay handed out by MonitorPanel's own display manager, the way System
///      Settings gets it. Matters when more than one display is connected.
///   2  The old framebuffer request (IOKit). Intel Macs, and anything MonitorPanel refuses.

/// Asks macOS to rotate `displayID` to `degrees` (0, 90, 180 or 270) using one method.
/// Returns 0 if the request was accepted, non-zero otherwise. On failure `*outError` (if not NULL) is set
/// to a malloc'd description the caller must free().
int32_t ConsigliereRotate(uint32_t displayID, int32_t degrees, int32_t method, char **outError);

/// What MonitorPanel says about rotating this display: 1 it can, 0 it cannot, -1 it would not say.
int32_t ConsigliereCanRotate(uint32_t displayID);

#endif
