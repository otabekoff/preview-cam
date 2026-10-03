import 'dart:async';

import 'package:preview/camera/camera_backend.dart';
import 'package:preview/camera/camera_device.dart';
import 'package:preview/platform/overlay_platform.dart';
import 'package:preview/services/monitor_service.dart';
import 'package:preview/services/preferences_service.dart';
import 'package:preview/settings/settings_model.dart';

/// A 1920x1080 primary monitor at 100% with a 48px taskbar at the bottom.
const MonitorInfo primary = MonitorInfo(
  id: r'\\.\DISPLAY1',
  bounds: PxRect(0, 0, 1920, 1080),
  workArea: PxRect(0, 0, 1920, 1032),
  dpi: 96,
  primary: true,
);

/// A 2560x1600 monitor at 150%, placed to the left of [primary].
const MonitorInfo secondary = MonitorInfo(
  id: r'\\.\DISPLAY2',
  bounds: PxRect(-2560, 0, 2560, 1600),
  workArea: PxRect(-2560, 0, 2560, 1528),
  dpi: 144,
);

class MemoryStore implements SettingsStore {
  MemoryStore([this.saved]);

  AppSettings? saved;
  int saves = 0;

  @override
  Future<AppSettings> load() async => saved ?? const AppSettings();

  @override
  Future<void> save(AppSettings settings) async {
    saved = settings;
    saves++;
  }
}

/// Records every call and simulates window geometry.
class FakeOverlayPlatform implements OverlayPlatform {
  FakeOverlayPlatform({List<MonitorInfo>? monitors})
    : monitors = monitors ?? [primary];

  List<MonitorInfo> monitors;
  PxRect rect = const PxRect(0, 0, 320, 180);
  final List<String> calls = [];
  final List<Map<String, Object?>> relayed = [];
  final Map<int, (int, int)> hotkeys = {};

  /// Hotkey ids that the "OS" refuses to register.
  Set<int> takenHotkeys = {};
  bool startup = false;
  bool shown = false;

  @override
  final OverlayPlatformEvents events = OverlayPlatformEvents();

  WindowBounds get bounds {
    final monitor = monitorContaining(rect, monitors);
    return WindowBounds(rect: rect, monitorId: monitor.id, dpi: monitor.dpi);
  }

  @override
  Future<List<MonitorInfo>> getMonitors() async => monitors;

  @override
  Future<WindowBounds> getBounds() async => bounds;

  @override
  Future<WindowBounds> setBounds(PxRect rect) async {
    this.rect = rect;
    calls.add('setBounds $rect');
    return bounds;
  }

  @override
  Future<void> show({bool activate = false}) async {
    shown = true;
    calls.add('show');
  }

  @override
  Future<void> hide() async {
    shown = false;
    calls.add('hide');
  }

  @override
  Future<void> setAlwaysOnTop(bool value) async =>
      calls.add('setAlwaysOnTop $value');

  @override
  Future<void> setClickThrough(bool value) async =>
      calls.add('setClickThrough $value');

  @override
  Future<void> setSkipTaskbar(bool value, {bool capturable = true}) async =>
      calls.add('setSkipTaskbar $value capturable=$capturable');

  @override
  Future<void> setOpacity(double value) async => calls.add('setOpacity $value');

  @override
  Future<void> setShape(NativeShape shape, double radius) async =>
      calls.add('setShape ${shape.name} $radius');

  @override
  Future<void> setAspectRatio(double ratio) async =>
      calls.add('setAspectRatio ${ratio.toStringAsFixed(3)}');

  @override
  Future<void> setMinSize(double logical) async {}

  @override
  Future<void> startDrag() async => calls.add('startDrag');

  @override
  Future<bool> registerHotkey({
    required int id,
    required int modifiers,
    required int vk,
    bool repeat = false,
  }) async {
    if (takenHotkeys.contains(id)) return false;
    hotkeys[id] = (modifiers, vk);
    return true;
  }

  @override
  Future<void> unregisterAllHotkeys() async => hotkeys.clear();

  @override
  Future<void> setTrayState({
    required bool visible,
    required bool clickThrough,
    required bool alwaysOnTop,
    required Map<String, String> labels,
  }) async {
    trayLabels = labels;
    calls.add('tray $visible $clickThrough $alwaysOnTop');
  }

  Map<String, String> trayLabels = const {};

  @override
  Future<bool> getStartup() async => startup;

  @override
  Future<bool> setStartup(bool enabled) async {
    startup = enabled;
    return true;
  }

  @override
  Future<void> openSettings() async => calls.add('openSettings');

  @override
  Future<void> relay(Map<String, Object?> message) async =>
      relayed.add(message);

  @override
  Future<void> openSystemSettings(String uri) async =>
      calls.add('openSystemSettings $uri');

  @override
  Future<void> quit() async => calls.add('quit');
}

/// A camera backend that never touches hardware.
class FakeCameraBackend extends CameraBackend {
  List<CameraDevice> available = const [
    CameraDevice(id: 'dev-a', name: 'Front Cam'),
  ];
  CameraOpenException? openError;
  int previewWidth = 1280;
  int previewHeight = 720;
  bool hasAlpha = false;

  /// Device currently open, if any.
  String? openId;
  int? requestedHeight;
  int? requestedFps;

  bool get isOpen => openId != null;

  @override
  Future<List<CameraDevice>> devices() async => available;

  @override
  Future<CameraSession> open(
    String deviceId, {
    int height = 720,
    int fps = 0,
  }) async {
    final error = openError;
    if (error != null) throw error;
    openId = deviceId;
    requestedHeight = height;
    requestedFps = fps;
    return CameraSession(
      textureId: 7,
      width: previewWidth,
      height: previewHeight,
      fps: 30,
      hasAlpha: hasAlpha,
      format: hasAlpha ? 'ARGB32' : 'NV12',
    );
  }

  @override
  Future<void> close() async => openId = null;

  /// Every virtual-camera configuration received, newest last.
  final List<VirtualCameraOutput> outputs = [];
  bool outputAvailable = true;

  @override
  Future<bool> setOutput(VirtualCameraOutput output) async {
    outputs.add(output);
    return outputAvailable || !output.enabled;
  }
}
