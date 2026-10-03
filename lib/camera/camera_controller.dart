import 'dart:async';

import 'package:flutter/foundation.dart';

import '../settings/settings_model.dart';
import 'camera_backend.dart';
import 'camera_device.dart';

/// What the overlay should currently show in place of / as the camera feed.
enum CameraStatus {
  /// Not started (overlay hidden).
  idle,
  starting,
  running,

  /// Windows reports no camera devices at all.
  noCameras,

  /// The selected camera is not connected right now.
  disconnected,

  /// Windows privacy settings block camera access.
  permissionDenied,

  /// Another application holds the camera and the driver does not share it.
  inUse,

  /// The camera exists but could not be opened or stopped delivering frames.
  unavailable,
}

/// Owns this application's camera preview pipeline.
///
/// Frames never pass through Dart: the native backend writes them into a
/// Flutter texture that [textureId] refers to. The pipeline is private to
/// this process; it does not touch OBS or change any device-level setting,
/// it only opens the device for reading like any other camera application.
///
/// All operations are queued so that rapid start/stop/device-change requests
/// can never overlap, and every failure ends in a descriptive [status]
/// rather than an exception.
class CameraFeedController extends ChangeNotifier {
  CameraFeedController(this._backend) {
    _backend.onError = _onCameraLost;
  }

  final CameraBackend _backend;

  CameraStatus get status => _status;
  CameraStatus _status = CameraStatus.idle;

  /// Cameras found by the most recent enumeration.
  List<CameraDevice> get devices => _devices;
  List<CameraDevice> _devices = const [];

  /// The camera currently opened (or last attempted).
  CameraDevice? get active => _active;
  CameraDevice? _active;

  /// The open camera while [status] is running.
  CameraSession? get session =>
      _status == CameraStatus.running ? _session : null;
  CameraSession? _session;

  int? get textureId => session?.textureId;

  double? get aspectRatio {
    final s = _session;
    return s == null || s.width <= 0 || s.height <= 0
        ? null
        : s.width / s.height;
  }

  /// Extra, system-provided detail about the last failure.
  String? get detail => _detail;
  String? _detail;

  _Request? _request;
  Future<void> _queue = Future<void>.value();
  bool _disposed = false;

  /// Opens the camera stored as [preferredKey] (see [CameraDevice.key]), or
  /// the first available camera when it is `null`.
  Future<void> start({
    String? preferredKey,
    CameraResolution resolution = CameraResolution.high,
    int fps = 0,
  }) {
    _request = _Request(preferredKey, resolution, fps);
    return _enqueue(_open);
  }

  /// Stops the preview and releases the camera for other applications.
  Future<void> stop() {
    _request = null;
    return _enqueue(() async {
      await _release();
      _update(CameraStatus.idle);
    });
  }

  /// Configures the virtual camera output; see [CameraBackend.setOutput].
  Future<bool> setOutput(VirtualCameraOutput output) =>
      _backend.setOutput(output);

  /// Tries again with the parameters of the last [start].
  Future<void> retry() => _enqueue(_open);

  /// Call when a camera was plugged in or removed.
  ///
  /// Re-enumerates devices, reports a vanished active camera as
  /// disconnected, and reopens the wanted camera once it is back.
  Future<void> handleDeviceChange() => _enqueue(() async {
    if (!await _enumerate()) return;
    if (_status == CameraStatus.running) {
      if (!_devices.contains(_active)) {
        await _release();
        _update(CameraStatus.disconnected);
      } else {
        notifyListeners();
      }
    } else if (_request != null) {
      await _open();
    } else {
      notifyListeners();
    }
  });

  Future<void> _enqueue(Future<void> Function() operation) {
    return _queue = _queue.then((_) async {
      if (_disposed) return;
      try {
        await operation();
      } on Object catch (error) {
        // Last line of defence: nothing a camera does may crash the overlay.
        debugPrint('Camera operation failed: $error');
        await _release();
        _update(CameraStatus.unavailable, detail: '$error');
      }
    });
  }

  Future<bool> _enumerate() async {
    try {
      _devices = await _backend.devices();
      return true;
    } on Exception catch (error) {
      _devices = const [];
      await _release();
      _update(CameraStatus.unavailable, detail: '$error');
      return false;
    }
  }

  Future<void> _open() async {
    final request = _request;
    if (request == null) return;
    await _release();
    _update(CameraStatus.starting);

    if (!await _enumerate()) return;
    if (_devices.isEmpty) {
      _active = null;
      _update(CameraStatus.noCameras);
      return;
    }

    final preferred = request.preferredKey == null
        ? null
        : CameraDevice.fromKey(request.preferredKey!);
    final device = _pick(preferred);
    if (device == null) {
      _active = preferred;
      _update(CameraStatus.disconnected);
      return;
    }
    _active = device;

    try {
      _session = await _backend.open(
        device.id,
        height: request.resolution.height,
        fps: request.fps,
      );
      _update(CameraStatus.running);
    } on CameraOpenException catch (error) {
      await _release();
      _update(_statusFor(error.failure), detail: error.message);
    }
  }

  CameraDevice? _pick(CameraDevice? preferred) {
    if (preferred == null) return _devices.first;
    for (final device in _devices) {
      if (device.id == preferred.id) return device;
    }
    // The identifier changes when a USB camera moves to another port; the
    // friendly name is then still a good match.
    for (final device in _devices) {
      if (device.name == preferred.name) return device;
    }
    return null;
  }

  /// The running camera failed or was closed underneath us.
  void _onCameraLost(CameraFailure failure, String description) {
    _enqueue(() async {
      if (_session == null) return;
      await _release();
      await _enumerate();
      _update(
        _devices.contains(_active)
            ? _statusFor(failure)
            : CameraStatus.disconnected,
        detail: description,
      );
    });
  }

  static CameraStatus _statusFor(CameraFailure failure) => switch (failure) {
    CameraFailure.accessDenied => CameraStatus.permissionDenied,
    CameraFailure.inUse => CameraStatus.inUse,
    CameraFailure.notFound => CameraStatus.disconnected,
    CameraFailure.failed => CameraStatus.unavailable,
  };

  Future<void> _release() async {
    final had = _session != null;
    _session = null;
    if (!had) return;
    try {
      await _backend.close();
    } on Object catch (error) {
      debugPrint('Releasing camera failed: $error');
    }
  }

  void _update(CameraStatus status, {String? detail}) {
    _status = status;
    _detail = (detail == null || detail.trim().isEmpty) ? null : detail.trim();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _backend.onError = null;
    unawaited(_release());
    super.dispose();
  }
}

class _Request {
  const _Request(this.preferredKey, this.resolution, this.fps);

  final String? preferredKey;
  final CameraResolution resolution;
  final int fps;
}
