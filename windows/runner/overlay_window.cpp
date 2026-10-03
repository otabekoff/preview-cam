#include "overlay_window.h"

#include <dbt.h>
#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <flutter_plugin_registrar.h>
#include <flutter_windows.h>
#include <shellapi.h>
#include <windowsx.h>

#include <algorithm>
#include <cmath>
#include <optional>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"
#include "utils.h"

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

const wchar_t OverlayWindow::kTitle[] = L"Preview Cam";

namespace {

constexpr char kChannelName[] = "preview/native";

// Private window messages (WM_APP + 1 is the tray callback, + 2 is
// OverlayWindow::kSecondInstanceMessage).
constexpr UINT kSettingsClosedMessage = WM_APP + 3;
constexpr UINT kBeginDragMessage = WM_APP + 4;
constexpr UINT kQuitMessage = WM_APP + 5;
constexpr UINT kCameraMessage = WM_APP + 6;

constexpr char kCameraChannelName[] = "preview/camera";

// Width of the invisible resize band along the edge of the shape, in logical
// pixels.
constexpr double kResizeGrip = 6.0;

constexpr wchar_t kRunKey[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kRunValue[] = L"PreviewCam";

// Device interface classes that cameras (physical and virtual) register.
constexpr GUID kVideoCameraCategory = {
    0xe5323777,
    0xf976,
    0x4f5b,
    {0x9b, 0x55, 0xb9, 0x46, 0x99, 0xc4, 0x6e, 0x44}};
constexpr GUID kCaptureCategory = {
    0x65e8773d,
    0x8f56,
    0x11d0,
    {0xa3, 0xb9, 0x00, 0xa0, 0xc9, 0x22, 0x31, 0x96}};

// Attributes that may be missing from older Windows SDKs.
#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWA_BORDER_COLOR
#define DWMWA_BORDER_COLOR 34
#endif
constexpr DWORD kDwmCornerDoNotRound = 1;     // DWMWCP_DONOTROUND
constexpr COLORREF kDwmColorNone = 0xFFFFFFFE;  // DWMWA_COLOR_NONE

// There is exactly one overlay window per process; ChildProc uses this to
// reach it from the Flutter view's window procedure.
OverlayWindow* g_overlay = nullptr;

const EncodableValue* Find(const EncodableMap* map, const char* key) {
  if (!map) {
    return nullptr;
  }
  auto it = map->find(EncodableValue(key));
  return it == map->end() ? nullptr : &it->second;
}

// Dart numbers arrive as int32, int64 or double depending on their value.
double NumberOr(const EncodableValue* value, double fallback) {
  if (!value) {
    return fallback;
  }
  if (auto v = std::get_if<double>(value)) {
    return *v;
  }
  if (auto v = std::get_if<int32_t>(value)) {
    return *v;
  }
  if (auto v = std::get_if<int64_t>(value)) {
    return static_cast<double>(*v);
  }
  return fallback;
}

int IntOr(const EncodableValue* value, int fallback) {
  return static_cast<int>(std::lround(NumberOr(value, fallback)));
}

bool BoolOr(const EncodableValue* value, bool fallback) {
  if (value) {
    if (auto v = std::get_if<bool>(value)) {
      return *v;
    }
  }
  return fallback;
}

std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  const int length = MultiByteToWideChar(
      CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()), nullptr, 0);
  std::wstring utf16(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                      utf16.data(), length);
  return utf16;
}

// Quoted path of the running executable, as stored in the Run key.
std::wstring StartupCommand() {
  wchar_t path[MAX_PATH];
  const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
  return L"\"" + std::wstring(path, length) + L"\"";
}

BOOL CALLBACK CollectMonitor(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
  auto* monitors = reinterpret_cast<EncodableList*>(data);
  MONITORINFOEXW info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfoW(monitor, &info)) {
    return TRUE;
  }
  monitors->push_back(EncodableValue(EncodableMap{
      {EncodableValue("id"), EncodableValue(Utf8FromUtf16(info.szDevice))},
      {EncodableValue("primary"),
       EncodableValue((info.dwFlags & MONITORINFOF_PRIMARY) != 0)},
      {EncodableValue("dpi"),
       EncodableValue(static_cast<int>(FlutterDesktopGetDpiForMonitor(monitor)))},
      {EncodableValue("x"), EncodableValue(info.rcMonitor.left)},
      {EncodableValue("y"), EncodableValue(info.rcMonitor.top)},
      {EncodableValue("width"),
       EncodableValue(info.rcMonitor.right - info.rcMonitor.left)},
      {EncodableValue("height"),
       EncodableValue(info.rcMonitor.bottom - info.rcMonitor.top)},
      {EncodableValue("workX"), EncodableValue(info.rcWork.left)},
      {EncodableValue("workY"), EncodableValue(info.rcWork.top)},
      {EncodableValue("workWidth"),
       EncodableValue(info.rcWork.right - info.rcWork.left)},
      {EncodableValue("workHeight"),
       EncodableValue(info.rcWork.bottom - info.rcWork.top)},
  }));
  return TRUE;
}

}  // namespace

