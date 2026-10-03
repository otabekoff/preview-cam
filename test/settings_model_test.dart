import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preview/services/hotkey_service.dart';
import 'package:preview/settings/settings_model.dart';

import 'fakes.dart';

void main() {
  group('AppSettings', () {
    test('defaults match the first-launch requirements', () {
      const s = AppSettings();
      expect((s.width, s.height), (320, 180));
      expect(s.mirror, isTrue);
      expect(s.alwaysOnTop, isTrue);
      expect(s.clickThrough, isFalse);
      expect(s.onboardingShown, isFalse);
      expect(
        s.hotkeys[HotkeyAction.toggleClickThrough]!.label,
        'Ctrl + Alt + C',
      );
    });

    test('survives an encode/decode round trip', () {
      final s = const AppSettings().copyWith(
        cameraId: 'Cam <id>',
        shape: OverlayShape.circle,
        opacity: 0.6,
        x: -1200,
        y: 40,
        monitorId: r'\\.\DISPLAY2',
        clickThrough: true,
        hotkeys: {
          ...defaultHotkeys,
          HotkeyAction.openSettings: null,
          HotkeyAction.sizeUp: const Hotkey(
            Hotkey.control | Hotkey.shift,
            0x26,
          ),
        },
      );
      final decoded = AppSettings.decode(s.encode());
      expect(decoded, s);
      expect(decoded.hotkeys[HotkeyAction.openSettings], isNull);
      expect(decoded.hotkeys[HotkeyAction.sizeUp]!.label, 'Ctrl + Shift + Up');
    });

    test('falls back to defaults for missing, wrong or corrupt data', () {
      expect(AppSettings.decode(null), const AppSettings());
      expect(AppSettings.decode('not json'), const AppSettings());
      final s = AppSettings.decode(
        '{"shape":"hexagon","opacity":"high","height":5,"mirror":false}',
      );
      expect(s.shape, const AppSettings().shape);
      expect(s.opacity, 1);
      expect(s.height, kMinOverlayHeight);
      expect(s.mirror, isFalse);
      expect(s.hotkeys, defaultHotkeys);
    });

    test('merge applies a partial patch and can clear nullable values', () {
      final s = const AppSettings().copyWith(cameraId: 'Cam <id>');
      final merged = s.merge({'cameraId': null, 'opacity': 0.5});
      expect(merged.cameraId, isNull);
      expect(merged.opacity, 0.5);
      expect(merged.shape, s.shape);
    });
  });

  group('hotkeys', () {
    test('physical keys map to Windows virtual-key codes', () {
      expect(vkForPhysicalKey(PhysicalKeyboardKey.keyC), 0x43);
      expect(vkForPhysicalKey(PhysicalKeyboardKey.digit0), 0x30);
      expect(vkForPhysicalKey(PhysicalKeyboardKey.f12), 0x7B);
      expect(vkForPhysicalKey(PhysicalKeyboardKey.equal), 0xBB);
      expect(vkForPhysicalKey(PhysicalKeyboardKey.arrowLeft), 0x25);
      expect(vkForPhysicalKey(PhysicalKeyboardKey.controlLeft), isNull);
    });

    test('service registers bindings and reports conflicts', () async {
      final platform = FakeOverlayPlatform()
        ..takenHotkeys = {HotkeyAction.openSettings.nativeId};
      final service = HotkeyService(platform);
      final fired = <HotkeyAction>[];
      service.onAction = fired.add;

      await service.apply({...defaultHotkeys, HotkeyAction.sizeDown: null});

      expect(platform.hotkeys[HotkeyAction.toggleClickThrough.nativeId], (
        Hotkey.control | Hotkey.alt,
        0x43,
      ));
      expect(
        platform.hotkeys.containsKey(HotkeyAction.sizeDown.nativeId),
        isFalse,
      );
      expect(service.failures, {HotkeyAction.openSettings});

      service.handleNativeHotkey(HotkeyAction.toggleOverlay.nativeId);
      service.handleNativeHotkey(999);
      expect(fired, [HotkeyAction.toggleOverlay]);
    });
  });
}
