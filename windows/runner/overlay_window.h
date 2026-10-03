#ifndef RUNNER_OVERLAY_WINDOW_H_
#define RUNNER_OVERLAY_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <set>
#include <string>

#include "camera_capture.h"
#include "settings_window.h"
#include "tray_icon.h"
#include "win32_window.h"

// The camera overlay: a frameless, per-pixel transparent, optionally topmost
// and click-through top-level window that hosts the main Flutter view.
//
// Everything Flutter cannot do reliably by itself lives here and is exposed to
// Dart over the `preview/native` method channel (see
// lib/platform/windows/windows_overlay_service.dart):
//
//  * window styles      WS_POPUP (no caption/border), a hidden owner window
//                       or WS_EX_TOOLWINDOW (no taskbar button),
//                       HWND_TOPMOST (always on top)
//  * transparency       DwmExtendFrameIntoClientArea + a window region that
//                       matches the camera shape
//  * click-through      WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE
//  * move / resize      native modal loops driven by WM_NCLBUTTONDOWN and
//                       WM_NCHITTEST, aspect ratio enforced in WM_SIZING
//  * global hotkeys     RegisterHotKey / WM_HOTKEY
//  * monitors and DPI   EnumDisplayMonitors, per-monitor DPI, work areas
//  * camera capture     DirectShow, see camera_capture.h
//  * device hot-plug    RegisterDeviceNotification / WM_DEVICECHANGE
//  * tray icon, start-with-Windows (HKCU Run key), settings window
class OverlayWindow : public Win32Window {
 public:
  // Window title; also used by a second process instance to find this one.
  static const wchar_t kTitle[];
  // Posted by a second process instance to bring the overlay back.
  static const UINT kSecondInstanceMessage = WM_APP + 2;
  // Posted by a development build to make this instance exit cleanly so the
  // new one can take its place.
  static const UINT kExitRequestMessage = WM_APP + 7;

  explicit OverlayWindow(const flutter::DartProject& project);
  virtual ~OverlayWindow();

  // Creates the (hidden) overlay window. Dart positions and shows it.
  bool CreateOverlay();

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window,
                         UINT const message,
                         WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  enum class Shape { kRectangle = 0, kRounded = 1, kCircle = 2 };

  using MethodCall = flutter::MethodCall<flutter::EncodableValue>;
  using MethodResult = flutter::MethodResult<flutter::EncodableValue>;

  void HandleMethodCall(const MethodCall& call,
                        std::unique_ptr<MethodResult> result);
  // The `preview/camera` channel: list / open / close.
  void HandleCameraCall(const MethodCall& call,
                        std::unique_ptr<MethodResult> result);
  void Notify(const char* method,
              std::unique_ptr<flutter::EncodableValue> arguments = nullptr);

  // Window geometry helpers. All values are physical pixels.
  flutter::EncodableValue BoundsValue();
  flutter::EncodableValue MonitorsValue();
  double ScaleFactor();
  int CornerRadiusPx();

  void ApplyTopmost();
  void SetClickThrough(bool enabled);
  // |skip|: no taskbar button. |capturable|: stay listed by screen-capture
  // tools while hidden from the taskbar (at the price of an Alt+Tab entry).
  void SetSkipTaskbar(bool skip, bool capturable);
  void SetOpacity(double opacity);
  // Clips the window (rendering and hit testing) to the camera shape.
  void UpdateRegion();
  // Returns HTCLIENT, or a sizing hit-test code when |client_point| lies in
  // one of the invisible resize zones along the edge of the shape.
  LRESULT HitTestResize(POINT client_point);
  // Adjusts a WM_SIZING rectangle so it keeps |aspect_ratio_|.
  void ConstrainAspect(WPARAM edge, RECT* rect);
  void BeginDrag();
  void OpenSettings();

  // Replacement window procedure for the Flutter view (a child window that
  // covers the whole client area and would otherwise swallow hit tests).
  static LRESULT CALLBACK ChildProc(HWND hwnd,
                                    UINT message,
                                    WPARAM wparam,
                                    LPARAM lparam) noexcept;

  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      camera_channel_;
  std::unique_ptr<CameraCapture> camera_;
  std::unique_ptr<TrayIcon> tray_;
  std::unique_ptr<SettingsWindow> settings_window_;

  WNDPROC child_original_proc_ = nullptr;
  HDEVNOTIFY device_notifications_[2] = {nullptr, nullptr};
  std::set<int> hotkey_ids_;

  Shape shape_ = Shape::kRectangle;
  double corner_radius_ = 0;   // logical pixels
  double aspect_ratio_ = 0;    // width / height; 0 = unconstrained
  double min_size_ = 90;       // logical pixels, shorter side
  BYTE alpha_ = 255;
  // Hidden window that owns the overlay in "hidden but capturable" mode.
  HWND taskbar_owner_ = nullptr;
  bool always_on_top_ = true;
  bool click_through_ = false;
  // True while SetWindowPos is called on behalf of Dart, which has already
  // sized the window for the destination monitor's DPI.
  bool programmatic_move_ = false;
  // True while a native move loop started from a Flutter pointer-down runs.
  bool flutter_drag_ = false;
};

#endif  // RUNNER_OVERLAY_WINDOW_H_
