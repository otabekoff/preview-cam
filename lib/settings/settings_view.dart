import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../camera/camera_controller.dart';
import '../camera/camera_device.dart';
import '../l10n/app_strings.dart';
import '../services/hotkey_service.dart';
import '../services/monitor_service.dart';
import 'settings_bridge.dart';
import 'settings_model.dart';

/// The settings window's connection to the overlay.
///
/// Holds the latest [OverlaySnapshot] and sends the user's changes back. It
/// applies each change locally first so controls respond immediately; the
/// overlay's next snapshot then confirms (or corrects) it.
class SettingsLink extends ChangeNotifier {
  SettingsLink({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('preview/native') {
    _channel.setMethodCallHandler((call) async {
      final message = call.arguments;
      if (call.method == 'onRelay' &&
          message is Map &&
          message['type'] == BridgeMessage.state) {
        _snapshot = OverlaySnapshot.fromMessage(message);
        notifyListeners();
      }
    });
    _send({'type': BridgeMessage.hello});
  }

  final MethodChannel _channel;

  /// `null` until the overlay has answered.
  OverlaySnapshot? get snapshot => _snapshot;
  OverlaySnapshot? _snapshot;

  void _send(Map<String, Object?> message) {
    _channel.invokeMethod<void>('relay', message);
  }

  /// Changes settings; [values] is a partial `AppSettings.toJson()` map.
  void patch(Map<String, Object?> values) {
    final current = _snapshot;
    if (current != null) {
      _snapshot = current.withSettings(current.settings.merge(values));
      notifyListeners();
    }
    _send({'type': BridgeMessage.patch, 'values': values});
  }

  void action(String name, [Object? value]) =>
      _send({'type': BridgeMessage.action, 'name': name, 'value': value});

  /// Pauses global hotkeys while a shortcut is being recorded.
  void setCapturing(bool active) =>
      _send({'type': BridgeMessage.capture, 'active': active});

  void close() => _channel.invokeMethod<void>('close');

  /// Opens a web page in the default browser.
  void openUrl(String url) => _channel.invokeMethod<void>('openUrl', url);
}

/// Root widget of the settings window.
class SettingsApp extends StatelessWidget {
  const SettingsApp({super.key, required this.link});

  final SettingsLink link;

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF8AB4F8),
        brightness: Brightness.dark,
      ),
      visualDensity: VisualDensity.compact,
    );
    return MaterialApp(
      title: 'Preview Cam Settings',
      debugShowCheckedModeBanner: false,
      theme: base.copyWith(
        // Dropdowns use titleMedium; match the rest of this compact window.
        textTheme: base.textTheme.copyWith(
          titleMedium: base.textTheme.bodyMedium,
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 32),
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
      ),
      home: SettingsView(link: link),
    );
  }
}

class SettingsView extends StatelessWidget {
  const SettingsView({super.key, required this.link});

