import '../platform/overlay_platform.dart';

/// The system-tray icon and its menu.
///
/// The icon and menu are native (`windows/runner/tray_icon.cpp`); this class
/// keeps the menu's check marks and (translated) labels in sync and forwards
/// the chosen command.
///
/// Commands: `toggleVisible`, `toggleClickThrough`, `toggleAlwaysOnTop`,
/// `position:<preset name>`, `settings`, `exit`.
class TrayService {
  TrayService(this._platform);

  final OverlayPlatform _platform;

  Future<void> update({
    required bool visible,
    required bool clickThrough,
    required bool alwaysOnTop,
    required Map<String, String> labels,
  }) => _platform.setTrayState(
    visible: visible,
    clickThrough: clickThrough,
    alwaysOnTop: alwaysOnTop,
    labels: labels,
  );
}
