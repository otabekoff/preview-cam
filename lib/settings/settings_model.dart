import 'dart:convert';

import '../l10n/app_strings.dart';
import '../platform/overlay_platform.dart';
import '../services/hotkey_service.dart';

/// Outline of the camera overlay.
enum OverlayShape {
  rectangle,
  rounded,
  circle,

  /// 16:9 rounded rectangle.
  wide,

  /// 4:3 rounded rectangle.
  classic;

  /// Aspect ratio the shape always has, or `null` when it follows the camera
  /// (aspect lock on) or is free (aspect lock off).
  double? get fixedAspect => switch (this) {
    circle => 1,
    wide => 16 / 9,
    classic => 4 / 3,
    rectangle || rounded => null,
  };

  bool get hasCornerRadius => this != rectangle && this != circle;

  NativeShape get native => switch (this) {
    rectangle => NativeShape.rectangle,
    circle => NativeShape.circle,
    rounded || wide || classic => NativeShape.rounded,
  };
}

/// Capture resolutions offered in Settings. The camera driver picks the
/// closest mode it supports.
enum CameraResolution {
  low('240p', 240),
  medium('480p', 480),
  high('720p', 720),
  veryHigh('1080p', 1080),
  max('Maximum', 0);

  const CameraResolution(this.label, this.height);

  final String label;

  /// Frame height to ask the camera for; 0 means its largest mode.
  final int height;
}

/// Smallest and largest overlay height, in logical pixels.
const double kMinOverlayHeight = 90;
const double kMaxOverlayHeight = 1080;

/// All persisted user preferences. Immutable; change with [copyWith].
class AppSettings {
  const AppSettings({
    this.cameraId,
    this.resolution = CameraResolution.high,
    this.fps = 0,
    this.mirror = true,
    this.cameraTransparency = true,
    this.virtualCamera = false,
    this.shape = OverlayShape.rounded,
    this.cornerRadius = 16,
    this.opacity = 1,
    this.lockAspect = true,
    this.width = 320,
    this.height = 180,
    this.x,
    this.y,
    this.monitorId,
    this.alwaysOnTop = true,
    this.clickThrough = false,
    this.hideFromTaskbar = true,
    this.windowCapture = true,
    this.startWithWindows = false,
    this.rememberPosition = true,
    this.hoverControls = true,
    this.onboardingShown = false,
    this.hotkeys = defaultHotkeys,
    this.language = AppLanguage.en,
  });

  /// The selected camera (see `CameraDevice.key`), or `null`
  /// to use the first available camera.
  final String? cameraId;
  final CameraResolution resolution;

  /// Requested frame rate; 0 lets the camera decide.
  final int fps;

  /// Flip this application's preview horizontally (self-view).
  final bool mirror;

  /// Show through the parts of the picture the camera marks as transparent
  /// (cameras with background removal). Off paints them black.
  final bool cameraTransparency;

  /// Offer the finished picture (cropped, mirrored, shaped, transparent
  /// outside the shape) to other applications as the "Preview Cam" camera.
  final bool virtualCamera;
  final OverlayShape shape;

  /// Corner radius in logical pixels for the rounded shapes.
  final double cornerRadius;

  /// Overlay opacity, 0.1 to 1.
  final double opacity;

  /// Keep the camera's aspect ratio for the free-form shapes.
  final bool lockAspect;

  /// Overlay size in logical pixels.
  final double width;
  final double height;

  /// Top-left corner in physical virtual-screen pixels; `null` until placed.
  final int? x;
  final int? y;

  /// Monitor the overlay was last on.
  final String? monitorId;

  final bool alwaysOnTop;
  final bool clickThrough;
  final bool hideFromTaskbar;

  /// While hidden from the taskbar, stay selectable in the window lists of
  /// screen-capture tools such as OBS. Off makes the overlay a tool window,
  /// which also removes it from Alt+Tab but hides it from those lists.
  final bool windowCapture;
  final bool startWithWindows;
  final bool rememberPosition;
  final bool hoverControls;

  /// The first-launch hint has been shown.
  final bool onboardingShown;

  /// Global shortcuts; a `null` value disables that action's shortcut.
  final Map<HotkeyAction, Hotkey?> hotkeys;

  /// Language of the user interface.
  final AppLanguage language;

  static const Object _unset = Object();

  AppSettings copyWith({
    Object? cameraId = _unset,
    CameraResolution? resolution,
    int? fps,
    bool? mirror,
    bool? cameraTransparency,
    bool? virtualCamera,
    OverlayShape? shape,
    double? cornerRadius,
    double? opacity,
    bool? lockAspect,
    double? width,
    double? height,
    Object? x = _unset,
    Object? y = _unset,
    Object? monitorId = _unset,
    bool? alwaysOnTop,
    bool? clickThrough,
    bool? hideFromTaskbar,
    bool? windowCapture,
    bool? startWithWindows,
    bool? rememberPosition,
    bool? hoverControls,
    bool? onboardingShown,
    Map<HotkeyAction, Hotkey?>? hotkeys,
    AppLanguage? language,
  }) => AppSettings(
    cameraId: identical(cameraId, _unset) ? this.cameraId : cameraId as String?,
    resolution: resolution ?? this.resolution,
    fps: fps ?? this.fps,
    mirror: mirror ?? this.mirror,
    cameraTransparency: cameraTransparency ?? this.cameraTransparency,
    virtualCamera: virtualCamera ?? this.virtualCamera,
    shape: shape ?? this.shape,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    opacity: opacity ?? this.opacity,
    lockAspect: lockAspect ?? this.lockAspect,
    width: width ?? this.width,
    height: height ?? this.height,
    x: identical(x, _unset) ? this.x : x as int?,
    y: identical(y, _unset) ? this.y : y as int?,
    monitorId: identical(monitorId, _unset)
        ? this.monitorId
        : monitorId as String?,
    alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
    clickThrough: clickThrough ?? this.clickThrough,
    hideFromTaskbar: hideFromTaskbar ?? this.hideFromTaskbar,
    windowCapture: windowCapture ?? this.windowCapture,
    startWithWindows: startWithWindows ?? this.startWithWindows,
    rememberPosition: rememberPosition ?? this.rememberPosition,
    hoverControls: hoverControls ?? this.hoverControls,
    onboardingShown: onboardingShown ?? this.onboardingShown,
    hotkeys: hotkeys ?? this.hotkeys,
    language: language ?? this.language,
  );

