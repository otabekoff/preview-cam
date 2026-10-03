import 'dart:async';

import 'package:flutter/foundation.dart';

import '../camera/camera_backend.dart';
import '../camera/camera_controller.dart';
import '../l10n/app_strings.dart';
import '../platform/overlay_platform.dart';
import '../services/hotkey_service.dart';
import '../services/monitor_service.dart';
import '../services/startup_service.dart';
import '../services/tray_service.dart';
import '../settings/settings_bridge.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_model.dart';
import 'overlay_window.dart';

/// Factor applied by the "increase / decrease size" shortcuts.
const double kResizeStep = 1.1;

/// The application's coordinator.
///
/// [SettingsController] is the single source of truth. Every user intent
/// (hover controls, tray menu, global hotkeys, the settings window, native
/// move/resize) ends up as a settings change, and [_apply] pushes whatever
/// changed to the native window, the camera and the other services. Nothing
/// here polls: all work is triggered by an event.
class OverlayController {
  OverlayController({
    required this.platform,
    required this.settings,
    required this.camera,
  }) : window = OverlayWindow(platform, MonitorService(platform)),
       hotkeys = HotkeyService(platform),
       tray = TrayService(platform),
       startup = StartupService(platform);

  final OverlayPlatform platform;
  final SettingsController settings;
  final CameraFeedController camera;
  final OverlayWindow window;
  final HotkeyService hotkeys;
  final TrayService tray;
  final StartupService startup;

  /// Whether the overlay window is shown (as opposed to hidden to the tray).
  final ValueNotifier<bool> visible = ValueNotifier(false);

  /// Short status message shown over the camera, e.g. "Click-through on".
  final ValueNotifier<String?> toast = ValueNotifier(null);

  /// First-launch hint.
  final ValueNotifier<bool> hint = ValueNotifier(false);

  AppSettings? _applied;
  double _nativeAspect = -1;
  VirtualCameraOutput? _output;
  bool _applying = false;
  bool _applyAgain = false;
  bool _hotkeysSuspended = false;
  Timer? _toastTimer;
  Timer? _hintTimer;
  Timer? _deviceDebounce;

  // ---------------------------------------------------------------------
  // Startup
  // ---------------------------------------------------------------------

  Future<void> init() async {
    final events = platform.events;
    events.onBoundsChanged = _storeBounds;
    events.onHotkey = hotkeys.handleNativeHotkey;
    events.onTrayCommand = handleTrayCommand;
    events.onDeviceChange = _onDeviceChange;
    events.onDisplayChange = _onDisplayChange;
    events.onCloseRequested = hide;
    events.onSecondInstance = show;
    events.onSettingsClosed = _onSettingsClosed;
    events.onRelay = _onRelay;
    hotkeys.onAction = handleHotkey;

    await settings.load();
    // The registry, not the settings file, says whether autostart is on.
    final autostart = await startup.isEnabled();
    final initial = _normalize(
      settings.value.copyWith(startWithWindows: autostart),
    );
    settings.value = initial;

    await platform.setMinSize(kMinOverlayHeight);
    await _apply(null, initial);
    _storeBounds(await window.restore(initial));
    await hotkeys.apply(initial.hotkeys);
    _applied = settings.value;

    settings.addListener(_onSettingsChanged);
    camera.addListener(_onCameraChanged);

    await show();

    if (!initial.onboardingShown) {
      hint.value = true;
      _hintTimer = Timer(const Duration(seconds: 15), dismissHint);
      settings.update((s) => s.copyWith(onboardingShown: true));
    }
  }

  // ---------------------------------------------------------------------
  // User actions
  // ---------------------------------------------------------------------

  Future<void> show() async {
    await platform.show();
    if (visible.value) return;
    visible.value = true;
    _startCamera();
    _syncTray();
    _broadcast();
  }

  /// Hides the overlay to the tray and releases the camera.
  Future<void> hide() async {
    await platform.hide();
    if (!visible.value) return;
    visible.value = false;
    unawaited(camera.stop());
    _syncTray();
    _broadcast();
  }

