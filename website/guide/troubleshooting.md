# Troubleshooting

## Windows says "Windows protected your PC"

The downloads are not code-signed yet, so SmartScreen does not recognise the
publisher. Choose **More info → Run anyway**. See the
[code signing policy](/code-signing).

## "Camera in use"

Another application holds the camera and the driver does not share it. Close
the camera there, or select a virtual camera instead — see
[Sharing one webcam](/guide/obs#sharing-one-webcam).

## "Camera permission required"

Windows is blocking camera access. Open **Settings → Privacy & security →
Camera** and switch on **Let desktop apps access your camera**. The button in
the overlay takes you there.

## "Camera disconnected" or "No camera found"

Plug the camera in; the preview starts by itself. If you selected a specific
camera that is no longer available, choose another in Settings.

## I cannot click the overlay

Click-through is on. Press `Ctrl + Alt + C`, or right-click the tray icon and
untick **Click-through**.

## The overlay is gone

It is hidden to the tray. Click the tray icon or press `Ctrl + Alt + V`. If
the icon is not visible, look behind the `^` arrow next to the clock.

## "Preview Cam" is not in OBS's device list

- It is a camera, so it appears under **Video Capture Device**, not under
  Window Capture.
- Switch on **Settings → Camera → Virtual camera for OBS** in Preview Cam.
- Close and reopen the source's properties in OBS to refresh the list.
- If OBS runs as administrator, start it normally: the camera is registered
  for your user account, which elevated programs ignore.

## The overlay is not in OBS's Window Capture list

Switch on **Settings → Behavior → Allow window capture**.

## A hotkey does nothing

Another application has registered the same combination; Settings shows a
warning icon next to it. Choose a different combination.

## Reset everything

Quit Preview Cam and delete the folder
`%APPDATA%\uz.nurafshon\Preview Cam`. The next start is like the first.

## Something else

[Open an issue](https://github.com/otabekoff/preview-cam/issues) and describe
what you did and what happened.