OverlayWindow::OverlayWindow(const flutter::DartProject& project)
    : project_(project) {}

OverlayWindow::~OverlayWindow() {}

bool OverlayWindow::CreateOverlay() {
  // WS_POPUP: no caption, no border, no system buttons.
  // WS_EX_LAYERED: lets the window carry a constant alpha (opacity) and is a
  // prerequisite for WS_EX_TRANSPARENT click-through.
  // The real position and size, and how the window is kept off the taskbar
  // (see SetSkipTaskbar), are applied by Dart before the window is shown.
  RECT frame = {0, 0, 320, 180};
  return Create(kTitle, frame, WS_POPUP, WS_EX_LAYERED);
}

bool OverlayWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }
  HWND hwnd = GetHandle();
  g_overlay = this;

  // Never shown. Owning the overlay is one of the two ways it is kept off
  // the taskbar; see SetSkipTaskbar.
  taskbar_owner_ =
      CreateWindowEx(WS_EX_TOOLWINDOW, L"STATIC", L"", WS_POPUP, 0, 0, 0, 0,
                     nullptr, nullptr, GetModuleHandle(nullptr), nullptr);
  SetSkipTaskbar(true, true);


  SetLayeredWindowAttributes(hwnd, 0, alpha_, LWA_ALPHA);

  // Per-pixel transparency: extending the DWM frame over the whole client
  // area ("sheet of glass") makes DWM honour the alpha channel of what Flutter
  // renders, so pixels Flutter leaves transparent show the desktop.
  const MARGINS margins = {-1, -1, -1, -1};
  DwmExtendFrameIntoClientArea(hwnd, &margins);
  // Windows 11 would otherwise round the corners and draw a 1px border.
  DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE,
                        &kDwmCornerDoNotRound, sizeof(kDwmCornerDoNotRound));
  DwmSetWindowAttribute(hwnd, DWMWA_BORDER_COLOR, &kDwmColorNone,
                        sizeof(kDwmColorNone));

  RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      flutter_controller_->engine()->messenger(), kChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const MethodCall& call, std::unique_ptr<MethodResult> result) {
        HandleMethodCall(call, std::move(result));
      });

  camera_ = std::make_unique<CameraCapture>(
      FlutterDesktopRegistrarGetTextureRegistrar(
          flutter_controller_->engine()->GetRegistrarForPlugin(
              "PreviewCamCapture")),
      hwnd, kCameraMessage);
  camera_->on_error = [this](const std::string& code,
                             const std::string& message) {
    if (camera_channel_) {
      camera_channel_->InvokeMethod(
          "onError", std::make_unique<EncodableValue>(EncodableMap{
                         {EncodableValue("code"), EncodableValue(code)},
                         {EncodableValue("message"), EncodableValue(message)},
                     }));
    }
  };
  camera_channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      flutter_controller_->engine()->messenger(), kCameraChannelName,
      &flutter::StandardMethodCodec::GetInstance());
  camera_channel_->SetMethodCallHandler(
      [this](const MethodCall& call, std::unique_ptr<MethodResult> result) {
        HandleCameraCall(call, std::move(result));
      });

  HWND child = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(child);
  // Subclass the Flutter view so resize zones fall through to this window.
  child_original_proc_ = reinterpret_cast<WNDPROC>(SetWindowLongPtr(
      child, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(ChildProc)));

  // Camera arrival/removal notifications (delivered as WM_DEVICECHANGE).
  const GUID categories[2] = {kVideoCameraCategory, kCaptureCategory};
  for (int i = 0; i < 2; ++i) {
    DEV_BROADCAST_DEVICEINTERFACE_W filter{};
    filter.dbcc_size = sizeof(filter);
    filter.dbcc_devicetype = DBT_DEVTYP_DEVICEINTERFACE;
    filter.dbcc_classguid = categories[i];
    device_notifications_[i] = RegisterDeviceNotificationW(
        hwnd, &filter, DEVICE_NOTIFY_WINDOW_HANDLE);
  }

  tray_ = std::make_unique<TrayIcon>([this](const std::string& command) {
    Notify("onTrayCommand", std::make_unique<EncodableValue>(command));
  });
  HICON icon = static_cast<HICON>(LoadImage(
      GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON),
      LR_DEFAULTCOLOR));
  tray_->Create(icon, kTitle);

  // The window stays hidden until Dart has restored its geometry and calls
  // `show`.
  return true;
}

