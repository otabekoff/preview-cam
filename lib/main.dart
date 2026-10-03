import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'camera/camera_backend.dart';
import 'camera/camera_controller.dart';
import 'overlay/overlay_controller.dart';
import 'platform/windows/windows_overlay_service.dart';
import 'services/preferences_service.dart';
import 'settings/settings_controller.dart';
import 'settings/settings_view.dart';

/// Entrypoint of the overlay window (the main Flutter engine).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (defaultTargetPlatform != TargetPlatform.windows) {
    // The native window work is Windows-only for now; see OverlayPlatform.
    runApp(const UnsupportedPlatformApp());
    return;
  }

  final controller = OverlayController(
    platform: WindowsOverlayService(),
    settings: SettingsController(PreferencesService()),
    camera: CameraFeedController(WindowsCameraBackend()),
  );
  runApp(OverlayApp(controller: controller));
  // Restores the window, registers hotkeys, shows the overlay and starts the
  // camera. The native window stays hidden until this has positioned it.
  await controller.init();
}

/// Entrypoint of the settings window, which the Windows runner starts in a
/// second Flutter engine (see `windows/runner/settings_window.cpp`).
@pragma('vm:entry-point')
void settingsMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(SettingsApp(link: SettingsLink()));
}
