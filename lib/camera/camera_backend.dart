import 'package:flutter/services.dart';

import 'camera_device.dart';

/// A camera that has been opened and is delivering frames to a texture.
class CameraSession {
  const CameraSession({
    required this.textureId,
    required this.width,
    required this.height,
    this.fps = 0,
    this.hasAlpha = false,
    this.format = '',
  });

  /// Flutter texture showing the live picture.
  final int textureId;

  /// Frame size in pixels.
  final int width;
  final int height;
  final double fps;

  /// The camera delivers its own transparency, e.g. NVIDIA Broadcast with
  /// the background removed.
  final bool hasAlpha;

  /// Pixel format received from the device (diagnostic).
  final String format;
}

/// Why a camera could not be opened.
enum CameraFailure { accessDenied, inUse, notFound, failed }

class CameraOpenException implements Exception {
  const CameraOpenException(this.failure, [this.message]);

  final CameraFailure failure;
  final String? message;

  @override
  String toString() => 'CameraOpenException(${failure.name}, $message)';
}

/// Access to the system's cameras. One camera is open at a time.
///
/// The seam for other platforms and for tests; Windows is implemented by
/// [WindowsCameraBackend].
abstract class CameraBackend {
  /// Called when the open camera stops unexpectedly (unplugged, driver error).
  void Function(CameraFailure failure, String message)? onError;

  Future<List<CameraDevice>> devices();

  /// Opens [deviceId] with the mode closest to [height] (0 = largest) and
  /// [fps] (0 = automatic). Throws [CameraOpenException].
  Future<CameraSession> open(String deviceId, {int height = 720, int fps = 0});

  /// Stops capturing and releases the device for other applications.
  Future<void> close();

  /// Configures the virtual camera through which other applications (OBS)
  /// receive the finished picture. Returns `false` if it could not be set up.
  Future<bool> setOutput(VirtualCameraOutput output);
}

/// What the virtual camera publishes: the camera picture cropped to
/// [aspect], optionally mirrored, masked to [shape].
class VirtualCameraOutput {
  const VirtualCameraOutput({
    required this.enabled,
    this.mirror = true,
    this.aspect = 16 / 9,
    this.shape = 0,
    this.radius = 0,
  });

  final bool enabled;
  final bool mirror;

  /// Width / height of the picture.
  final double aspect;

  /// 0 rectangle, 1 rounded rectangle, 2 circle.
  final int shape;

  /// Corner radius as a fraction of the picture's height.
  final double radius;

  @override
  bool operator ==(Object other) =>
      other is VirtualCameraOutput &&
      other.enabled == enabled &&
      other.mirror == mirror &&
      other.aspect == aspect &&
      other.shape == shape &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(enabled, mirror, aspect, shape, radius);
}

/// DirectShow capture implemented in `windows/runner/camera_capture.cpp`.
///
/// Frames are converted and uploaded natively; Dart only receives the
/// texture id.
class WindowsCameraBackend extends CameraBackend {
  WindowsCameraBackend({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('preview/camera') {
    _channel.setMethodCallHandler((call) async {
      final arguments = call.arguments;
      if (call.method == 'onError' && arguments is Map) {
        onError?.call(
          _failure(arguments['code'] as String?),
          arguments['message'] as String? ?? '',
        );
      }
    });
  }

  final MethodChannel _channel;

  @override
  Future<List<CameraDevice>> devices() async {
    final list = await _channel.invokeListMethod<Object?>('list');
    return [
      for (final item in list ?? const <Object?>[])
        if (item is Map)
          CameraDevice(id: item['id'] as String, name: item['name'] as String),
    ];
  }

  @override
  Future<CameraSession> open(
    String deviceId, {
    int height = 720,
    int fps = 0,
  }) async {
    try {
      final result = (await _channel.invokeMapMethod<String, Object?>('open', {
        'id': deviceId,
        'height': height,
        'fps': fps,
      }))!;
      return CameraSession(
        textureId: result['textureId']! as int,
        width: result['width']! as int,
        height: result['height']! as int,
        fps: (result['fps'] as num?)?.toDouble() ?? 0,
        hasAlpha: result['hasAlpha'] as bool? ?? false,
        format: result['format'] as String? ?? '',
      );
    } on PlatformException catch (error) {
      throw CameraOpenException(_failure(error.code), error.message);
    }
  }

  @override
  Future<void> close() => _channel.invokeMethod('close');

  @override
  Future<bool> setOutput(VirtualCameraOutput output) async =>
      await _channel.invokeMethod<bool>('setOutput', {
        'enabled': output.enabled,
        'mirror': output.mirror,
        'aspect': output.aspect,
        'shape': output.shape,
        'radius': output.radius,
      }) ??
      false;

  static CameraFailure _failure(String? code) =>
      CameraFailure.values.firstWhere(
        (failure) => failure.name == code,
        orElse: () => CameraFailure.failed,
      );
}
