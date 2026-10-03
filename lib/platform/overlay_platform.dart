import '../services/monitor_service.dart';

/// Position and size of the overlay window as reported by the OS.
class WindowBounds {
  const WindowBounds({
    required this.rect,
    required this.monitorId,
    required this.dpi,
  });

  factory WindowBounds.fromMap(Map<Object?, Object?> map) => WindowBounds(
    rect: PxRect(
      map['x']! as int,
      map['y']! as int,
      map['width']! as int,
      map['height']! as int,
    ),
    monitorId: map['monitor'] as String? ?? '',
    dpi: map['dpi'] as int? ?? 96,
  );

  /// Outer rectangle in physical pixels.
  final PxRect rect;

  /// Monitor containing the majority of the window.
  final String monitorId;
  final int dpi;

  double get scale => dpi / 96.0;
  double get logicalWidth => rect.width / scale;
  double get logicalHeight => rect.height / scale;
}

/// Outline the native window is clipped to.
enum NativeShape { rectangle, rounded, circle }

/// Events raised by the native window.
class OverlayPlatformEvents {
  /// The user finished moving or resizing the window.
  void Function(WindowBounds bounds)? onBoundsChanged;

  /// A registered global hotkey was pressed.
  void Function(int id)? onHotkey;

  /// A tray menu item was chosen (or the icon was clicked).
  void Function(String command)? onTrayCommand;

  /// A camera was plugged in or removed.
  void Function()? onDeviceChange;

  /// Monitors, resolution or the work area changed.
  void Function()? onDisplayChange;

  /// The window was asked to close (Alt+F4).
  void Function()? onCloseRequested;

  /// The user launched the application again while it is running.
  void Function()? onSecondInstance;

  /// The settings window was closed.
  void Function()? onSettingsClosed;

  /// A message from the settings window.
  void Function(Map<Object?, Object?> message)? onRelay;
}

/// Everything the overlay needs from the host operating system.
///
/// This is the seam for other platforms: Windows is implemented by
/// `WindowsOverlayService`; a macOS or Linux port supplies its own
/// implementation without touching the rest of the application.
abstract class OverlayPlatform {
  OverlayPlatformEvents get events;

  Future<List<MonitorInfo>> getMonitors();
  Future<WindowBounds> getBounds();

  /// Moves/resizes the window; [rect] is in physical pixels.
  Future<WindowBounds> setBounds(PxRect rect);

  Future<void> show({bool activate = false});
  Future<void> hide();

  Future<void> setAlwaysOnTop(bool value);
  Future<void> setClickThrough(bool value);

  /// [capturable]: while hidden from the taskbar, stay listed by
  /// screen-capture tools (otherwise the window becomes a tool window).
  Future<void> setSkipTaskbar(bool value, {bool capturable = true});
  Future<void> setOpacity(double value);

  /// [radius] is in logical pixels and only used for [NativeShape.rounded].
  Future<void> setShape(NativeShape shape, double radius);

  /// Width / height enforced while the user resizes; 0 means unconstrained.
  Future<void> setAspectRatio(double ratio);

  /// Smallest allowed length of the shorter side, in logical pixels.
  Future<void> setMinSize(double logical);

  /// Starts a native window drag; call while the primary button is down.
  Future<void> startDrag();

  Future<bool> registerHotkey({
    required int id,
    required int modifiers,
    required int vk,
    bool repeat = false,
  });
  Future<void> unregisterAllHotkeys();

  Future<void> setTrayState({
    required bool visible,
    required bool clickThrough,
    required bool alwaysOnTop,
    required Map<String, String> labels,
  });

  Future<bool> getStartup();
  Future<bool> setStartup(bool enabled);

  Future<void> openSettings();

  /// Sends [message] to the other window (overlay <-> settings).
  Future<void> relay(Map<String, Object?> message);

  /// Opens a system settings page, e.g. the camera privacy page.
  Future<void> openSystemSettings(String uri);

  /// Terminates the process.
  Future<void> quit();
}