  final SettingsLink link;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: link,
        builder: (context, _) {
          final snapshot = link.snapshot;
          if (snapshot == null) {
            return Center(
              child: Text(AppStrings.of(AppLanguage.en).connecting),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              ..._camera(context, snapshot),
              ..._appearance(snapshot),
              ..._behavior(snapshot),
              ..._hotkeys(context, snapshot),
              ..._about(context, snapshot),
            ],
          );
        },
      ),
    );
  }

  // --- Camera ------------------------------------------------------------

  List<Widget> _camera(BuildContext context, OverlaySnapshot snapshot) {
    final s = snapshot.settings;
    final t = AppStrings.of(s.language);
    // The stored selection may predate a change of the device's identifier;
    // resolve it to a listed camera by id, then by name.
    final wanted = s.cameraId == null
        ? null
        : CameraDevice.fromKey(s.cameraId!);
    CameraDevice? listed;
    if (wanted != null) {
      for (final camera in snapshot.cameras) {
        if (camera.id == wanted.id) listed = camera;
      }
      for (final camera in snapshot.cameras) {
        if (listed == null && camera.name == wanted.name) listed = camera;
      }
    }
    return [
      _Header(t.camera),
      _Row(
        label: t.device,
        child: DropdownButton<String?>(
          isExpanded: true,
          value: listed?.key ?? s.cameraId,
          items: [
            DropdownMenuItem(value: null, child: Text(t.automaticDevice)),
            for (final camera in snapshot.cameras)
              DropdownMenuItem(
                value: camera.key,
                child: Text(camera.name, overflow: TextOverflow.ellipsis),
              ),
            if (wanted != null && listed == null)
              DropdownMenuItem(
                value: s.cameraId,
                child: Text(
                  t.notConnected(wanted.name),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (id) => link.patch({'cameraId': id}),
        ),
      ),
      _CameraStatusLine(snapshot: snapshot, link: link),
      _Row(
        label: t.resolution,
        child: DropdownButton<CameraResolution>(
          isExpanded: true,
          value: s.resolution,
          items: [
            for (final resolution in CameraResolution.values)
              DropdownMenuItem(
                value: resolution,
                child: Text(t.resolutionName(resolution)),
              ),
          ],
          onChanged: (value) => link.patch({'resolution': value!.name}),
        ),
      ),
      _Row(
        label: t.frameRate,
        child: DropdownButton<int>(
          isExpanded: true,
          value: const [0, 15, 24, 30, 60].contains(s.fps) ? s.fps : 0,
          items: [
            DropdownMenuItem(value: 0, child: Text(t.automatic)),
            for (final rate in const [15, 24, 30, 60])
              DropdownMenuItem(value: rate, child: Text(t.fps(rate))),
          ],
          onChanged: (value) => link.patch({'fps': value}),
        ),
      ),
      _Toggle(
        label: t.mirrorPreview,
        value: s.mirror,
        onChanged: (value) => link.patch({'mirror': value}),
      ),
      _Toggle(
        label: t.transparentBackground,
        value: s.cameraTransparency,
        onChanged: (value) => link.patch({'cameraTransparency': value}),
      ),
      _Toggle(
        label: t.virtualCamera,
        value: s.virtualCamera,
        onChanged: (value) => link.patch({'virtualCamera': value}),
      ),
      if (s.virtualCamera)
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            t.virtualCameraHint,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
    ];
  }

  // --- Appearance --------------------------------------------------------

  List<Widget> _appearance(OverlaySnapshot snapshot) {
    final s = snapshot.settings;
    final t = AppStrings.of(s.language);
    return [
      _Header(t.sectionAppearance),
      _Row(
        label: t.shape,
        child: DropdownButton<OverlayShape>(
          isExpanded: true,
          value: s.shape,
          items: [
            for (final shape in OverlayShape.values)
              DropdownMenuItem(value: shape, child: Text(t.shapeName(shape))),
          ],
          onChanged: (value) => link.patch({'shape': value!.name}),
        ),
      ),
      _SliderRow(
        label: t.cornerRadius,
        value: s.cornerRadius,
        min: 0,
        max: 64,
        enabled: s.shape.hasCornerRadius,
        format: (value) => '${value.round()} px',
        onChanged: (value) =>
            link.patch({'cornerRadius': value.roundToDouble()}),
      ),
      _SliderRow(
        label: t.opacity,
        value: s.opacity,
        min: 0.2,
        max: 1,
        format: (value) => '${(value * 100).round()}%',
        onChanged: (value) => link.patch({'opacity': value}),
      ),
      _SliderRow(
        label: t.overlaySize,
        value: s.height.clamp(kMinOverlayHeight, 720).toDouble(),
        min: kMinOverlayHeight,
        max: 720,
        format: (_) => '${s.width.round()} × ${s.height.round()}',
        onChanged: (value) => link.patch({
          'height': value.roundToDouble(),
          // Free-form overlays scale proportionally; for fixed aspect
          // ratios the overlay recomputes the width itself.
          'width': s.width * value.roundToDouble() / s.height,
        }),
      ),
      _Toggle(
        label: t.lockAspect,
        value: s.shape.fixedAspect != null || s.lockAspect,
        onChanged: s.shape.fixedAspect != null
            ? null
            : (value) => link.patch({'lockAspect': value}),
      ),
      _Row(
        label: t.position,
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in PositionPreset.values)
              OutlinedButton(
                onPressed: () =>
                    link.action(BridgeMessage.actionMove, preset.name),
                child: Text(t.presetName(preset)),
              ),
          ],
        ),
      ),
    ];
  }

  // --- Behavior ----------------------------------------------------------

  List<Widget> _behavior(OverlaySnapshot snapshot) {
    final s = snapshot.settings;
    final t = AppStrings.of(s.language);
    return [
      _Header(t.sectionBehavior),
      _Row(
        label: t.language,
        child: DropdownButton<AppLanguage>(
          isExpanded: true,
          value: s.language,
          items: [
            for (final language in AppLanguage.values)
              DropdownMenuItem(
                value: language,
                child: Text(language.nativeName),
              ),
          ],
          onChanged: (value) => link.patch({'language': value!.name}),
        ),
      ),
      if (!snapshot.overlayVisible)
        _Notice(
          text: t.overlayHidden,
          actionLabel: t.show,
          onAction: () => link.action(BridgeMessage.actionShowOverlay),
        ),
      _Toggle(
        label: t.alwaysOnTop,
        value: s.alwaysOnTop,
        onChanged: (value) => link.patch({'alwaysOnTop': value}),
      ),
      _Toggle(
        label: t.clickThrough,
        value: s.clickThrough,
        onChanged: (value) => link.patch({'clickThrough': value}),
      ),
      _Toggle(
        label: t.hideFromTaskbar,
        value: s.hideFromTaskbar,
        onChanged: (value) => link.patch({'hideFromTaskbar': value}),
      ),
      _Toggle(
        label: t.windowCapture,
        value: s.windowCapture,
        onChanged: s.hideFromTaskbar
            ? (value) => link.patch({'windowCapture': value})
            : null,
      ),
      _Toggle(
        label: t.startWithWindows,
        value: s.startWithWindows,
        onChanged: (value) => link.patch({'startWithWindows': value}),
      ),
      _Toggle(
        label: t.rememberPosition,
        value: s.rememberPosition,
        onChanged: (value) => link.patch({'rememberPosition': value}),
      ),
      _Toggle(
        label: t.hoverControls,
        value: s.hoverControls,
        onChanged: (value) => link.patch({'hoverControls': value}),
      ),
    ];
  }

  // --- Hotkeys -----------------------------------------------------------

  List<Widget> _hotkeys(BuildContext context, OverlaySnapshot snapshot) {
    final s = snapshot.settings;
    final t = AppStrings.of(s.language);

    void setHotkey(HotkeyAction action, Hotkey? hotkey) {
      link.patch({
        'hotkeys': {
          for (final entry in HotkeyAction.values)
            entry.name: (entry == action ? hotkey : s.hotkeys[entry])?.toJson(),
        },
      });
    }

    return [
      _Header(t.sectionHotkeys),
      for (final action in HotkeyAction.values)
        _HotkeyRow(
          key: ValueKey(action),
          strings: t,
          action: action,
          hotkey: s.hotkeys[action],
          failed: snapshot.hotkeyFailures.contains(action),
          onCapturing: link.setCapturing,
          onChanged: (hotkey) => setHotkey(action, hotkey),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => link.patch({
            'hotkeys': {
              for (final action in HotkeyAction.values)
                action.name: defaultHotkeys[action]?.toJson(),
            },
          }),
          child: Text(t.resetHotkeys),
        ),
      ),
    ];
  }
}

