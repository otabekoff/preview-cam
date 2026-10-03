import 'package:flutter_test/flutter_test.dart';
import 'package:preview/camera/camera_backend.dart';
import 'package:preview/camera/camera_controller.dart';
import 'package:preview/camera/camera_device.dart';
import 'package:preview/settings/settings_model.dart';

import 'fakes.dart';

void main() {
  late FakeCameraBackend backend;
  late CameraFeedController camera;

  setUp(() {
    backend = FakeCameraBackend();
    camera = CameraFeedController(backend);
  });

  test('opens the first camera when there is no preference', () async {
    await camera.start(resolution: CameraResolution.veryHigh, fps: 30);

    expect(camera.status, CameraStatus.running);
    expect(camera.active!.name, 'Front Cam');
    expect(camera.textureId, 7);
    expect(camera.aspectRatio, closeTo(16 / 9, 0.001));
    expect(backend.requestedHeight, 1080);
    expect(backend.requestedFps, 30);
  });

  test('opens a virtual camera and reports its transparency', () async {
    const nvidia = CameraDevice(
      id: 'sw:nvidia',
      name: 'Camera (NVIDIA Broadcast)',
    );
    backend
      ..available = [...backend.available, nvidia]
      ..hasAlpha = true;

    await camera.start(preferredKey: nvidia.key);

    expect(backend.openId, 'sw:nvidia');
    expect(camera.session!.hasAlpha, isTrue);
  });

  test('reports when no camera exists', () async {
    backend.available = [];
    await camera.start();
    expect(camera.status, CameraStatus.noCameras);
    expect(camera.textureId, isNull);
  });

  test(
    'reports a missing preferred camera instead of switching silently',
    () async {
      await camera.start(preferredKey: 'USB Cam <dev-b>');
      expect(camera.status, CameraStatus.disconnected);
      expect(camera.active!.name, 'USB Cam');
      expect(backend.isOpen, isFalse);
    },
  );

  test('matches by friendly name when the device id changed', () async {
    await camera.start(preferredKey: 'Front Cam <another-usb-port>');
    expect(camera.status, CameraStatus.running);
    expect(backend.openId, 'dev-a');
  });

  test('distinguishes denied, busy and other failures', () async {
    backend.openError = const CameraOpenException(CameraFailure.accessDenied);
    await camera.start();
    expect(camera.status, CameraStatus.permissionDenied);

    backend.openError = const CameraOpenException(CameraFailure.inUse);
    await camera.retry();
    expect(camera.status, CameraStatus.inUse);

    backend.openError = const CameraOpenException(
      CameraFailure.failed,
      'Format not supported',
    );
    await camera.retry();
    expect(camera.status, CameraStatus.unavailable);
    expect(camera.detail, 'Format not supported');
    expect(backend.isOpen, isFalse);
  });

  test('a runtime camera error releases the device and is reported', () async {
    await camera.start();
    backend.onError!(CameraFailure.failed, 'stream stopped');
    await pumpEventQueue();

    expect(camera.status, CameraStatus.unavailable);
    expect(camera.detail, 'stream stopped');
    expect(backend.isOpen, isFalse);
  });

  test('unplugging and replugging the camera recovers automatically', () async {
    await camera.start();
    final devices = backend.available;

    backend.available = [];
    await camera.handleDeviceChange();
    expect(camera.status, CameraStatus.disconnected);
    expect(backend.isOpen, isFalse);

    backend.available = devices;
    await camera.handleDeviceChange();
    expect(camera.status, CameraStatus.running);
  });

  test('stop releases the camera for other applications', () async {
    await camera.start();
    await camera.stop();
    expect(camera.status, CameraStatus.idle);
    expect(backend.isOpen, isFalse);

    // Hot-plug events while stopped only refresh the device list.
    await camera.handleDeviceChange();
    expect(camera.status, CameraStatus.idle);
    expect(backend.isOpen, isFalse);
  });
}
