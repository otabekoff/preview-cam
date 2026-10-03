import '../platform/overlay_platform.dart';
import '../services/monitor_service.dart';
import '../settings/settings_model.dart';

/// Geometry of the overlay window: where it is, and how to move it sensibly
/// across monitors with different sizes and DPI scaling.
///
/// The application thinks in logical pixels (so the overlay keeps its
/// apparent size on every monitor), Windows positions windows in physical
/// pixels; this class converts between the two using the DPI of the monitor
/// the window is going to be on.
class OverlayWindow {
  OverlayWindow(this._platform, this._monitors);

  final OverlayPlatform _platform;
  final MonitorService _monitors;

  /// Last known bounds. Updated by every call here and by [adopt].
  WindowBounds? get bounds => _bounds;
  WindowBounds? _bounds;

  /// Records bounds reported by the OS after the user moved or resized.
  void adopt(WindowBounds bounds) => _bounds = bounds;

  /// Places the window for startup: the remembered position if it is still
  /// valid, otherwise bottom-right of an available monitor.
  Future<WindowBounds> restore(AppSettings settings) async {
    final monitors = await _monitors.monitors();
    return _set(
      resolveStartupRect(
        monitors: monitors,
        logicalWidth: settings.width,
        logicalHeight: settings.height,
        remember: settings.rememberPosition,
        savedX: settings.x,
        savedY: settings.y,
        savedMonitorId: settings.monitorId,
      ),
    );
  }

  /// Moves the window to [preset] on the monitor it is mostly on.
  Future<WindowBounds> moveToPreset(PositionPreset preset) async {
    final monitors = await _monitors.monitors();
    final current = await _platform.getBounds();
    final monitor = _monitorOf(current, monitors);
    // Rescale in case the window is straddling monitors with different DPI.
    final width = (current.logicalWidth * monitor.scale).round();
    final height = (current.logicalHeight * monitor.scale).round();
    return _set(presetRect(preset, monitor, width, height));
  }

  /// Resizes to a logical size, keeping the corner nearest a screen corner
  /// fixed and the window inside the work area.
  Future<WindowBounds> resizeLogical(double width, double height) async {
    final monitors = await _monitors.monitors();
    final current = await _platform.getBounds();
    final monitor = _monitorOf(current, monitors);
    return _set(
      resizeAnchored(
        current.rect,
        (width * monitor.scale).round(),
        (height * monitor.scale).round(),
        monitor,
      ),
    );
  }

  /// Brings the window back if a monitor was unplugged or the desktop layout
  /// changed underneath it. Returns the new bounds when it had to move.
  ///
  /// The logical size is passed in rather than derived from the current
  /// bounds, whose DPI is meaningless once the window is off every monitor.
  Future<WindowBounds?> ensureOnScreen(
    double logicalWidth,
    double logicalHeight,
  ) async {
    final monitors = await _monitors.monitors();
    if (monitors.isEmpty) return null;
    final current = await _platform.getBounds();
    _bounds = current;
    if (visibleFraction(current.rect, monitors) >= 0.5) return null;
    final monitor = monitorContaining(current.rect, monitors);
    return _set(
      presetRect(
        PositionPreset.bottomRight,
        monitor,
        (logicalWidth * monitor.scale).round(),
        (logicalHeight * monitor.scale).round(),
      ),
    );
  }

  MonitorInfo _monitorOf(WindowBounds bounds, List<MonitorInfo> monitors) =>
      monitorById(monitors, bounds.monitorId) ??
      monitorContaining(bounds.rect, monitors);

  Future<WindowBounds> _set(PxRect rect) async =>
      _bounds = await _platform.setBounds(rect);
}
