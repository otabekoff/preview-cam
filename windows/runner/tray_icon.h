#ifndef RUNNER_TRAY_ICON_H_
#define RUNNER_TRAY_ICON_H_

#include <windows.h>

#include <shellapi.h>

#include <functional>
#include <string>

// Notification-area (system tray) icon with the application's context menu.
//
// The icon is owned by a hidden top-level window rather than by the overlay
// window. The overlay can carry WS_EX_NOACTIVATE (click-through mode), and a
// window that cannot be activated cannot become the foreground window, which
// TrackPopupMenu needs in order to dismiss the menu when the user clicks
// elsewhere.
//
// Menu selections are reported as command strings ("toggleVisible",
// "position:bottomRight", "exit", ...) so the Dart side owns all behaviour.
class TrayIcon {
 public:
  // Menu texts; replaced with translations by the Dart side.
  struct Labels {
    std::wstring show = L"Show Camera";
    std::wstring hide = L"Hide Camera";
    std::wstring click_through = L"Click-through";
    std::wstring always_on_top = L"Always on top";
    std::wstring position = L"Position";
    std::wstring top_left = L"Top Left";
    std::wstring top_right = L"Top Right";
    std::wstring bottom_left = L"Bottom Left";
    std::wstring bottom_right = L"Bottom Right";
    std::wstring center = L"Center";
    std::wstring settings = L"Settings";
    std::wstring exit = L"Exit";
  };

  struct MenuState {
    bool visible = true;
    bool click_through = false;
    bool always_on_top = true;
    Labels labels;
  };

  using CommandHandler = std::function<void(const std::string& command)>;

  explicit TrayIcon(CommandHandler handler);
  ~TrayIcon();

  TrayIcon(const TrayIcon&) = delete;
  TrayIcon& operator=(const TrayIcon&) = delete;

  // Adds the icon to the notification area.
  bool Create(HICON icon, const std::wstring& tooltip);

  // Updates the check marks / labels shown the next time the menu opens.
  void SetState(const MenuState& state) { state_ = state; }

 private:
  static LRESULT CALLBACK WndProc(HWND hwnd,
                                  UINT message,
                                  WPARAM wparam,
                                  LPARAM lparam) noexcept;

  void AddIcon();
  void ShowMenu(POINT anchor);

  CommandHandler handler_;
  MenuState state_;
  HWND hwnd_ = nullptr;
  NOTIFYICONDATAW nid_ = {};
  bool added_ = false;
  // Broadcast by Explorer when the taskbar is (re)created, e.g. after an
  // Explorer crash; the icon must be added again.
  UINT taskbar_created_message_ = 0;
};

#endif  // RUNNER_TRAY_ICON_H_