/// Where the footer links lead.
const String kAuthorUrl = 'https://github.com/otabekoff';
const String kDonateUrl = 'https://taps.uz/uzhandy';

extension on SettingsView {
  /// Credits and donation link at the bottom of the window.
  List<Widget> _about(BuildContext context, OverlaySnapshot snapshot) {
    final t = AppStrings.of(snapshot.settings.language);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return [
      const Divider(height: 32),
      Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(t.developedBy, style: TextStyle(fontSize: 12, color: muted)),
          TextButton(
            onPressed: () => link.openUrl(kAuthorUrl),
            child: const Text('Otabek Sadiridinov · github.com/otabekoff'),
          ),
        ],
      ),
      Center(
        child: TextButton.icon(
          onPressed: () => link.openUrl(kDonateUrl),
          icon: const Icon(Icons.favorite_border, size: 16),
          label: Text('${t.supportProject} · taps.uz/uzhandy'),
        ),
      ),
    ];
  }
}

class _CameraStatusLine extends StatelessWidget {
  const _CameraStatusLine({required this.snapshot, required this.link});

  final OverlaySnapshot snapshot;
  final SettingsLink link;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final t = AppStrings.of(snapshot.settings.language);
    final active = snapshot.activeCamera;
    final label = active == null ? t.camera : CameraDevice.nameOf(active);
    final fps = snapshot.previewFps > 0
        ? ' @ ${t.fps(snapshot.previewFps.round())}'
        : '';
    final alpha = snapshot.cameraHasAlpha ? ' · ${t.withTransparency}' : '';
    final (String text, bool problem) = switch (snapshot.cameraStatus) {
      CameraStatus.idle => (t.statusIdle, false),
      CameraStatus.starting => (t.statusStarting(label), false),
      CameraStatus.running => (
        '${snapshot.previewWidth} × ${snapshot.previewHeight}$fps'
            ' · ${snapshot.previewFormat}$alpha',
        false,
      ),
      CameraStatus.noCameras => (t.statusNoCameras, true),
      CameraStatus.disconnected => (t.statusDisconnected(label), true),
      CameraStatus.permissionDenied => (t.statusPermission, true),
      CameraStatus.inUse => (t.statusInUse(label), true),
      CameraStatus.unavailable => (
        '${t.statusUnavailable(label)}'
            '${snapshot.cameraDetail == null ? '.' : ': ${snapshot.cameraDetail}.'}',
        true,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(left: 132, bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: problem ? colors.error : colors.onSurfaceVariant,
              ),
            ),
          ),
          if (problem)
            TextButton(
              onPressed: () => link.action(BridgeMessage.actionRetryCamera),
              child: Text(t.retry),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 1,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

/// A label on the left with a control filling the rest of the row.
class _Row extends StatelessWidget {
  const _Row({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 132, child: Text(label)),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.label, required this.value, this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Transform.scale(
          scale: 0.8,
          alignment: Alignment.centerRight,
          child: Switch(value: value, onChanged: onChanged),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
          ),
        ),
        TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}

/// A labelled slider that keeps its own value while being dragged, so
/// snapshots arriving from the overlay mid-drag cannot make the thumb jump.
class _SliderRow extends StatefulWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double value) format;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final value = (_dragValue ?? widget.value)
        .clamp(widget.min, widget.max)
        .toDouble();
    return _Row(
      label: widget.label,
      child: Row(
        children: [
          Expanded(
            child: Slider(
              value: value,
              min: widget.min,
              max: widget.max,
              onChangeStart: widget.enabled
                  ? (value) => setState(() => _dragValue = value)
                  : null,
              onChanged: widget.enabled
                  ? (value) {
                      setState(() => _dragValue = value);
                      widget.onChanged(value);
                    }
                  : null,
              onChangeEnd: widget.enabled
                  ? (_) => setState(() => _dragValue = null)
                  : null,
            ),
          ),
          SizedBox(
            width: 76,
            child: Text(
              widget.format(value),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// One shortcut: shows the current combination and records a new one.
class _HotkeyRow extends StatefulWidget {
  const _HotkeyRow({
    super.key,
    required this.strings,
    required this.action,
    required this.hotkey,
    required this.failed,
    required this.onCapturing,
    required this.onChanged,
  });

  final AppStrings strings;
  final HotkeyAction action;
  final Hotkey? hotkey;

  /// Windows refused the combination (another application owns it).
  final bool failed;
  final ValueChanged<bool> onCapturing;
  final ValueChanged<Hotkey?> onChanged;

  @override
  State<_HotkeyRow> createState() => _HotkeyRowState();
}

class _HotkeyRowState extends State<_HotkeyRow> {
  final FocusNode _focus = FocusNode();
  bool _recording = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _setRecording(false);
    });
  }

  @override
  void dispose() {
    if (_recording) widget.onCapturing(false);
    _focus.dispose();
    super.dispose();
  }

  void _setRecording(bool recording) {
    if (_recording == recording) return;
    setState(() => _recording = recording);
    widget.onCapturing(recording);
    if (recording) {
      _focus.requestFocus();
    } else {
      _focus.unfocus();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_recording) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.handled;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _setRecording(false);
      return KeyEventResult.handled;
    }
    final vk = vkForPhysicalKey(event.physicalKey);
    if (vk == null) return KeyEventResult.handled; // A modifier on its own.
    final keyboard = HardwareKeyboard.instance;
    final modifiers =
        (keyboard.isControlPressed ? Hotkey.control : 0) |
        (keyboard.isAltPressed ? Hotkey.alt : 0) |
        (keyboard.isShiftPressed ? Hotkey.shift : 0) |
        (keyboard.isMetaPressed ? Hotkey.win : 0);
    final functionKey = vk >= 0x70 && vk <= 0x87;
    // A plain letter as a global shortcut would make that key unusable in
    // every application, so a modifier is required (function keys excepted).
    if (modifiers == 0 && !functionKey) return KeyEventResult.handled;
    widget.onChanged(Hotkey(modifiers, vk));
    _setRecording(false);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hotkey = widget.hotkey;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(widget.strings.hotkeyActionName(widget.action))),
          if (widget.failed && !_recording)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Tooltip(
                message: widget.strings.hotkeyInUse,
                child: Icon(Icons.warning_amber, size: 18, color: colors.error),
              ),
            ),
          Focus(
            focusNode: _focus,
            onKeyEvent: _onKey,
            child: SizedBox(
              width: 150,
              child: OutlinedButton(
                onPressed: () => _setRecording(!_recording),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _recording ? colors.tertiary : null,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  _recording
                      ? widget.strings.pressKeys
                      : hotkey?.label ?? widget.strings.none,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: widget.strings.removeShortcut,
            iconSize: 16,
            onPressed: hotkey == null ? null : () => widget.onChanged(null),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}
