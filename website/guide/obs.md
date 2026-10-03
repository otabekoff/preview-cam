# Using it with OBS

Preview Cam is independent of OBS Studio: it opens the camera for itself and
changes nothing on the device. There are a few things worth knowing when you
use both.

## Sharing one webcam

Whether two applications can read the same physical webcam at once depends on
the camera driver and on which application opened it first. If the camera is
taken, the overlay says **Camera in use** instead of showing an empty window.

The reliable setup is to let one application own the webcam and have the
others read a virtual camera:

- **NVIDIA Broadcast** owns the webcam; OBS and Preview Cam both use
  *Camera (NVIDIA Broadcast)*.
- **OBS** owns the webcam; start *Virtual Camera* in OBS and select
  *OBS Virtual Camera* in Preview Cam.

Any camera Windows lists can be selected in **Settings → Camera → Device**.

## Getting the overlay into a recording

Display Capture records the overlay like everything else on screen. If you
capture a single window instead, the overlay is not part of that window, so
add it to the scene in one of these ways.

### The Preview Cam virtual camera (recommended)

This gives OBS exactly what the overlay shows — cropped, mirrored and in the
same shape — with a real alpha channel, so rounded corners, the circle and a
removed background stay transparent.

1. In Preview Cam: **Settings → Camera → Virtual camera for OBS** → on.
2. In OBS: **Sources → + → Video Capture Device**.
3. In the **Device** list choose **Preview Cam**.

The camera delivers ARGB video only, so OBS always receives the alpha
channel. If the corners still look filled after updating Preview Cam, OBS is
using the previous version of the camera: remove the source and add it again,
or restart OBS.

Good to know:

- The hover controls and messages are not part of the picture.
- The picture has the overlay's proportions at the camera's resolution, for
  example 1080 × 1080 for a circle from a 1080p camera. After changing the
  shape, deactivate and reactivate the source in OBS to pick up the new size.
- While Preview Cam is not running, or the overlay is hidden, the device
  delivers a transparent picture.

### Window Capture

1. In Preview Cam: **Settings → Behavior → Allow window capture** → on
   (the default).
2. In OBS: **Sources → + → Window Capture** and choose
   `[preview.exe]: Preview Cam`.

OBS draws captured windows opaque, so the area outside a rounded or circular
shape comes out black. Use the virtual camera when you need transparency.

### The camera directly

Add a **Video Capture Device** source and pick the same camera the overlay
uses. You get the plain rectangular picture and shape it with OBS filters;
Preview Cam is then only your own on-screen monitor.

## Transparent background with NVIDIA Broadcast

1. In NVIDIA Broadcast: **Virtual background → Remove**.
2. In Preview Cam: select **Camera (NVIDIA Broadcast)**.
3. Settings shows `ARGB32 · with transparency` when it is active.

Turn **Transparent background** off in Settings if you prefer a black
background.
