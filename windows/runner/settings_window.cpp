#include "settings_window.h"

#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <shellapi.h>

#include <algorithm>
#include <optional>

namespace {

constexpr wchar_t kSettingsTitle[] = L"Preview Cam Settings";
// Client-area size in logical pixels.
constexpr int kClientWidth = 440;
constexpr int kClientHeight = 680;
constexpr DWORD kStyle =
    WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX;

}  // namespace

SettingsWindow::SettingsWindow(HWND owner,
                               UINT closed_message,
                               RelayHandler on_relay)
    : owner_(owner),
      closed_message_(closed_message),
      on_relay_(std::move(on_relay)),
      project_(L"data") {
  project_.set_dart_entrypoint("settingsMain");
}

SettingsWindow::~SettingsWindow() {}

bool SettingsWindow::Open(HMONITOR monitor) {
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  GetMonitorInfo(monitor, &info);
  const UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const double scale = dpi / 96.0;

  RECT frame = {0, 0, static_cast<LONG>(kClientWidth * scale),
                static_cast<LONG>(kClientHeight * scale)};
  AdjustWindowRectExForDpi(&frame, kStyle, FALSE, 0, dpi);
  const LONG work_width = info.rcWork.right - info.rcWork.left;
  const LONG work_height = info.rcWork.bottom - info.rcWork.top;
  const LONG width = std::min(frame.right - frame.left, work_width);
  const LONG height = std::min(frame.bottom - frame.top, work_height);
  frame.left = info.rcWork.left + (work_width - width) / 2;
  frame.top = info.rcWork.top + (work_height - height) / 2;
  frame.right = frame.left + width;
  frame.bottom = frame.top + height;

  return Create(kSettingsTitle, frame, kStyle, 0);
}

bool SettingsWindow::OnCreate() {
  RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  // No plugins are registered: the settings UI gets everything it needs
  // (settings, camera list, status) from the overlay engine via the relay.

  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "preview/native",
      &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "relay") {
          if (call.arguments()) {
            on_relay_(*call.arguments());
          }
          result->Success();
        } else if (call.method_name() == "close") {
          result->Success();
          PostMessage(GetHandle(), WM_CLOSE, 0, 0);
        } else if (call.method_name() == "openUrl") {
          // Footer links. Only web addresses are passed to the shell.
          const std::string* url =
              call.arguments() ? std::get_if<std::string>(call.arguments())
                               : nullptr;
          if (url && url->rfind("https://", 0) == 0) {
            const int length = MultiByteToWideChar(
                CP_UTF8, 0, url->c_str(), -1, nullptr, 0);
            std::wstring wide(length > 0 ? length - 1 : 0, L'\0');
            if (length > 1) {
              MultiByteToWideChar(CP_UTF8, 0, url->c_str(), -1, wide.data(),
                                  length);
              ShellExecuteW(nullptr, L"open", wide.c_str(), nullptr, nullptr,
                            SW_SHOWNORMAL);
            }
          }
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() { this->Show(); });
  // Ensures a frame is pending so the callback above fires.
  flutter_controller_->ForceRedraw();
  return true;
}

void SettingsWindow::OnDestroy() {
  channel_ = nullptr;
  flutter_controller_ = nullptr;
  Win32Window::OnDestroy();
}

void SettingsWindow::SendRelay(const flutter::EncodableValue& message) {
  if (channel_) {
    channel_->InvokeMethod(
        "onRelay", std::make_unique<flutter::EncodableValue>(message));
  }
}

void SettingsWindow::BringToFront() {
  HWND hwnd = GetHandle();
  if (!hwnd) {
    return;
  }
  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  }
  SetForegroundWindow(hwnd);
}

LRESULT SettingsWindow::MessageHandler(HWND hwnd,
                                       UINT const message,
                                       WPARAM const wparam,
                                       LPARAM const lparam) noexcept {
  // Handled before Flutter sees it: the engine's lifecycle manager treats
  // WM_CLOSE on the last visible window as an application-exit request, but
  // closing Settings must never quit the (possibly hidden) overlay.
  if (message == WM_CLOSE) {
    DestroyWindow(hwnd);
    return 0;
  }

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
    case WM_DESTROY: {
      // The base handler tears down the engine. The owner then deletes this
      // object once the message has finished dispatching.
      const HWND owner = owner_;
      const UINT closed_message = closed_message_;
      const LRESULT result =
          Win32Window::MessageHandler(hwnd, message, wparam, lparam);
      PostMessage(owner, closed_message, 0, 0);
      return result;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
