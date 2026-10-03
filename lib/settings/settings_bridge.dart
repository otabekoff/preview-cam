import '../camera/camera_controller.dart';
import '../camera/camera_device.dart';
import '../services/hotkey_service.dart';
import 'settings_model.dart';

/// Messages exchanged between the overlay and the settings window.
///
/// The two windows run in separate Flutter engines (see
/// `windows/runner/settings_window.h`) and therefore share no Dart objects.
/// Messages are plain maps relayed by the native runner:
///
/// * overlay -> settings: [OverlaySnapshot] (`type: state`) whenever anything
///   the settings UI displays has changed.
/// * settings -> overlay: `hello` (request a snapshot), `patch` (changed
///   setting values), `action` (one-off commands) and `capture` (pause global
///   hotkeys while a new shortcut is being recorded).
///
/// The overlay engine is the single owner of settings and persistence.
abstract final class BridgeMessage {
  static const String state = 'state';
  static const String hello = 'hello';
  static const String patch = 'patch';
  static const String action = 'action';
  static const String capture = 'capture';

  static const String actionMove = 'move';
  static const String actionRetryCamera = 'retryCamera';
  static const String actionShowOverlay = 'showOverlay';
}

/// Everything the settings window needs to render.
class OverlaySnapshot {
  const OverlaySnapshot({
    required this.settings,
    this.cameras = const [],
    this.cameraStatus = CameraStatus.idle,
    this.cameraDetail,
    this.activeCamera,
    this.previewWidth = 0,
    this.previewHeight = 0,
    this.previewFps = 0,
    this.previewFormat = '',
    this.cameraHasAlpha = false,
    this.hotkeyFailures = const {},
    this.overlayVisible = true,
  });

  final AppSettings settings;
  final List<CameraDevice> cameras;
  final CameraStatus cameraStatus;
  final String? cameraDetail;

  /// `CameraDevice.key` of the camera in use.
  final String? activeCamera;
  final int previewWidth;
  final int previewHeight;
  final double previewFps;
  final String previewFormat;

  /// The open camera supplies its own transparency.
  final bool cameraHasAlpha;

  /// Shortcuts that could not be registered (already used elsewhere).
  final Set<HotkeyAction> hotkeyFailures;
  final bool overlayVisible;

  Map<String, Object?> toMessage() => {
    'type': BridgeMessage.state,
    'settings': settings.toJson(),
    'cameras': [for (final camera in cameras) camera.key],
    'cameraStatus': cameraStatus.name,
    'cameraDetail': cameraDetail,
    'activeCamera': activeCamera,
    'previewWidth': previewWidth,
    'previewHeight': previewHeight,
    'previewFps': previewFps,
    'previewFormat': previewFormat,
    'cameraHasAlpha': cameraHasAlpha,
    'hotkeyFailures': [for (final action in hotkeyFailures) action.name],
    'overlayVisible': overlayVisible,
  };

  factory OverlaySnapshot.fromMessage(Map<Object?, Object?> message) {
    final settings = message['settings'];
    final cameras = message['cameras'];
    final failures = message['hotkeyFailures'];
    return OverlaySnapshot(
      settings: settings is Map
          ? AppSettings.fromJson(settings)
          : const AppSettings(),
      cameras: [
        if (cameras is List)
          for (final id in cameras)
            if (id is String) CameraDevice.fromKey(id),
      ],
      cameraStatus: CameraStatus.values.firstWhere(
        (status) => status.name == message['cameraStatus'],
        orElse: () => CameraStatus.idle,
      ),
      cameraDetail: message['cameraDetail'] as String?,
      activeCamera: message['activeCamera'] as String?,
      previewWidth: message['previewWidth'] as int? ?? 0,
      previewHeight: message['previewHeight'] as int? ?? 0,
      previewFps: (message['previewFps'] as num?)?.toDouble() ?? 0,
      previewFormat: message['previewFormat'] as String? ?? '',
      cameraHasAlpha: message['cameraHasAlpha'] as bool? ?? false,
      hotkeyFailures: {
        if (failures is List)
          for (final action in HotkeyAction.values)
            if (failures.contains(action.name)) action,
      },
      overlayVisible: message['overlayVisible'] as bool? ?? true,
    );
  }

  OverlaySnapshot withSettings(AppSettings settings) => OverlaySnapshot(
    settings: settings,
    cameras: cameras,
    cameraStatus: cameraStatus,
    cameraDetail: cameraDetail,
    activeCamera: activeCamera,
    previewWidth: previewWidth,
    previewHeight: previewHeight,
    previewFps: previewFps,
    previewFormat: previewFormat,
    cameraHasAlpha: cameraHasAlpha,
    hotkeyFailures: hotkeyFailures,
    overlayVisible: overlayVisible,
  );
}