void OverlayWindow::OnDestroy() {
  HWND hwnd = GetHandle();
  if (hwnd) {
    for (int id : hotkey_ids_) {
      UnregisterHotKey(hwnd, id);
    }
  }
  hotkey_ids_.clear();
  for (HDEVNOTIFY& handle : device_notifications_) {
    if (handle) {
      UnregisterDeviceNotification(handle);
      handle = nullptr;
    }
  }
  settings_window_ = nullptr;
  tray_ = nullptr;
  // Stops capture and releases the device before the engine goes away.
  camera_channel_ = nullptr;
  camera_ = nullptr;
  channel_ = nullptr;
  flutter_controller_ = nullptr;
  if (g_overlay == this) {
    g_overlay = nullptr;
  }
  if (taskbar_owner_) {
    // Detach first: destroying an owner destroys the windows it owns.
    if (hwnd) {
      SetWindowLongPtr(hwnd, GWLP_HWNDPARENT, 0);
    }
    DestroyWindow(taskbar_owner_);
    taskbar_owner_ = nullptr;
  }


  Win32Window::OnDestroy();
}

void OverlayWindow::Notify(const char* method,
                           std::unique_ptr<EncodableValue> arguments) {
  if (channel_) {
    channel_->InvokeMethod(method, std::move(arguments));
  }
}

double OverlayWindow::ScaleFactor() {
  return GetDpiForWindow(GetHandle()) / 96.0;
}

int OverlayWindow::CornerRadiusPx() {
  RECT rect = GetClientArea();
  const int limit = static_cast<int>(std::min(rect.right, rect.bottom) / 2);
  return std::clamp(static_cast<int>(std::lround(corner_radius_ * ScaleFactor())),
                    0, limit);
}

EncodableValue OverlayWindow::BoundsValue() {
  HWND hwnd = GetHandle();
  RECT rect{};
  GetWindowRect(hwnd, &rect);
  // MONITOR_DEFAULTTONEAREST picks the monitor with the largest intersection,
  // i.e. the one containing the majority of the overlay.
  HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
  MONITORINFOEXW info{};
  info.cbSize = sizeof(info);
  GetMonitorInfoW(monitor, &info);
  return EncodableValue(EncodableMap{
      {EncodableValue("x"), EncodableValue(rect.left)},
      {EncodableValue("y"), EncodableValue(rect.top)},
      {EncodableValue("width"), EncodableValue(rect.right - rect.left)},
      {EncodableValue("height"), EncodableValue(rect.bottom - rect.top)},
      {EncodableValue("monitor"), EncodableValue(Utf8FromUtf16(info.szDevice))},
      {EncodableValue("dpi"),
       EncodableValue(static_cast<int>(FlutterDesktopGetDpiForMonitor(monitor)))},
  });
}

EncodableValue OverlayWindow::MonitorsValue() {
  EncodableList monitors;
  EnumDisplayMonitors(nullptr, nullptr, CollectMonitor,
                      reinterpret_cast<LPARAM>(&monitors));
  return EncodableValue(monitors);
}

void OverlayWindow::ApplyTopmost() {
  // A real topmost window: the window manager keeps it above all non-topmost
  // windows, no re-raising or polling required.
  SetWindowPos(GetHandle(), always_on_top_ ? HWND_TOPMOST : HWND_NOTOPMOST, 0,
               0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}

void OverlayWindow::SetClickThrough(bool enabled) {
  click_through_ = enabled;
  HWND hwnd = GetHandle();
  LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  // A layered window with WS_EX_TRANSPARENT is skipped by mouse hit testing
  // entirely, so input reaches whatever is underneath. WS_EX_NOACTIVATE keeps
  // it from ever taking focus while in this mode.
  const LONG_PTR flags = WS_EX_TRANSPARENT | WS_EX_NOACTIVATE;
  ex_style = enabled ? (ex_style | flags) : (ex_style & ~flags);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);
  SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);
}

