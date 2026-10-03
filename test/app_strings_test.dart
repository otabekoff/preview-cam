import 'package:flutter_test/flutter_test.dart';
import 'package:preview/l10n/app_strings.dart';
import 'package:preview/overlay/overlay_controller.dart';
import 'package:preview/camera/camera_controller.dart';
import 'package:preview/services/hotkey_service.dart';
import 'package:preview/services/monitor_service.dart';
import 'package:preview/settings/settings_controller.dart';
import 'package:preview/settings/settings_model.dart';

import 'fakes.dart';

void main() {
  test('English is the default language and the choice is persisted', () {
    expect(const AppSettings().language, AppLanguage.en);
    final saved = const AppSettings().copyWith(language: AppLanguage.uz);
    expect(AppSettings.decode(saved.encode()).language, AppLanguage.uz);
    expect(AppSettings.decode('{"language":"xx"}').language, AppLanguage.en);
  });

  test('every language names every shape, position, hotkey and tray item', () {
    for (final language in AppLanguage.values) {
      final t = AppStrings.of(language);
      for (final shape in OverlayShape.values) {
        expect(t.shapeName(shape), isNotEmpty);
      }
      for (final preset in PositionPreset.values) {
        expect(t.presetName(preset), isNotEmpty);
      }
      for (final action in HotkeyAction.values) {
        expect(t.hotkeyActionName(action), isNotEmpty);
      }
      final tray = t.trayLabels();
      expect(tray.keys, containsAll(['show', 'hide', 'settings', 'exit']));
      expect(tray.values, everyElement(isNotEmpty));
    }
    expect(AppStrings.of(AppLanguage.uz).settings, 'Sozlamalar');
    expect(AppStrings.of(AppLanguage.ru).settings, 'Настройки');
  });

  test('changing the language retranslates the tray menu and toasts', () async {
    final platform = FakeOverlayPlatform();
    final controller = OverlayController(
      platform: platform,
      settings: SettingsController(MemoryStore(), saveDelay: Duration.zero),
      camera: CameraFeedController(FakeCameraBackend()),
    );
    addTearDown(controller.dispose);
    await controller.init();
    await pumpEventQueue();
    expect(platform.trayLabels['exit'], 'Exit');

    controller.settings.update((s) => s.copyWith(language: AppLanguage.ru));
    await pumpEventQueue();
    expect(platform.trayLabels['exit'], 'Выход');

    controller.toggleClickThrough();
    await pumpEventQueue();
    expect(controller.toast.value, contains('Сквозные клики включены'));
  });
}
