#ifndef RUNNER_SETTINGS_WINDOW_H_
#define RUNNER_SETTINGS_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <functional>
#include <memory>

#include "win32_window.h"

// A regular (titled) window hosting the settings UI.
//
// It runs a second Flutter engine that starts at the Dart `settingsMain`
// entrypoint. The engine only exists while the window is open, so the overlay
// carries no settings-UI cost during normal use. The two engines do not share
// Dart state; they exchange messages through OverlayWindow, which relays
// `relay` calls from one engine as `onRelay` calls on the other.
class SettingsWindow : public Win32Window {
 public:
  using RelayHandler = std::function<void(const flutter::EncodableValue&)>;

  // |owner| receives |closed_message| after this window has been destroyed.
  SettingsWindow(HWND owner, UINT closed_message, RelayHandler on_relay);
  virtual ~SettingsWindow();

  // Creates the window centred in the work area of |monitor|.
  bool Open(HMONITOR monitor);

  // Delivers |message| to the settings engine as an `onRelay` call.
  void SendRelay(const flutter::EncodableValue& message);

  // Restores and activates the window.
  void BringToFront();

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window,
                         UINT const message,
                         WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  HWND owner_;
  UINT closed_message_;
  RelayHandler on_relay_;
  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

#endif  // RUNNER_SETTINGS_WINDOW_H_