void OverlayWindow::SetSkipTaskbar(bool skip, bool capturable) {
  HWND hwnd = GetHandle();
  // The taskbar only re-evaluates a window when it is shown, so the change
  // has to happen while the window is hidden.
  const bool visible = IsWindowVisible(hwnd) != FALSE;
  if (visible) {
    ShowWindow(hwnd, SW_HIDE);
  }
  // Three states:
  //  * taskbar button:        WS_EX_APPWINDOW, no owner.
  //  * hidden, capturable:    owned by a hidden window. The taskbar shows no
  //                           button for owned windows, yet the overlay stays
  //                           an ordinary window that OBS and other capture
  //                           tools list as a "Window Capture" source.
  //  * hidden, tool window:   WS_EX_TOOLWINDOW. Also absent from Alt+Tab,
  //                           but capture tools leave tool windows out.
  const bool owned = skip && capturable;
  const bool tool = skip && !capturable;
  LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  ex_style &= ~(WS_EX_TOOLWINDOW | WS_EX_APPWINDOW);
  if (tool) {
    ex_style |= WS_EX_TOOLWINDOW;
  } else if (!skip) {
    ex_style |= WS_EX_APPWINDOW;
  }
  SetWindowLongPtr(hwnd, GWLP_HWNDPARENT,
                   owned ? reinterpret_cast<LONG_PTR>(taskbar_owner_) : 0);
  SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);
  if (visible) {
    ShowWindow(hwnd, SW_SHOWNOACTIVATE);
    ApplyTopmost();
  }
}

void OverlayWindow::SetOpacity(double opacity) {
  alpha_ = static_cast<BYTE>(
      std::clamp(std::lround(opacity * 255.0), 25L, 255L));
  // Constant alpha applied by the compositor: no extra work for Flutter.
  SetLayeredWindowAttributes(GetHandle(), 0, alpha_, LWA_ALPHA);
}

void OverlayWindow::UpdateRegion() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }
  RECT rect = GetClientArea();
  const int width = rect.right;
  const int height = rect.bottom;
  // The region is deliberately a hair larger than the shape Flutter draws:
  // Flutter paints the anti-aliased edge with real alpha, while the region
  // (which cannot be anti-aliased) only has to keep the fully transparent
  // corners from catching mouse input.
  HRGN region = nullptr;
  if (shape_ == Shape::kCircle) {
    region = CreateEllipticRgn(-1, -1, width + 2, height + 2);
  } else if (shape_ == Shape::kRounded) {
    const int radius = CornerRadiusPx();
    if (radius > 0) {
      const int diameter = std::max(0, radius * 2 - 2);
      region =
          CreateRoundRectRgn(0, 0, width + 1, height + 1, diameter, diameter);
    }
  }
  // The system owns |region| after this call.
  SetWindowRgn(hwnd, region, TRUE);
}

LRESULT OverlayWindow::HitTestResize(POINT point) {
  if (click_through_) {
    return HTCLIENT;
  }
  RECT rect = GetClientArea();
  const double width = rect.right;
  const double height = rect.bottom;
  const double grip = kResizeGrip * ScaleFactor();
  const double x = point.x;
  const double y = point.y;

  if (shape_ == Shape::kCircle) {
    // A ring just inside the circle; the angle picks the sizing direction.
    const double radius = std::min(width, height) / 2.0;
    const double dx = x - width / 2.0;
    const double dy = y - height / 2.0;
    if (std::sqrt(dx * dx + dy * dy) < radius - grip * 1.5) {
      return HTCLIENT;
    }
    constexpr double kPi = 3.14159265358979323846;
    static const LRESULT kSectors[8] = {HTRIGHT,      HTBOTTOMRIGHT, HTBOTTOM,
                                        HTBOTTOMLEFT, HTLEFT,        HTTOPLEFT,
                                        HTTOP,        HTTOPRIGHT};
    int sector = static_cast<int>(
        std::floor((std::atan2(dy, dx) + kPi / 8.0) / (kPi / 4.0)));
    sector = ((sector % 8) + 8) % 8;
    return kSectors[sector];
  }

  const bool on_left = x < grip;
  const bool on_right = x >= width - grip;
  const bool on_top = y < grip;
  const bool on_bottom = y >= height - grip;
  if (on_left || on_right || on_top || on_bottom) {
    // Corners are easier to grab than a grip-by-grip square.
    const double corner = grip * 2.5;
    const bool left = on_left || (x < corner && (on_top || on_bottom));
    const bool right =
        on_right || (x >= width - corner && (on_top || on_bottom));
    const bool top = on_top || (y < corner && (on_left || on_right));
    const bool bottom =
        on_bottom || (y >= height - corner && (on_left || on_right));
    if (top && left) return HTTOPLEFT;
    if (top && right) return HTTOPRIGHT;
    if (bottom && left) return HTBOTTOMLEFT;
    if (bottom && right) return HTBOTTOMRIGHT;
    if (left) return HTLEFT;
    if (right) return HTRIGHT;
    if (top) return HTTOP;
    return HTBOTTOM;
  }

  if (shape_ == Shape::kRounded) {
    // With a large radius the square corners are outside the visible shape,
    // so the diagonal grips follow the inside of the corner arcs instead.
    const double radius = CornerRadiusPx();
    if (radius > grip * 2.5) {
      const bool left = x < radius;
      const bool right = x >= width - radius;
      const bool top = y < radius;
      const bool bottom = y >= height - radius;
      if ((left || right) && (top || bottom)) {
        const double cx = left ? radius : width - radius;
        const double cy = top ? radius : height - radius;
        const double distance =
            std::sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
        if (distance >= radius - grip * 1.5) {
          if (top) return left ? HTTOPLEFT : HTTOPRIGHT;
          return left ? HTBOTTOMLEFT : HTBOTTOMRIGHT;
        }
      }
    }
  }
  return HTCLIENT;
}

