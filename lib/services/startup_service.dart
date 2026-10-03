import '../platform/overlay_platform.dart';

/// "Start with Windows".
///
/// Implemented natively as a value under the per-user registry key
/// `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, which needs no
/// administrator rights and shows up in Task Manager's Startup tab.
class StartupService {
  StartupService(this._platform);

  final OverlayPlatform _platform;

  /// Whether the application is currently registered to start at sign-in.
  Future<bool> isEnabled() => _platform.getStartup();

  /// Returns `false` when the registry could not be updated.
  Future<bool> setEnabled(bool enabled) => _platform.setStartup(enabled);
}
