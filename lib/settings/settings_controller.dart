import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/preferences_service.dart';
import 'settings_model.dart';

/// Holds the current [AppSettings] and writes changes to disk.
///
/// Writes are debounced: dragging a slider or resizing the window produces
/// many updates but a single save shortly after the last one.
class SettingsController extends ChangeNotifier {
  SettingsController(
    this._store, {
    this.saveDelay = const Duration(milliseconds: 400),
  });

  final SettingsStore _store;
  final Duration saveDelay;

  AppSettings get value => _value;
  AppSettings _value = const AppSettings();

  Timer? _saveTimer;

  Future<void> load() async {
    _value = await _store.load();
    notifyListeners();
  }

  /// Replaces the settings. Listeners run only when something changed.
  set value(AppSettings next) {
    if (next == _value) return;
    _value = next;
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, flush);
    notifyListeners();
  }

  void update(AppSettings Function(AppSettings current) change) {
    value = change(_value);
  }

  /// Writes any pending change immediately (used before exiting).
  Future<void> flush() async {
    if (_saveTimer == null) return;
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      await _store.save(_value);
    } on Exception catch (error) {
      debugPrint('Saving settings failed: $error');
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