void OverlayWindow::ConstrainAspect(WPARAM edge, RECT* rect) {
  const double width = rect->right - rect->left;
  const double height = rect->bottom - rect->top;
  switch (edge) {
    case WMSZ_TOP:
    case WMSZ_BOTTOM:
      // Height is being dragged; width follows.
      rect->right = rect->left + std::lround(height * aspect_ratio_);
      break;
    case WMSZ_TOPLEFT:
    case WMSZ_TOPRIGHT:
      rect->top = rect->bottom - std::lround(width / aspect_ratio_);
      break;
    default:
      // Left, right and bottom corners: width drives, bottom edge follows.
      rect->bottom = rect->top + std::lround(width / aspect_ratio_);
      break;
  }
}

void OverlayWindow::BeginDrag() {
  // Only start if the primary button is still physically held; otherwise the
  // modal move loop would wait for a button-up that already happened.
  const int button =
      GetSystemMetrics(SM_SWAPBUTTON) ? VK_RBUTTON : VK_LBUTTON;
  if (GetAsyncKeyState(button) >= 0) {
    return;
  }
  POINT cursor{};
  GetCursorPos(&cursor);
  flutter_drag_ = true;
  // Hand the drag to the window manager exactly as if the user had pressed
  // the button on a title bar: the system runs its native move loop.
  ReleaseCapture();
  SendMessage(GetHandle(), WM_NCLBUTTONDOWN, HTCAPTION,
              MAKELPARAM(cursor.x, cursor.y));
}

void OverlayWindow::OpenSettings() {
  if (settings_window_ && settings_window_->GetHandle()) {
    settings_window_->BringToFront();
    return;
  }
  settings_window_ = std::make_unique<SettingsWindow>(
      GetHandle(), kSettingsClosedMessage, [this](const EncodableValue& m) {
        Notify("onRelay", std::make_unique<EncodableValue>(m));
      });
  HMONITOR monitor = MonitorFromWindow(GetHandle(), MONITOR_DEFAULTTONEAREST);
  if (!settings_window_->Open(monitor)) {
    settings_window_ = nullptr;
  }
}