  Map<String, Object?> toJson() => {
    'cameraId': cameraId,
    'resolution': resolution.name,
    'fps': fps,
    'mirror': mirror,
    'cameraTransparency': cameraTransparency,
    'virtualCamera': virtualCamera,
    'shape': shape.name,
    'cornerRadius': cornerRadius,
    'opacity': opacity,
    'lockAspect': lockAspect,
    'width': width,
    'height': height,
    'x': x,
    'y': y,
    'monitorId': monitorId,
    'alwaysOnTop': alwaysOnTop,
    'clickThrough': clickThrough,
    'hideFromTaskbar': hideFromTaskbar,
    'windowCapture': windowCapture,
    'startWithWindows': startWithWindows,
    'rememberPosition': rememberPosition,
    'hoverControls': hoverControls,
    'onboardingShown': onboardingShown,
    'language': language.name,
    'hotkeys': {
      for (final action in HotkeyAction.values)
        action.name: hotkeys[action]?.toJson(),
    },
  };

  /// Tolerant decoding: unknown, missing or malformed values fall back to
  /// their defaults so a damaged or older settings file never blocks startup.
  factory AppSettings.fromJson(Map<Object?, Object?> json) {
    const d = AppSettings();
    T? read<T>(String key) => json[key] is T ? json[key] as T : null;
    double? number(String key) => (read<num>(key))?.toDouble();
    E? named<E extends Enum>(List<E> values, String key) {
      final name = read<String>(key);
      for (final value in values) {
        if (value.name == name) return value;
      }
      return null;
    }

    final storedHotkeys = read<Map<Object?, Object?>>('hotkeys');
    return AppSettings(
      cameraId: read<String>('cameraId'),
      resolution: named(CameraResolution.values, 'resolution') ?? d.resolution,
      fps: read<int>('fps') ?? d.fps,
      mirror: read<bool>('mirror') ?? d.mirror,
      cameraTransparency:
          read<bool>('cameraTransparency') ?? d.cameraTransparency,
      virtualCamera: read<bool>('virtualCamera') ?? d.virtualCamera,
      shape: named(OverlayShape.values, 'shape') ?? d.shape,
      cornerRadius: (number('cornerRadius') ?? d.cornerRadius)
          .clamp(0, 200)
          .toDouble(),
      opacity: (number('opacity') ?? d.opacity).clamp(0.1, 1).toDouble(),
      lockAspect: read<bool>('lockAspect') ?? d.lockAspect,
      width: (number('width') ?? d.width).clamp(40, 4000).toDouble(),
      height: (number('height') ?? d.height)
          .clamp(kMinOverlayHeight, kMaxOverlayHeight)
          .toDouble(),
      x: read<int>('x'),
      y: read<int>('y'),
      monitorId: read<String>('monitorId'),
      alwaysOnTop: read<bool>('alwaysOnTop') ?? d.alwaysOnTop,
      clickThrough: read<bool>('clickThrough') ?? d.clickThrough,
      hideFromTaskbar: read<bool>('hideFromTaskbar') ?? d.hideFromTaskbar,
      windowCapture: read<bool>('windowCapture') ?? d.windowCapture,
      startWithWindows: read<bool>('startWithWindows') ?? d.startWithWindows,
      rememberPosition: read<bool>('rememberPosition') ?? d.rememberPosition,
      hoverControls: read<bool>('hoverControls') ?? d.hoverControls,
      onboardingShown: read<bool>('onboardingShown') ?? d.onboardingShown,
      language: named(AppLanguage.values, 'language') ?? d.language,
      hotkeys: {
        for (final action in HotkeyAction.values)
          action:
              storedHotkeys != null && storedHotkeys.containsKey(action.name)
              ? Hotkey.fromJson(storedHotkeys[action.name])
              : defaultHotkeys[action],
      },
    );
  }

  /// This settings object with the entries of [patch] (a partial [toJson]
  /// map) applied on top.
  AppSettings merge(Map<Object?, Object?> patch) =>
      AppSettings.fromJson({...toJson(), ...patch});

  String encode() => jsonEncode(toJson());

  static AppSettings decode(String? source) {
    if (source == null || source.isEmpty) return const AppSettings();
    try {
      final json = jsonDecode(source);
      return json is Map ? AppSettings.fromJson(json) : const AppSettings();
    } on FormatException {
      return const AppSettings();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}