  Future<void> toggleVisible() => visible.value ? hide() : show();

  void toggleMirror() => settings.update((s) => s.copyWith(mirror: !s.mirror));

  void toggleAlwaysOnTop() =>
      settings.update((s) => s.copyWith(alwaysOnTop: !s.alwaysOnTop));

  void toggleClickThrough() =>
      settings.update((s) => s.copyWith(clickThrough: !s.clickThrough));

  void cycleShape() => settings.update((s) {
    const shapes = OverlayShape.values;
    return s.copyWith(shape: shapes[(s.shape.index + 1) % shapes.length]);
  });

  /// Grows or shrinks the overlay by [factor], keeping its proportions.
  void resizeBy(double factor) => settings.update((s) {
    final height = (s.height * factor)
        .clamp(kMinOverlayHeight, kMaxOverlayHeight)
        .toDouble();
    return s.copyWith(height: height, width: s.width * height / s.height);
  });

  Future<void> moveTo(PositionPreset preset) async {
    _storeBounds(await window.moveToPreset(preset));
  }

  Future<void> openSettings() => platform.openSettings();

  /// Begins a native window drag (called on pointer drag start).
  void startDrag() {
    dismissHint();
    unawaited(platform.startDrag());
  }

  void retryCamera() => unawaited(camera.retry());

  void openPrivacySettings() =>
      unawaited(platform.openSystemSettings('ms-settings:privacy-webcam'));

  void dismissHint() {
    _hintTimer?.cancel();
    hint.value = false;
  }

