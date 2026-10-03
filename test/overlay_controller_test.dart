import 'package:flutter_test/flutter_test.dart';
import 'package:preview/camera/camera_controller.dart';
import 'package:preview/overlay/overlay_controller.dart';
import 'package:preview/services/hotkey_service.dart';
import 'package:preview/services/monitor_service.dart';
import 'package:preview/settings/settings_bridge.dart';
import 'package:preview/settings/settings_controller.dart';
import 'package:preview/settings/settings_model.dart';

import 'fakes.dart';

void main() {
  late FakeOverlayPlatform platform;
  late FakeCameraBackend cameraBackend;
  late MemoryStore store;
  late OverlayController controller;

  Future<void> start({AppSettings? saved, List<MonitorInfo>? monitors}) async {
    platform = FakeOverlayPlatform(monitors: monitors);
    cameraBackend = FakeCameraBackend();
    store = MemoryStore(saved);
    controller = OverlayController(
      platform: platform,
      settings: SettingsController(store, saveDelay: Duration.zero),
      camera: CameraFeedController(cameraBackend),
    );
    await controller.init();
    await pumpEventQueue();
  }

  tearDown(() => controller.dispose());

  test(
    'first launch: bottom-right, topmost, camera running, hint once',
    () async {
      await start();

      expect(platform.rect, const PxRect(1580, 832, 320, 180));
      expect(platform.calls, contains('setAlwaysOnTop true'));
      expect(platform.calls, contains('setShape rounded 16.0'));
      expect(platform.shown, isTrue);
      expect(controller.camera.status, CameraStatus.running);
      expect(controller.hint.value, isTrue);
      expect(platform.hotkeys.length, HotkeyAction.values.length);
      expect(store.saved!.onboardingShown, isTrue);
      expect(store.saved!.monitorId, primary.id);

      // Second launch with the saved settings: no hint.
      controller.dispose();
      await start(saved: store.saved);
      expect(controller.hint.value, isFalse);
    },
  );

  test('restores the saved position on a second monitor', () async {
    await start(
      monitors: [primary, secondary],
      saved: const AppSettings(x: -2000, y: 300, monitorId: r'\\.\DISPLAY2'),
    );
    expect(platform.rect, const PxRect(-2000, 300, 480, 270));
    expect(controller.settings.value.width, closeTo(320, 0.01));
  });

  test('moves back on-screen when its monitor is unplugged', () async {
    await start(
      monitors: [primary, secondary],
      saved: const AppSettings(x: -2000, y: 300, monitorId: r'\\.\DISPLAY2'),
    );
    platform.monitors = [primary];
    platform.events.onDisplayChange!();
    await pumpEventQueue();

    expect(platform.rect, const PxRect(1580, 832, 320, 180));
    expect(controller.settings.value.monitorId, primary.id);
  });

  test(
    'click-through hotkey toggles the native style, tray and toast',
    () async {
      await start();
      final id = HotkeyAction.toggleClickThrough.nativeId;

      platform.events.onHotkey!(id);
      await pumpEventQueue();
      expect(platform.calls, contains('setClickThrough true'));
      expect(platform.calls.last, 'tray true true true');
      expect(controller.toast.value, contains('Ctrl + Alt + C'));
      expect(store.saved!.clickThrough, isTrue);

      platform.events.onHotkey!(id);
      await pumpEventQueue();
      expect(platform.calls, contains('setClickThrough false'));
      expect(controller.toast.value, 'Click-through off');
    },
  );

  test(
    'switching to a circle makes the window square, anchored bottom-right',
    () async {
      await start();
      controller.settings.update((s) => s.copyWith(shape: OverlayShape.circle));
      await pumpEventQueue();

      expect(platform.calls, contains('setShape circle 16.0'));
      expect(platform.calls, contains('setAspectRatio 1.000'));
      expect(platform.rect, const PxRect(1720, 832, 180, 180));
    },
  );

  test('size hotkeys scale the overlay and keep its aspect ratio', () async {
    await start();
    platform.events.onHotkey!(HotkeyAction.sizeUp.nativeId);
    await pumpEventQueue();

    expect(platform.rect.height, 198);
    expect(platform.rect.width, 352);
    expect(platform.rect.right, 1900);
    expect(platform.rect.bottom, 1012);
  });

  test('a native move or resize is remembered', () async {
    await start();
    platform.rect = const PxRect(100, 200, 640, 360);
    platform.events.onBoundsChanged!(platform.bounds);
    await pumpEventQueue();

    expect(store.saved!.x, 100);
    expect(store.saved!.y, 200);
    expect(store.saved!.width, 640);
    expect(store.saved!.height, 360);
  });

  test('hiding releases the camera; showing reopens it', () async {
    await start();
    await controller.hide();
    await pumpEventQueue();
    expect(platform.shown, isFalse);
    expect(cameraBackend.isOpen, isFalse);

    platform.events.onTrayCommand!('toggleVisible');
    await pumpEventQueue();
    expect(platform.shown, isTrue);
    expect(controller.camera.status, CameraStatus.running);
  });

  test('tray: position presets and exit', () async {
    await start();
    platform.events.onTrayCommand!('position:topLeft');
    await pumpEventQueue();
    expect(platform.rect, const PxRect(20, 20, 320, 180));

    platform.events.onTrayCommand!('exit');
    await pumpEventQueue();
    expect(cameraBackend.isOpen, isFalse);
    expect(store.saved!.x, 20);
    expect(platform.calls.last, 'quit');
  });

  test('settings window: snapshot on hello, patches are applied', () async {
    await start();
    platform.relayed.clear();

    platform.events.onRelay!({'type': BridgeMessage.hello});
    await pumpEventQueue();
    final snapshot = OverlaySnapshot.fromMessage(platform.relayed.last);
    expect(snapshot.cameras.single.name, 'Front Cam');
    expect(snapshot.cameraStatus, CameraStatus.running);
    expect((snapshot.previewWidth, snapshot.previewHeight), (1280, 720));

    platform.events.onRelay!({
      'type': BridgeMessage.patch,
      'values': {'opacity': 0.5, 'startWithWindows': true, 'mirror': false},
    });
    await pumpEventQueue();
    expect(platform.calls, contains('setOpacity 0.5'));
    expect(platform.startup, isTrue);
    expect(controller.settings.value.mirror, isFalse);
  });

  test(
    'virtual camera follows the overlay shape, crop and mirroring',
    () async {
      await start();
      expect(cameraBackend.outputs.last.enabled, isFalse);

      controller.settings.update((s) => s.copyWith(virtualCamera: true));
      await pumpEventQueue();
      var output = cameraBackend.outputs.last;
      expect(output.enabled, isTrue);
      expect(output.shape, 1); // rounded
      expect(output.aspect, closeTo(16 / 9, 0.01));
      expect(output.radius, closeTo(16 / 180, 0.001));
      expect(output.mirror, isTrue);

      controller.settings.update(
        (s) => s.copyWith(shape: OverlayShape.circle, mirror: false),
      );
      await pumpEventQueue();
      output = cameraBackend.outputs.last;
      expect(output.shape, 2);
      expect(output.aspect, closeTo(1, 0.01));
      expect(output.mirror, isFalse);
    },
  );

  test('virtual camera switches itself off when it cannot be set up', () async {
    await start();
    cameraBackend.outputAvailable = false;
    controller.settings.update((s) => s.copyWith(virtualCamera: true));
    await pumpEventQueue();

    expect(controller.settings.value.virtualCamera, isFalse);
    expect(controller.toast.value, contains('Virtual camera'));
  });

  test('recording a shortcut suspends the global hotkeys', () async {
    await start();
    platform.events.onRelay!({'type': BridgeMessage.capture, 'active': true});
    await pumpEventQueue();
    expect(platform.hotkeys, isEmpty);

    platform.events.onSettingsClosed!();
    await pumpEventQueue();
    expect(platform.hotkeys.length, HotkeyAction.values.length);
  });
}
