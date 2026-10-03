import 'package:shared_preferences/shared_preferences.dart';

import '../settings/settings_model.dart';

/// Where settings are stored. Abstract so tests can keep them in memory.
abstract class SettingsStore {
  Future<AppSettings> load();
  Future<void> save(AppSettings settings);
}

/// Persists settings as one JSON document through `shared_preferences`,
/// which on Windows is a small file under
/// `%APPDATA%\<company>\Preview Cam\shared_preferences.json`.
class PreferencesService implements SettingsStore {
  static const String _key = 'settings';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _instance async =>
      _prefs ??= await SharedPreferences.getInstance();

  @override
  Future<AppSettings> load() async {
    try {
      return AppSettings.decode((await _instance).getString(_key));
    } on Exception {
      // An unreadable preferences file must not prevent the overlay opening.
      return const AppSettings();
    }
  }

  @override
  Future<void> save(AppSettings settings) async {
    await (await _instance).setString(_key, settings.encode());
  }
}
