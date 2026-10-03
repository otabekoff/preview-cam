import 'package:flutter_test/flutter_test.dart';
import 'package:preview/services/monitor_service.dart';

import 'fakes.dart';

void main() {
  group('presetRect', () {
    test('bottom-right keeps a 20px margin above the taskbar', () {
      final rect = presetRect(PositionPreset.bottomRight, primary, 320, 180);
      expect(rect, const PxRect(1920 - 20 - 320, 1032 - 20 - 180, 320, 180));
    });

    test('covers every corner and the centre of the work area', () {
      PxRect at(PositionPreset preset) => presetRect(preset, primary, 320, 180);
      expect(at(PositionPreset.topLeft), const PxRect(20, 20, 320, 180));
      expect(at(PositionPreset.topRight), const PxRect(1580, 20, 320, 180));
      expect(at(PositionPreset.bottomLeft), const PxRect(20, 832, 320, 180));
      expect(at(PositionPreset.center), const PxRect(800, 426, 320, 180));
    });

    test('scales the margin with DPI and handles negative coordinates', () {
      // 20 logical px at 150% = 30 physical px.
      final rect = presetRect(PositionPreset.bottomRight, secondary, 480, 270);
      expect(rect, const PxRect(0 - 30 - 480, 1528 - 30 - 270, 480, 270));
    });
  });

  test('clampToWorkArea pulls a window back inside', () {
    expect(
      clampToWorkArea(const PxRect(1800, 1000, 320, 180), primary),
      const PxRect(1600, 852, 320, 180),
    );
    expect(
      clampToWorkArea(const PxRect(-50, -50, 320, 180), primary),
      const PxRect(0, 0, 320, 180),
    );
  });

  group('resizeAnchored', () {
    test('a bottom-right overlay grows up and to the left', () {
      const current = PxRect(1580, 832, 320, 180);
      final rect = resizeAnchored(current, 640, 360, primary);
      expect(rect.right, current.right);
      expect(rect.bottom, current.bottom);
    });

    test('a top-left overlay grows down and to the right', () {
      final rect = resizeAnchored(
        const PxRect(20, 20, 320, 180),
        640,
        360,
        primary,
      );
      expect(rect, const PxRect(20, 20, 640, 360));
    });
  });

  test(
    'monitorContaining picks the monitor with the majority of the window',
    () {
      final monitors = [primary, secondary];
      expect(
        monitorContaining(const PxRect(-100, 100, 320, 180), monitors),
        primary,
      );
      expect(
        monitorContaining(const PxRect(-250, 100, 320, 180), monitors),
        secondary,
      );
      expect(
        monitorContaining(const PxRect(9000, 9000, 320, 180), monitors),
        primary,
      );
    },
  );

  group('resolveStartupRect', () {
    PxRect resolve({
      List<MonitorInfo>? monitors,
      int? x,
      int? y,
      String? monitorId,
      bool remember = true,
    }) => resolveStartupRect(
      monitors: monitors ?? [primary, secondary],
      logicalWidth: 320,
      logicalHeight: 180,
      remember: remember,
      savedX: x,
      savedY: y,
      savedMonitorId: monitorId,
    );

    test('first launch opens bottom-right on the primary monitor', () {
      expect(resolve(), const PxRect(1580, 832, 320, 180));
    });

    test('restores a saved position on its monitor, sized for that DPI', () {
      expect(
        resolve(x: -2000, y: 300, monitorId: secondary.id),
        const PxRect(-2000, 300, 480, 270),
      );
    });

    test('falls back to the primary monitor when the saved one is gone', () {
      expect(
        resolve(monitors: [primary], x: -2000, y: 300, monitorId: secondary.id),
        const PxRect(1580, 832, 320, 180),
      );
    });

    test('never restores a position that is mostly off-screen', () {
      expect(
        resolve(x: 5000, y: 5000, monitorId: primary.id),
        const PxRect(1580, 832, 320, 180),
      );
    });

    test('ignores the saved position when "remember position" is off', () {
      expect(
        resolve(x: 100, y: 100, monitorId: primary.id, remember: false),
        const PxRect(1580, 832, 320, 180),
      );
    });
  });
}