  void showToast(String message) {
    toast.value = message;
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2500), () {
      toast.value = null;
    });
  }

  /// Releases the camera, saves settings and terminates the process.
  Future<void> exit() async {
    try {
      await camera.stop().timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // Exiting anyway; the OS releases the device with the process.
    }
    await settings.flush();
    await platform.quit();
  }

  void handleHotkey(HotkeyAction action) {
    switch (action) {
      case HotkeyAction.toggleOverlay:
        unawaited(toggleVisible());
      case HotkeyAction.toggleClickThrough:
        toggleClickThrough();
      case HotkeyAction.sizeUp:
        resizeBy(kResizeStep);
      case HotkeyAction.sizeDown:
        resizeBy(1 / kResizeStep);
      case HotkeyAction.moveBottomRight:
        unawaited(moveTo(PositionPreset.bottomRight));
      case HotkeyAction.openSettings:
        unawaited(openSettings());
    }
  }

  void handleTrayCommand(String command) {
    switch (command) {
      case 'toggleVisible':
        unawaited(toggleVisible());
      case 'toggleClickThrough':
        toggleClickThrough();
      case 'toggleAlwaysOnTop':
        toggleAlwaysOnTop();
      case 'settings':
        unawaited(openSettings());
      case 'exit':
        unawaited(exit());
      default:
        if (command.startsWith('position:')) {
          final preset = PositionPreset.byName(command.substring(9));
          if (preset != null) unawaited(moveTo(preset));
        }
    }
  }

  // ---------------------------------------------------------------------
  // Settings -> native
  // ---------------------------------------------------------------------

  /// Texts in the language chosen in Settings.
  AppStrings get strings => AppStrings.of(settings.value.language);

  /// Aspect ratio the overlay must have, or `null` when it is free-form.
  double? _aspectFor(AppSettings s) =>
      s.shape.fixedAspect ??
      (s.lockAspect ? camera.aspectRatio ?? s.width / s.height : null);

  /// Derives the width from the height when the aspect ratio is fixed.
  AppSettings _normalize(AppSettings s) {
    final aspect = _aspectFor(s);
    if (aspect == null) return s;
    final width = s.height * aspect;
    return (width - s.width).abs() > 1 ? s.copyWith(width: width) : s;
  }

  void _onSettingsChanged() {
    final normalized = _normalize(settings.value);
    if (normalized != settings.value) {
      settings.value = normalized; // Re-enters this listener.
      return;
    }
    unawaited(_applyPending());
  }

  /// Runs [_apply] until native state has caught up with the settings.
  /// Changes made while an apply is in flight are picked up by another pass
  /// instead of running concurrently.
  Future<void> _applyPending() async {
    if (_applying) {
      _applyAgain = true;
      return;
    }
    _applying = true;
    try {
      do {
        _applyAgain = false;
        final next = settings.value;
        await _apply(_applied, next);
        _applied = next;
      } while (_applyAgain);
    } finally {
      _applying = false;
    }
    _broadcast();
  }

  /// Pushes the differences between [previous] and [next] to the platform.
  /// With [previous] `null` (startup) the whole window state is applied.
  Future<void> _apply(AppSettings? previous, AppSettings next) async {
    bool changed(Object? Function(AppSettings s) field) =>
        previous == null || field(previous) != field(next);

    if (changed((s) => s.shape) || changed((s) => s.cornerRadius)) {
      await platform.setShape(next.shape.native, next.cornerRadius);
    }
    final aspect = _aspectFor(next) ?? 0;
    if (aspect != _nativeAspect) {
      _nativeAspect = aspect;
      await platform.setAspectRatio(aspect);
    }
    if (changed((s) => s.opacity)) await platform.setOpacity(next.opacity);
    if (changed((s) => s.alwaysOnTop)) {
      await platform.setAlwaysOnTop(next.alwaysOnTop);
    }
    if (changed((s) => s.hideFromTaskbar)) {
      await platform.setSkipTaskbar(next.hideFromTaskbar);
    }
    if (changed((s) => s.clickThrough)) {
      await platform.setClickThrough(next.clickThrough);
      if (previous != null) _announceClickThrough(next);
    }
    if (changed((s) => s.clickThrough) ||
        changed((s) => s.alwaysOnTop) ||
        changed((s) => s.language)) {
      _syncTray();
    }
    await _syncOutput(next);
    if (previous == null) return;

    if (changed((s) => s.startWithWindows)) {
      final ok = await startup.setEnabled(next.startWithWindows);
      if (!ok) {
        settings.update(
          (s) => s.copyWith(startWithWindows: previous.startWithWindows),
        );
      }
    }
    if (changed((s) => s.hotkeys) && !_hotkeysSuspended) {
      await hotkeys.apply(next.hotkeys);
    }
    if (visible.value &&
        (changed((s) => s.cameraId) ||
            changed((s) => s.resolution) ||
            changed((s) => s.fps))) {
      _startCamera();
    }

    // Size changes requested through settings, hotkeys or a shape change.
    // (Sizes the user dragged natively already match and are skipped.)
    final bounds = window.bounds;
    if (bounds != null &&
        ((bounds.logicalWidth - next.width).abs() > 1 ||
            (bounds.logicalHeight - next.height).abs() > 1)) {
      _storeBounds(await window.resizeLogical(next.width, next.height));
    }
  }

  /// Tells the virtual camera what the overlay currently looks like, so
  /// other applications receive the same crop, mirroring and shape.
  Future<void> _syncOutput(AppSettings s) async {
    final output = VirtualCameraOutput(
      enabled: s.virtualCamera,
      mirror: s.mirror,
      aspect: s.width / s.height,
      shape: s.shape.native.index,
      radius: s.shape.hasCornerRadius ? s.cornerRadius / s.height : 0,
    );
    if (output == _output) return;
    _output = output;
    final ok = await camera.setOutput(output);
    if (!ok && s.virtualCamera) {
      _output = null;
      showToast(strings.virtualCameraFailed);
      settings.update((s) => s.copyWith(virtualCamera: false));
    }
  }

  void _announceClickThrough(AppSettings s) {
    final t = AppStrings.of(s.language);
    if (!s.clickThrough) {
      showToast(t.clickThroughOff);
      return;
    }
    final hotkey = s.hotkeys[HotkeyAction.toggleClickThrough];
    showToast(
      hotkey == null ? t.clickThroughOnTray : t.clickThroughOn(hotkey.label),
    );
  }

  void _startCamera() {
    final s = settings.value;
    unawaited(
      camera.start(
        preferredKey: s.cameraId,
        resolution: s.resolution,
        fps: s.fps,
      ),
    );
  }

  void _syncTray() {
    final s = settings.value;
    unawaited(
      tray.update(
        visible: visible.value,
        clickThrough: s.clickThrough,
        alwaysOnTop: s.alwaysOnTop,
        labels: AppStrings.of(s.language).trayLabels(),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Native -> settings
  // ---------------------------------------------------------------------

  /// Remembers where the window is (position, size and monitor).
  void _storeBounds(WindowBounds bounds) {
    window.adopt(bounds);
    settings.update(
      (s) => s.copyWith(
        x: bounds.rect.x,
        y: bounds.rect.y,
        width: bounds.logicalWidth,
        height: bounds.logicalHeight,
        monitorId: bounds.monitorId,
      ),
    );
  }

  void _onCameraChanged() {
    // The camera's aspect ratio may have become known or changed.
    final normalized = _normalize(settings.value);
    if (normalized != settings.value) {
      settings.value = normalized;
    } else {
      unawaited(_applyPending());
    }
  }

  void _onDeviceChange() {
    // One hot-plug produces a burst of notifications.
    _deviceDebounce?.cancel();
    _deviceDebounce = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(camera.handleDeviceChange()),
    );
  }

  Future<void> _onDisplayChange() async {
    final s = settings.value;
    final moved = await window.ensureOnScreen(s.width, s.height);
    if (moved != null) _storeBounds(moved);
  }

  // ---------------------------------------------------------------------
  // Settings window
  // ---------------------------------------------------------------------

  OverlaySnapshot get snapshot => OverlaySnapshot(
    settings: settings.value,
    cameras: camera.devices,
    cameraStatus: camera.status,
    cameraDetail: camera.detail,
    activeCamera: camera.active?.key,
    previewWidth: camera.session?.width ?? 0,
    previewHeight: camera.session?.height ?? 0,
    previewFps: camera.session?.fps ?? 0,
    previewFormat: camera.session?.format ?? '',
    cameraHasAlpha: camera.session?.hasAlpha ?? false,
    hotkeyFailures: hotkeys.failures,
    overlayVisible: visible.value,
  );

  /// Sends the current state to the settings window (dropped natively when
  /// that window is not open).
  void _broadcast() => unawaited(platform.relay(snapshot.toMessage()));

  void _onRelay(Map<Object?, Object?> message) {
    switch (message['type']) {
      case BridgeMessage.hello:
        if (!visible.value) unawaited(camera.handleDeviceChange());
        _broadcast();
      case BridgeMessage.patch:
        final values = message['values'];
        if (values is Map) settings.value = settings.value.merge(values);
      case BridgeMessage.capture:
        unawaited(_suspendHotkeys(message['active'] == true));
      case BridgeMessage.action:
        switch (message['name']) {
          case BridgeMessage.actionMove:
            final preset = PositionPreset.byName(message['value'] as String?);
            if (preset != null) unawaited(moveTo(preset));
          case BridgeMessage.actionRetryCamera:
            retryCamera();
          case BridgeMessage.actionShowOverlay:
            unawaited(show());
        }
    }
  }

  /// While a shortcut is recorded in Settings the existing global hotkeys
  /// are released, otherwise Windows would swallow the key presses.
  Future<void> _suspendHotkeys(bool suspend) async {
    if (suspend == _hotkeysSuspended) return;
    _hotkeysSuspended = suspend;
    if (suspend) {
      await hotkeys.suspend();
    } else {
      await hotkeys.apply(settings.value.hotkeys);
      _broadcast();
    }
  }

  void _onSettingsClosed() => unawaited(_suspendHotkeys(false));

  void dispose() {
    _toastTimer?.cancel();
    _hintTimer?.cancel();
    _deviceDebounce?.cancel();
    settings.removeListener(_onSettingsChanged);
    camera.removeListener(_onCameraChanged);
  }
}
