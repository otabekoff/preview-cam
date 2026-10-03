import 'package:flutter/services.dart';

import '../platform/overlay_platform.dart';

/// Actions that can be bound to a global keyboard shortcut.
enum HotkeyAction {
  toggleOverlay,
  toggleClickThrough,
  sizeUp,
  sizeDown,
  moveBottomRight,
  openSettings;

  /// Identifier passed to `RegisterHotKey` (must be non-zero).
  int get nativeId => index + 1;

  /// Holding the keys repeats the action instead of firing once.
  bool get repeats => this == sizeUp || this == sizeDown;

  static HotkeyAction? fromNativeId(int id) =>
      id >= 1 && id <= values.length ? values[id - 1] : null;
}

/// A key combination: Win32 `MOD_*` flags plus a virtual-key code.
class Hotkey {
  const Hotkey(this.modifiers, this.vk);

  static const int alt = 0x1; // MOD_ALT
  static const int control = 0x2; // MOD_CONTROL
  static const int shift = 0x4; // MOD_SHIFT
  static const int win = 0x8; // MOD_WIN

  final int modifiers;
  final int vk;

  /// Human readable form, e.g. `Ctrl + Alt + C`.
  String get label => [
    if (modifiers & control != 0) 'Ctrl',
    if (modifiers & alt != 0) 'Alt',
    if (modifiers & shift != 0) 'Shift',
    if (modifiers & win != 0) 'Win',
    vkLabel(vk),
  ].join(' + ');

  Map<String, Object?> toJson() => {'modifiers': modifiers, 'vk': vk};

  static Hotkey? fromJson(Object? json) {
    if (json is! Map) return null;
    final modifiers = json['modifiers'];
    final vk = json['vk'];
    if (modifiers is! int || vk is! int || vk <= 0) return null;
    return Hotkey(modifiers, vk);
  }

  @override
  bool operator ==(Object other) =>
      other is Hotkey && other.modifiers == modifiers && other.vk == vk;

  @override
  int get hashCode => Object.hash(modifiers, vk);
}

/// Shortcuts used until the user changes them.
const Map<HotkeyAction, Hotkey?> defaultHotkeys = {
  HotkeyAction.toggleOverlay: Hotkey(Hotkey.control | Hotkey.alt, 0x56), // V
  HotkeyAction.toggleClickThrough: Hotkey(
    Hotkey.control | Hotkey.alt,
    0x43,
  ), // C
  HotkeyAction.sizeUp: Hotkey(Hotkey.control | Hotkey.alt, 0xBB), // =
  HotkeyAction.sizeDown: Hotkey(Hotkey.control | Hotkey.alt, 0xBD), // -
  HotkeyAction.moveBottomRight: Hotkey(Hotkey.control | Hotkey.alt, 0x42), // B
  HotkeyAction.openSettings: Hotkey(Hotkey.control | Hotkey.alt, 0x53), // S
};

/// Display name of a Windows virtual-key code.
String vkLabel(int vk) {
  if (vk >= 0x30 && vk <= 0x39 || vk >= 0x41 && vk <= 0x5A) {
    return String.fromCharCode(vk);
  }
  if (vk >= 0x70 && vk <= 0x87) return 'F${vk - 0x6F}';
  if (vk >= 0x60 && vk <= 0x69) return 'Num ${vk - 0x60}';
  return _vkNames[vk] ?? 'Key $vk';
}

const Map<int, String> _vkNames = {
  0x20: 'Space',
  0x21: 'Page Up',
  0x22: 'Page Down',
  0x23: 'End',
  0x24: 'Home',
  0x25: 'Left',
  0x26: 'Up',
  0x27: 'Right',
  0x28: 'Down',
  0x2D: 'Insert',
  0x2E: 'Delete',
  0x6A: 'Num *',
  0x6B: 'Num +',
  0x6D: 'Num -',
  0x6F: 'Num /',
  0xBA: ';',
  0xBB: '=',
  0xBC: ',',
  0xBD: '-',
  0xBE: '.',
  0xBF: '/',
  0xC0: '`',
  0xDB: '[',
  0xDC: r'\',
  0xDD: ']',
  0xDE: "'",
};

/// Maps a physical key to its Windows virtual-key code, or `null` for keys
/// that cannot be used as the main key of a shortcut (modifiers, Esc, ...).
///
/// Physical keys are used so recording works the same on any keyboard layout.
int? vkForPhysicalKey(PhysicalKeyboardKey key) {
  final usage = key.usbHidUsage & 0xFFFF;
  if (key.usbHidUsage >> 16 != 0x7) return null;
  if (usage >= 0x04 && usage <= 0x1D) return 0x41 + (usage - 0x04); // A-Z
  if (usage >= 0x1E && usage <= 0x26) return 0x31 + (usage - 0x1E); // 1-9
  if (usage == 0x27) return 0x30; // 0
  if (usage >= 0x3A && usage <= 0x45) return 0x70 + (usage - 0x3A); // F1-F12
  if (usage >= 0x59 && usage <= 0x61) return 0x61 + (usage - 0x59); // Num 1-9
  return _vkForUsage[usage];
}

const Map<int, int> _vkForUsage = {
  0x2C: 0x20, // Space
  0x2D: 0xBD, // -
  0x2E: 0xBB, // =
  0x2F: 0xDB, // [
  0x30: 0xDD, // ]
  0x31: 0xDC, // \
  0x33: 0xBA, // ;
  0x34: 0xDE, // '
  0x35: 0xC0, // `
  0x36: 0xBC, // ,
  0x37: 0xBE, // .
  0x38: 0xBF, // /
  0x49: 0x2D, // Insert
  0x4A: 0x24, // Home
  0x4B: 0x21, // Page Up
  0x4C: 0x2E, // Delete
  0x4D: 0x23, // End
  0x4E: 0x22, // Page Down
  0x4F: 0x27, // Right
  0x50: 0x25, // Left
  0x51: 0x28, // Down
  0x52: 0x26, // Up
  0x54: 0x6F, // Num /
  0x55: 0x6A, // Num *
  0x56: 0x6D, // Num -
  0x57: 0x6B, // Num +
  0x62: 0x60, // Num 0
};

/// Registers system-wide shortcuts and dispatches them to [onAction].
///
/// Registration is done natively with `RegisterHotKey`, so shortcuts fire
/// regardless of which application has keyboard focus.
class HotkeyService {
  HotkeyService(this._platform);

  final OverlayPlatform _platform;

  void Function(HotkeyAction action)? onAction;

  /// Actions whose shortcut could not be registered, typically because
  /// another application already owns the combination.
  Set<HotkeyAction> get failures => Set.unmodifiable(_failures);
  final Set<HotkeyAction> _failures = {};

  /// Called by the platform layer for each `WM_HOTKEY`.
  void handleNativeHotkey(int id) {
    final action = HotkeyAction.fromNativeId(id);
    if (action != null) onAction?.call(action);
  }

  /// Replaces all registered shortcuts with [bindings].
  Future<void> apply(Map<HotkeyAction, Hotkey?> bindings) async {
    await _platform.unregisterAllHotkeys();
    _failures.clear();
    for (final action in HotkeyAction.values) {
      final hotkey = bindings[action];
      if (hotkey == null) continue;
      final ok = await _platform.registerHotkey(
        id: action.nativeId,
        modifiers: hotkey.modifiers,
        vk: hotkey.vk,
        repeat: action.repeats,
      );
      if (!ok) _failures.add(action);
    }
  }

  /// Releases every shortcut, e.g. while the user records a new one.
  Future<void> suspend() => _platform.unregisterAllHotkeys();
}
