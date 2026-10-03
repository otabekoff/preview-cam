#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "overlay_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Single instance: two overlays would fight over the camera and the global
  // hotkeys. A second launch just asks the running instance to show itself.
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, TRUE, L"Local\\PreviewCam.SingleInstance");
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing =
        ::FindWindowW(Win32Window::ClassName(), OverlayWindow::kTitle);
#ifdef NDEBUG
    if (existing) {
      ::PostMessage(existing, OverlayWindow::kSecondInstanceMessage, 0, 0);
    }
    return EXIT_SUCCESS;
#else
    // Development builds take over instead: `flutter run` must start even
    // while an installed copy is sitting in the tray. The running instance
    // is asked to exit (it saves its settings first); the mutex becomes
    // ours once it is gone.
    if (existing) {
      ::PostMessage(existing, OverlayWindow::kExitRequestMessage, 0, 0);
    }
    const DWORD waited = ::WaitForSingleObject(instance_mutex, 10000);
    if (waited != WAIT_OBJECT_0 && waited != WAIT_ABANDONED) {
      return EXIT_FAILURE;
    }
#endif
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  OverlayWindow window(project);
  if (!window.CreateOverlay()) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (instance_mutex) {
    ::ReleaseMutex(instance_mutex);
    ::CloseHandle(instance_mutex);
  }
  return EXIT_SUCCESS;
}