void OverlayWindow::HandleMethodCall(const MethodCall& call,
                                     std::unique_ptr<MethodResult> result) {
  HWND hwnd = GetHandle();
  const std::string& method = call.method_name();
  const EncodableValue* args = call.arguments();
  const EncodableMap* map = args ? std::get_if<EncodableMap>(args) : nullptr;

  if (method == "getMonitors") {
    result->Success(MonitorsValue());
  } else if (method == "getBounds") {
    result->Success(BoundsValue());
  } else if (method == "setBounds") {
    // Dart has already scaled the size for the destination monitor, so the
    // WM_DPICHANGED this may trigger must not rescale the window again.
    programmatic_move_ = true;
    SetWindowPos(hwnd, nullptr, IntOr(Find(map, "x"), 0),
                 IntOr(Find(map, "y"), 0), IntOr(Find(map, "width"), 320),
                 IntOr(Find(map, "height"), 180),
                 SWP_NOZORDER | SWP_NOACTIVATE);
    programmatic_move_ = false;
    result->Success(BoundsValue());
  } else if (method == "show") {
    ShowWindow(hwnd, BoolOr(Find(map, "activate"), false) ? SW_SHOW
                                                          : SW_SHOWNOACTIVATE);
    ApplyTopmost();
    result->Success();
  } else if (method == "hide") {
    ShowWindow(hwnd, SW_HIDE);
    result->Success();
  } else if (method == "setAlwaysOnTop") {
    always_on_top_ = BoolOr(args, true);
    ApplyTopmost();
    result->Success();
  } else if (method == "setClickThrough") {
    SetClickThrough(BoolOr(args, false));
    result->Success();
  } else if (method == "setSkipTaskbar") {
    SetSkipTaskbar(BoolOr(Find(map, "skip"), true),
                   BoolOr(Find(map, "capturable"), true));
    result->Success();
  } else if (method == "setOpacity") {
    SetOpacity(NumberOr(args, 1.0));
    result->Success();
  } else if (method == "setShape") {
    shape_ = static_cast<Shape>(std::clamp(IntOr(Find(map, "kind"), 0), 0, 2));
    corner_radius_ = NumberOr(Find(map, "radius"), 0);
    UpdateRegion();
    result->Success();
  } else if (method == "setAspectRatio") {
    aspect_ratio_ = std::max(0.0, NumberOr(args, 0));
    result->Success();
  } else if (method == "setMinSize") {
    min_size_ = std::max(32.0, NumberOr(args, 90));
    result->Success();
  } else if (method == "startDrag") {
    // Posted so this call returns before the modal move loop starts.
    PostMessage(hwnd, kBeginDragMessage, 0, 0);
    result->Success();
  } else if (method == "registerHotkey") {
    const int id = IntOr(Find(map, "id"), 0);
    UINT modifiers = static_cast<UINT>(IntOr(Find(map, "modifiers"), 0));
    if (!BoolOr(Find(map, "repeat"), false)) {
      modifiers |= MOD_NOREPEAT;
    }
    UnregisterHotKey(hwnd, id);
    const bool ok =
        RegisterHotKey(hwnd, id, modifiers,
                       static_cast<UINT>(IntOr(Find(map, "vk"), 0))) != FALSE;
    if (ok) {
      hotkey_ids_.insert(id);
    } else {
      hotkey_ids_.erase(id);
    }
    result->Success(EncodableValue(ok));
  } else if (method == "unregisterAllHotkeys") {
    for (int id : hotkey_ids_) {
      UnregisterHotKey(hwnd, id);
    }
    hotkey_ids_.clear();
    result->Success();
  } else if (method == "setTrayState") {
    if (tray_) {
      TrayIcon::MenuState state;
      state.visible = BoolOr(Find(map, "visible"), true);
      state.click_through = BoolOr(Find(map, "clickThrough"), false);
      state.always_on_top = BoolOr(Find(map, "alwaysOnTop"), true);
      // Translated menu texts; anything missing keeps its English default.
      const EncodableValue* labels_value = Find(map, "labels");
      const EncodableMap* labels =
          labels_value ? std::get_if<EncodableMap>(labels_value) : nullptr;
      auto label = [labels](const char* key, std::wstring* target) {
        const EncodableValue* value = Find(labels, key);
        const std::string* text =
            value ? std::get_if<std::string>(value) : nullptr;
        if (text && !text->empty()) {
          *target = Utf16FromUtf8(*text);
        }
      };
      label("show", &state.labels.show);
      label("hide", &state.labels.hide);
      label("clickThrough", &state.labels.click_through);
      label("alwaysOnTop", &state.labels.always_on_top);
      label("position", &state.labels.position);
      label("topLeft", &state.labels.top_left);
      label("topRight", &state.labels.top_right);
      label("bottomLeft", &state.labels.bottom_left);
      label("bottomRight", &state.labels.bottom_right);
      label("center", &state.labels.center);
      label("settings", &state.labels.settings);
      label("exit", &state.labels.exit);
      tray_->SetState(state);
    }
    result->Success();
  } else if (method == "getStartup") {
    wchar_t value[MAX_PATH + 8];
    DWORD size = sizeof(value);
    const LSTATUS status =
        RegGetValueW(HKEY_CURRENT_USER, kRunKey, kRunValue, RRF_RT_REG_SZ,
                     nullptr, value, &size);
    result->Success(EncodableValue(status == ERROR_SUCCESS));
  } else if (method == "setStartup") {
    // Per-user Run key: no administrator rights required.
    LSTATUS status;
    if (BoolOr(args, false)) {
      const std::wstring command = StartupCommand();
      status = RegSetKeyValueW(
          HKEY_CURRENT_USER, kRunKey, kRunValue, REG_SZ, command.c_str(),
          static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
    } else {
      status = RegDeleteKeyValueW(HKEY_CURRENT_USER, kRunKey, kRunValue);
      if (status == ERROR_FILE_NOT_FOUND) {
        status = ERROR_SUCCESS;
      }
    }
    result->Success(EncodableValue(status == ERROR_SUCCESS));
  } else if (method == "openSettings") {
    OpenSettings();
    result->Success();
  } else if (method == "relay") {
    if (args && settings_window_ && settings_window_->GetHandle()) {
      settings_window_->SendRelay(*args);
    }
    result->Success();
  } else if (method == "openSystemSettings") {
    // Only Windows Settings pages (e.g. ms-settings:privacy-webcam).
    const std::string* uri = args ? std::get_if<std::string>(args) : nullptr;
    if (uri && uri->rfind("ms-settings:", 0) == 0) {
      ShellExecuteW(nullptr, L"open", Utf16FromUtf8(*uri).c_str(), nullptr,
                    nullptr, SW_SHOWNORMAL);
    }
    result->Success();
  } else if (method == "quit") {
    result->Success();
    PostMessage(hwnd, kQuitMessage, 0, 0);
  } else {
    result->NotImplemented();
  }
}

void OverlayWindow::HandleCameraCall(const MethodCall& call,
                                     std::unique_ptr<MethodResult> result) {
  const std::string& method = call.method_name();
  const EncodableValue* args = call.arguments();
  const EncodableMap* map = args ? std::get_if<EncodableMap>(args) : nullptr;
  if (!camera_) {
    result->Error("failed", "Camera capture is not available.");
    return;
  }
  // Open and close finish on the capture thread; the reply is sent when the
  // completion is delivered back to this (platform) thread.
  std::shared_ptr<MethodResult> reply(std::move(result));

  if (method == "list") {
    EncodableList devices;
    for (const auto& device : CameraCapture::ListDevices()) {
      devices.push_back(EncodableValue(EncodableMap{
          {EncodableValue("id"), EncodableValue(device.id)},
          {EncodableValue("name"), EncodableValue(device.name)},
      }));
    }
    reply->Success(EncodableValue(devices));
  } else if (method == "open") {
    const EncodableValue* id = Find(map, "id");
    const std::string* device_id = id ? std::get_if<std::string>(id) : nullptr;
    if (!device_id) {
      reply->Error("failed", "Missing camera id.");
      return;
    }
    const int64_t texture_id = camera_->texture_id();
    camera_->Open(*device_id, IntOr(Find(map, "height"), 720),
                  IntOr(Find(map, "fps"), 0),
                  [reply, texture_id](const CameraCapture::OpenResult& opened) {
                    if (!opened.ok) {
                      reply->Error(opened.error_code, opened.error_message);
                      return;
                    }
                    reply->Success(EncodableValue(EncodableMap{
                        {EncodableValue("textureId"),
                         EncodableValue(texture_id)},
                        {EncodableValue("width"), EncodableValue(opened.width)},
                        {EncodableValue("height"),
                         EncodableValue(opened.height)},
                        {EncodableValue("fps"), EncodableValue(opened.fps)},
                        {EncodableValue("hasAlpha"),
                         EncodableValue(opened.has_alpha)},
                        {EncodableValue("format"),
                         EncodableValue(opened.format)},
                    }));
                  });
  } else if (method == "close") {
    camera_->Close([reply]() { reply->Success(); });
  } else if (method == "setOutput") {
    // Virtual camera: (un)register the device and say what to publish.
    VcamOutput::Config config;
    config.enabled = BoolOr(Find(map, "enabled"), false);
    config.mirror = BoolOr(Find(map, "mirror"), true);
    config.aspect = NumberOr(Find(map, "aspect"), 16.0 / 9.0);
    config.shape = static_cast<VcamOutput::Shape>(
        std::clamp(IntOr(Find(map, "shape"), 0), 0, 2));
    config.radius = NumberOr(Find(map, "radius"), 0);
    bool ok = true;
    if (config.enabled) {
      ok = VcamOutput::Register();
      config.enabled = ok;
    } else {
      VcamOutput::Unregister();
    }
    camera_->SetOutput(config);
    reply->Success(EncodableValue(ok));
  } else {
    reply->NotImplemented();
  }
}

// static
LRESULT CALLBACK OverlayWindow::ChildProc(HWND hwnd,
                                          UINT message,
                                          WPARAM wparam,
                                          LPARAM lparam) noexcept {
  OverlayWindow* self = g_overlay;
  if (!self || !self->child_original_proc_) {
    return DefWindowProc(hwnd, message, wparam, lparam);
  }
  if (message == WM_NCHITTEST) {
    POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
    ScreenToClient(self->GetHandle(), &point);
    if (self->HitTestResize(point) != HTCLIENT) {
      // "Not me": the system asks the parent next, whose WM_NCHITTEST returns
      // the sizing code, giving native resize cursors and a native size loop.
      return HTTRANSPARENT;
    }
  }
  return CallWindowProc(self->child_original_proc_, hwnd, message, wparam,
                        lparam);
}

LRESULT OverlayWindow::MessageHandler(HWND hwnd,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  // Messages owned by the overlay; Flutter never needs to see these.
  switch (message) {
    case WM_CLOSE:
      // Alt+F4 etc. hide to the tray; only the tray's Exit terminates.
      Notify("onCloseRequested");
      return 0;

    case WM_NCHITTEST: {
      POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
      ScreenToClient(hwnd, &point);
      return HitTestResize(point);
    }

    case WM_GETMINMAXINFO: {
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      const double shorter = min_size_ * ScaleFactor();
      double min_width = shorter;
      double min_height = shorter;
      if (aspect_ratio_ >= 1.0) {
        min_width = shorter * aspect_ratio_;
      } else if (aspect_ratio_ > 0) {
        min_height = shorter / aspect_ratio_;
      }
      info->ptMinTrackSize.x = static_cast<LONG>(std::lround(min_width));
      info->ptMinTrackSize.y = static_cast<LONG>(std::lround(min_height));
      return 0;
    }

    case WM_SIZING:
      if (aspect_ratio_ > 0) {
        ConstrainAspect(wparam, reinterpret_cast<RECT*>(lparam));
        return TRUE;
      }
      break;

    case WM_EXITSIZEMOVE: {
      if (flutter_drag_) {
        flutter_drag_ = false;
        // The move loop consumed the button-up, so Flutter still believes the
        // pointer is down. Deliver the missing release to the Flutter view.
        if (HWND child = child_content()) {
          POINT cursor{};
          GetCursorPos(&cursor);
          ScreenToClient(child, &cursor);
          PostMessage(child, WM_LBUTTONUP, 0, MAKELPARAM(cursor.x, cursor.y));
        }
      }
      // One notification when the user lets go; Dart persists the geometry.
      Notify("onBoundsChanged", std::make_unique<EncodableValue>(BoundsValue()));
      return 0;
    }

    case WM_DPICHANGED:
      if (programmatic_move_) {
        return 0;
      }
      break;  // Base class applies the suggested rectangle.

    case WM_HOTKEY:
      Notify("onHotkey",
             std::make_unique<EncodableValue>(static_cast<int>(wparam)));
      return 0;

    case WM_DEVICECHANGE:
      if (wparam == DBT_DEVICEARRIVAL || wparam == DBT_DEVICEREMOVECOMPLETE) {
        Notify("onDeviceChange");
      }
      break;

    case WM_DISPLAYCHANGE:
      Notify("onDisplayChange");
      break;

    case WM_SETTINGCHANGE:
      if (wparam == SPI_SETWORKAREA) {
        Notify("onDisplayChange");
      }
      break;

    case kSecondInstanceMessage:
      Notify("onSecondInstance");
      return 0;

    case kExitRequestMessage:
      // Same path as the tray's Exit: Dart releases the camera, saves the
      // settings and then asks to quit.
      Notify("onTrayCommand", std::make_unique<EncodableValue>("exit"));
      return 0;

    case kBeginDragMessage:
      BeginDrag();
      return 0;

    case kSettingsClosedMessage:
      if (settings_window_ && !settings_window_->GetHandle()) {
        settings_window_ = nullptr;
        Notify("onSettingsClosed");
      }
      return 0;

    case kQuitMessage:
      DestroyWindow(hwnd);
      return 0;

    case kCameraMessage:
      if (camera_) {
        camera_->HandleNotify(wparam, lparam);
      }
      return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
    case WM_SIZE: {
      const LRESULT result =
          Win32Window::MessageHandler(hwnd, message, wparam, lparam);
      UpdateRegion();
      return result;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
