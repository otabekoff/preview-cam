#include "tray_icon.h"

#include <windowsx.h>

namespace {

constexpr wchar_t kTrayWindowClass[] = L"PREVIEW_CAM_TRAY";
constexpr UINT kTrayCallbackMessage = WM_APP + 1;
constexpr UINT kTrayIconId = 1;

// Menu command identifiers, mapped to command strings in CommandFor().
enum MenuId : UINT {
  kToggleVisible = 1,
  kToggleClickThrough,
  kToggleAlwaysOnTop,
  kPositionTopLeft,
  kPositionTopRight,
  kPositionBottomLeft,
  kPositionBottomRight,
  kPositionCenter,
  kSettings,
  kExit,
};

const char* CommandFor(UINT id) {
  switch (id) {
    case kToggleVisible:
      return "toggleVisible";
    case kToggleClickThrough:
      return "toggleClickThrough";
    case kToggleAlwaysOnTop:
      return "toggleAlwaysOnTop";
    case kPositionTopLeft:
      return "position:topLeft";
    case kPositionTopRight:
      return "position:topRight";
    case kPositionBottomLeft:
      return "position:bottomLeft";
    case kPositionBottomRight:
      return "position:bottomRight";
    case kPositionCenter:
      return "position:center";
    case kSettings:
      return "settings";
    case kExit:
      return "exit";
    default:
      return nullptr;
  }
}

}  // namespace

TrayIcon::TrayIcon(CommandHandler handler) : handler_(std::move(handler)) {}

TrayIcon::~TrayIcon() {
  if (added_) {
    Shell_NotifyIconW(NIM_DELETE, &nid_);
  }
  if (hwnd_) {
    DestroyWindow(hwnd_);
  }
  UnregisterClassW(kTrayWindowClass, GetModuleHandle(nullptr));
}

bool TrayIcon::Create(HICON icon, const std::wstring& tooltip) {
  WNDCLASSW window_class{};
  window_class.lpfnWndProc = TrayIcon::WndProc;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kTrayWindowClass;
  RegisterClassW(&window_class);

  // Never shown; exists to receive tray callbacks and to own the popup menu.
  hwnd_ = CreateWindowExW(WS_EX_TOOLWINDOW, kTrayWindowClass, L"", WS_POPUP, 0,
                          0, 0, 0, nullptr, nullptr, window_class.hInstance,
                          this);
  if (!hwnd_) {
    return false;
  }
  SetWindowLongPtr(hwnd_, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));

  taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");

  nid_.cbSize = sizeof(nid_);
  nid_.hWnd = hwnd_;
  nid_.uID = kTrayIconId;
  nid_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP;
  nid_.uCallbackMessage = kTrayCallbackMessage;
  nid_.hIcon = icon;
  wcsncpy_s(nid_.szTip, tooltip.c_str(), _TRUNCATE);
  nid_.uVersion = NOTIFYICON_VERSION_4;

  AddIcon();
  return added_;
}

void TrayIcon::AddIcon() {
  added_ = Shell_NotifyIconW(NIM_ADD, &nid_) != FALSE;
  if (added_) {
    Shell_NotifyIconW(NIM_SETVERSION, &nid_);
  }
}

void TrayIcon::ShowMenu(POINT anchor) {
  const Labels& labels = state_.labels;
  HMENU position = CreatePopupMenu();
  AppendMenuW(position, MF_STRING, kPositionTopLeft, labels.top_left.c_str());
  AppendMenuW(position, MF_STRING, kPositionTopRight, labels.top_right.c_str());
  AppendMenuW(position, MF_STRING, kPositionBottomLeft,
              labels.bottom_left.c_str());
  AppendMenuW(position, MF_STRING, kPositionBottomRight,
              labels.bottom_right.c_str());
  AppendMenuW(position, MF_STRING, kPositionCenter, labels.center.c_str());

  HMENU menu = CreatePopupMenu();
  AppendMenuW(menu, MF_STRING, kToggleVisible,
              state_.visible ? labels.hide.c_str() : labels.show.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING | (state_.click_through ? MF_CHECKED : 0),
              kToggleClickThrough, labels.click_through.c_str());
  AppendMenuW(menu, MF_STRING | (state_.always_on_top ? MF_CHECKED : 0),
              kToggleAlwaysOnTop, labels.always_on_top.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_POPUP, reinterpret_cast<UINT_PTR>(position),
              labels.position.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kSettings, labels.settings.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kExit, labels.exit.c_str());
  SetMenuDefaultItem(menu, kToggleVisible, FALSE);

  // Required so the menu closes when the user clicks outside of it.
  SetForegroundWindow(hwnd_);
  UINT flags = TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON;
  flags |= GetSystemMetrics(SM_MENUDROPALIGNMENT) ? TPM_RIGHTALIGN
                                                  : TPM_LEFTALIGN;
  const UINT selected = static_cast<UINT>(
      TrackPopupMenuEx(menu, flags, anchor.x, anchor.y, hwnd_, nullptr));
  PostMessage(hwnd_, WM_NULL, 0, 0);
  DestroyMenu(menu);  // Also destroys the |position| submenu.

  if (const char* command = CommandFor(selected)) {
    handler_(command);
  }
}

// static
LRESULT CALLBACK TrayIcon::WndProc(HWND hwnd,
                                   UINT message,
                                   WPARAM wparam,
                                   LPARAM lparam) noexcept {
  auto* self =
      reinterpret_cast<TrayIcon*>(GetWindowLongPtr(hwnd, GWLP_USERDATA));
  if (self) {
    if (message == kTrayCallbackMessage) {
      // NOTIFYICON_VERSION_4: LOWORD(lparam) is the event, wparam holds the
      // anchor point in screen coordinates.
      switch (LOWORD(lparam)) {
        case NIN_SELECT:
        case NIN_KEYSELECT:
          self->handler_("toggleVisible");
          return 0;
        case WM_CONTEXTMENU: {
          POINT anchor = {GET_X_LPARAM(wparam), GET_Y_LPARAM(wparam)};
          self->ShowMenu(anchor);
          return 0;
        }
      }
      return 0;
    }
    if (message == self->taskbar_created_message_ &&
        self->taskbar_created_message_ != 0) {
      self->AddIcon();
      return 0;
    }
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}
