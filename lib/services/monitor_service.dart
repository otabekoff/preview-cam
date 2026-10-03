import 'dart:math' as math;

import '../platform/overlay_platform.dart';

/// Margin kept between the overlay and the edge of the work area when a
/// position preset is applied, in logical pixels.
const double kPresetMargin = 20;

/// An integer rectangle in physical pixels, in virtual-screen coordinates
/// (the coordinate space shared by all monitors; can be negative).
class PxRect {
  const PxRect(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;

  int get right => x + width;
  int get bottom => y + height;
  int get area => width * height;
  double get centerX => x + width / 2;
  double get centerY => y + height / 2;

  /// Area shared with [other], in pixels.
  int overlap(PxRect other) {
    final int w = math.min<int>(right, other.right) - math.max<int>(x, other.x);
    final int h =
        math.min<int>(bottom, other.bottom) - math.max<int>(y, other.y);
    return w > 0 && h > 0 ? w * h : 0;
  }

  @override
  bool operator ==(Object other) =>
      other is PxRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() => 'PxRect($x, $y, $width x $height)';
}

/// A display as reported by Windows.
class MonitorInfo {
  const MonitorInfo({
    required this.id,
    required this.bounds,
    required this.workArea,
    required this.dpi,
    this.primary = false,
  });

  factory MonitorInfo.fromMap(Map<Object?, Object?> map) => MonitorInfo(
    id: map['id']! as String,
    primary: map['primary'] as bool? ?? false,
    dpi: map['dpi'] as int? ?? 96,
    bounds: PxRect(
      map['x']! as int,
      map['y']! as int,
      map['width']! as int,
      map['height']! as int,
    ),
    workArea: PxRect(
      map['workX']! as int,
      map['workY']! as int,
      map['workWidth']! as int,
      map['workHeight']! as int,
    ),
  );

  /// Device name, e.g. `\\.\DISPLAY1`.
  final String id;
  final PxRect bounds;

  /// [bounds] minus the taskbar and other docked app bars.
  final PxRect workArea;
  final int dpi;
  final bool primary;

  /// Physical pixels per logical pixel on this monitor.
  double get scale => dpi / 96.0;
}

/// Quick positions offered in the tray menu and settings.
enum PositionPreset {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  center;

  static PositionPreset? byName(String? name) {
    for (final preset in values) {
      if (preset.name == name) return preset;
    }
    return null;
  }
}

/// Queries the connected displays.
class MonitorService {
  MonitorService(this._platform);

  final OverlayPlatform _platform;

  Future<List<MonitorInfo>> monitors() => _platform.getMonitors();
}

// ---------------------------------------------------------------------------
// Pure placement maths. Everything below works in physical pixels and has no
// platform dependencies, so it is unit tested directly.
// ---------------------------------------------------------------------------

MonitorInfo primaryMonitor(List<MonitorInfo> monitors) =>
    monitors.firstWhere((m) => m.primary, orElse: () => monitors.first);

MonitorInfo? monitorById(List<MonitorInfo> monitors, String? id) {
  for (final monitor in monitors) {
    if (monitor.id == id) return monitor;
  }
  return null;
}

/// The monitor containing the largest part of [rect], or the primary monitor
/// when [rect] is entirely off-screen.
MonitorInfo monitorContaining(PxRect rect, List<MonitorInfo> monitors) {
  MonitorInfo? best;
  var bestOverlap = 0;
  for (final monitor in monitors) {
    final overlap = rect.overlap(monitor.bounds);
    if (overlap > bestOverlap) {
      best = monitor;
      bestOverlap = overlap;
    }
  }
  return best ?? primaryMonitor(monitors);
}

/// Fraction (0..1) of [rect] that lies inside the work area of any monitor.
double visibleFraction(PxRect rect, List<MonitorInfo> monitors) {
  if (rect.area <= 0) return 0;
  var visible = 0;
  for (final monitor in monitors) {
    visible += rect.overlap(monitor.workArea);
  }
  return visible / rect.area;
}

/// A [width] x [height] window placed at [preset] inside the work area of
/// [monitor], so it never ends up behind the taskbar.
PxRect presetRect(
  PositionPreset preset,
  MonitorInfo monitor,
  int width,
  int height, {
  double margin = kPresetMargin,
}) {
  final work = monitor.workArea;
  final m = (margin * monitor.scale).round();
  final left = work.x + m;
  final top = work.y + m;
  final right = work.right - m - width;
  final bottom = work.bottom - m - height;
  final rect = switch (preset) {
    PositionPreset.topLeft => PxRect(left, top, width, height),
    PositionPreset.topRight => PxRect(right, top, width, height),
    PositionPreset.bottomLeft => PxRect(left, bottom, width, height),
    PositionPreset.bottomRight => PxRect(right, bottom, width, height),
    PositionPreset.center => PxRect(
      work.x + (work.width - width) ~/ 2,
      work.y + (work.height - height) ~/ 2,
      width,
      height,
    ),
  };
  return clampToWorkArea(rect, monitor);
}

/// Moves [rect] the minimum distance needed to sit inside [monitor]'s work
/// area. A rectangle larger than the work area is aligned to its top-left.
PxRect clampToWorkArea(PxRect rect, MonitorInfo monitor) {
  final work = monitor.workArea;
  final x = rect.width >= work.width
      ? work.x
      : rect.x.clamp(work.x, work.right - rect.width).toInt();
  final y = rect.height >= work.height
      ? work.y
      : rect.y.clamp(work.y, work.bottom - rect.height).toInt();
  return PxRect(x, y, rect.width, rect.height);
}

/// Resizes [current] to [width] x [height], keeping fixed whichever corner is
/// nearest to a corner of the work area. An overlay parked bottom-right
/// therefore grows up and to the left instead of off the screen.
PxRect resizeAnchored(
  PxRect current,
  int width,
  int height,
  MonitorInfo monitor,
) {
  final work = monitor.workArea;
  final anchorRight = current.centerX > work.centerX;
  final anchorBottom = current.centerY > work.centerY;
  final x = anchorRight ? current.right - width : current.x;
  final y = anchorBottom ? current.bottom - height : current.y;
  return clampToWorkArea(PxRect(x, y, width, height), monitor);
}

/// Decides where the overlay opens.
///
/// The saved position is restored when [remember] is set, the saved monitor
/// is still connected, and the window would be mostly visible there. In every
/// other case (first launch, monitor unplugged, resolution changed) the
/// overlay falls back to the bottom-right of an available monitor instead of
/// being left off-screen.
PxRect resolveStartupRect({
  required List<MonitorInfo> monitors,
  required double logicalWidth,
  required double logicalHeight,
  required bool remember,
  int? savedX,
  int? savedY,
  String? savedMonitorId,
}) {
  final saved = remember ? monitorById(monitors, savedMonitorId) : null;
  final monitor = saved ?? primaryMonitor(monitors);
  final width = (logicalWidth * monitor.scale).round();
  final height = (logicalHeight * monitor.scale).round();

  if (saved != null && savedX != null && savedY != null) {
    final rect = PxRect(savedX, savedY, width, height);
    if (rect.overlap(saved.workArea) >= rect.area * 0.5) {
      return clampToWorkArea(rect, saved);
    }
  }
  return presetRect(PositionPreset.bottomRight, monitor, width, height);
}
