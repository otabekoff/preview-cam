import '../services/hotkey_service.dart';
import '../services/monitor_service.dart';
import '../settings/settings_model.dart';

/// Languages the user interface is available in.
enum AppLanguage {
  en('English'),
  uz('O‘zbekcha'),
  ru('Русский');

  const AppLanguage(this.nativeName);

  /// The language's own name, shown in the language selector.
  final String nativeName;
}

/// Every user-visible text of the application.
///
/// One subclass per language. Texts are plain getters and methods (rather
/// than generated from ARB files) so the overlay engine, the settings engine
/// and the native tray menu can all be fed from the same small table, and a
/// missing translation is a compile error.
abstract class AppStrings {
  const AppStrings();

  static AppStrings of(AppLanguage language) => switch (language) {
    AppLanguage.en => const _English(),
    AppLanguage.uz => const _Uzbek(),
    AppLanguage.ru => const _Russian(),
  };

  // --- Shared -------------------------------------------------------------
  String get settings;
  String get retry;
  String get camera;
  String get clickThrough;
  String get alwaysOnTop;
  String get position;
  String get shape;

  // --- Overlay: camera states ----------------------------------------------
  String get cameraStarting;
  String get noCameraTitle;
  String get noCameraMessage;
  String get disconnectedTitle;
  String disconnectedMessage(String camera);
  String get permissionTitle;
  String get permissionMessage;
  String get inUseTitle;
  String inUseMessage(String camera);
  String get unavailableTitle;
  String unavailableMessage(String camera);

  /// Used when the camera's name is not known.
  String get theCamera;
  String get privacySettings;

  // --- Overlay: toasts, hint, controls -------------------------------------
  String get clickThroughOff;
  String clickThroughOn(String hotkey);
  String get clickThroughOnTray;
  String get virtualCameraFailed;
  String get hintMove;
  String get hintHover;
  String hintClickThrough(String hotkey);
  String get hintClickThroughTray;
  String get hintDismiss;
  String get mirror;
  String get hideToTray;

  // --- Tray ---------------------------------------------------------------
  String get showCamera;
  String get hideCamera;
  String get exit;

  // --- Settings window -------------------------------------------------------
  String get connecting;
  String get sectionAppearance;
  String get sectionBehavior;
  String get sectionHotkeys;
  String get language;
  String get device;
  String get automaticDevice;
  String notConnected(String camera);
  String get resolution;
  String get maximum;
  String get frameRate;
  String get automatic;
  String fps(int value);
  String get mirrorPreview;
  String get transparentBackground;
  String get virtualCamera;
  String get virtualCameraHint;
  String get cornerRadius;
  String get opacity;
  String get overlaySize;
  String get lockAspect;
  String get overlayHidden;
  String get show;
  String get hideFromTaskbar;
  String get windowCapture;
  String get startWithWindows;
  String get rememberPosition;
  String get hoverControls;
  String get pressKeys;
  String get none;
  String get removeShortcut;
  String get hotkeyInUse;
  String get resetHotkeys;
  String get statusIdle;
  String statusStarting(String camera);
  String get withTransparency;
  String get statusNoCameras;
  String statusDisconnected(String camera);
  String get statusPermission;
  String statusInUse(String camera);
  String statusUnavailable(String camera);
  String get developedBy;
  String get supportProject;

  // --- Names of enum values --------------------------------------------------
  String shapeName(OverlayShape shape);
  String presetName(PositionPreset preset);
  String hotkeyActionName(HotkeyAction action);

  String resolutionName(CameraResolution resolution) =>
      resolution == CameraResolution.max ? maximum : resolution.label;

  /// Labels of the native tray menu, keyed as the Windows runner expects.
  Map<String, String> trayLabels() => {
    'show': showCamera,
    'hide': hideCamera,
    'clickThrough': clickThrough,
    'alwaysOnTop': alwaysOnTop,
    'position': position,
    'settings': settings,
    'exit': exit,
    for (final preset in PositionPreset.values) preset.name: presetName(preset),
  };
}

class _English extends AppStrings {
  const _English();

  @override
  String get settings => 'Settings';
  @override
  String get retry => 'Retry';
  @override
  String get camera => 'Camera';
  @override
  String get clickThrough => 'Click-through';
  @override
  String get alwaysOnTop => 'Always on top';
  @override
  String get position => 'Position';
  @override
  String get shape => 'Shape';

  @override
  String get cameraStarting => 'Starting camera…';
  @override
  String get noCameraTitle => 'No camera found';
  @override
  String get noCameraMessage =>
      'Connect a camera. The preview starts automatically.';
  @override
  String get disconnectedTitle => 'Camera disconnected';
  @override
  String disconnectedMessage(String camera) =>
      '$camera is not connected.\n'
      'Reconnect it or choose another camera in Settings.';
  @override
  String get permissionTitle => 'Camera permission required';
  @override
  String get permissionMessage =>
      'Allow desktop apps to use the camera in Windows privacy settings.';
  @override
  String get inUseTitle => 'Camera in use';
  @override
  String inUseMessage(String camera) =>
      '$camera is being used by another application.\n'
      'Close it there or choose another camera from Settings.';
  @override
  String get unavailableTitle => 'Camera unavailable';
  @override
  String unavailableMessage(String camera) =>
      '$camera is currently unavailable.\n'
      'Choose another camera from Settings.';
  @override
  String get theCamera => 'The camera';
  @override
  String get privacySettings => 'Privacy settings';

  @override
  String get clickThroughOff => 'Click-through off';
  @override
  String clickThroughOn(String hotkey) =>
      'Click-through on · $hotkey to turn off';
  @override
  String get clickThroughOnTray => 'Click-through on · turn off from the tray';
  @override
  String get virtualCameraFailed => 'Virtual camera could not be enabled';
  @override
  String get hintMove => 'Drag anywhere to move · edges to resize';
  @override
  String get hintHover => 'Hover for controls';
  @override
  String hintClickThrough(String hotkey) => '$hotkey toggles click-through';
  @override
  String get hintClickThroughTray => 'Click-through: tray menu';
  @override
  String get hintDismiss => 'Click to dismiss';
  @override
  String get mirror => 'Mirror';
  @override
  String get hideToTray => 'Hide to tray';

  @override
  String get showCamera => 'Show Camera';
  @override
  String get hideCamera => 'Hide Camera';
  @override
  String get exit => 'Exit';

  @override
  String get connecting => 'Connecting to overlay…';
  @override
  String get sectionAppearance => 'Appearance';
  @override
  String get sectionBehavior => 'Behavior';
  @override
  String get sectionHotkeys => 'Global hotkeys';
  @override
  String get language => 'Language';
  @override
  String get device => 'Device';
  @override
  String get automaticDevice => 'Automatic (first available)';
  @override
  String notConnected(String camera) => '$camera (not connected)';
  @override
  String get resolution => 'Resolution';
  @override
  String get maximum => 'Maximum';
  @override
  String get frameRate => 'Frame rate';
  @override
  String get automatic => 'Automatic';
  @override
  String fps(int value) => '$value fps';
  @override
  String get mirrorPreview => 'Mirror preview';
  @override
  String get transparentBackground =>
      'Transparent background (if the camera removes it)';
  @override
  String get virtualCamera => 'Virtual camera for OBS ("Preview Cam" device)';
  @override
  String get virtualCameraHint =>
      'In OBS add a Video Capture Device source and choose the device '
      '"Preview Cam". Window Capture cannot show transparency.';
  @override
  String get cornerRadius => 'Corner radius';
  @override
  String get opacity => 'Opacity';
  @override
  String get overlaySize => 'Overlay size';
  @override
  String get lockAspect => 'Lock aspect ratio to camera';
  @override
  String get overlayHidden => 'The overlay is hidden.';
  @override
  String get show => 'Show';
  @override
  String get hideFromTaskbar => 'Hide from taskbar';
  @override
  String get windowCapture => 'Allow window capture (OBS window list)';
  @override
  String get startWithWindows => 'Start with Windows';
  @override
  String get rememberPosition => 'Remember position';
  @override
  String get hoverControls => 'Hover controls';
  @override
  String get pressKeys => 'Press keys…';
  @override
  String get none => 'None';
  @override
  String get removeShortcut => 'Remove shortcut';
  @override
  String get hotkeyInUse => 'Already in use by another application';
  @override
  String get resetHotkeys => 'Reset hotkeys';
  @override
  String get statusIdle => 'Camera is off while the overlay is hidden.';
  @override
  String statusStarting(String camera) => 'Starting $camera…';
  @override
  String get withTransparency => 'with transparency';
  @override
  String get statusNoCameras => 'No camera found.';
  @override
  String statusDisconnected(String camera) => '$camera is not connected.';
  @override
  String get statusPermission =>
      'Camera access is blocked in Windows privacy settings.';
  @override
  String statusInUse(String camera) =>
      '$camera is being used by another application.';
  @override
  String statusUnavailable(String camera) => '$camera is unavailable';
  @override
  String get developedBy => 'Developed by';
  @override
  String get supportProject => 'Support the project';

  @override
  String shapeName(OverlayShape shape) => switch (shape) {
    OverlayShape.rectangle => 'Rectangle',
    OverlayShape.rounded => 'Rounded',
    OverlayShape.circle => 'Circle',
    OverlayShape.wide => '16:9 rounded',
    OverlayShape.classic => '4:3 rounded',
  };
  @override
  String presetName(PositionPreset preset) => switch (preset) {
    PositionPreset.topLeft => 'Top Left',
    PositionPreset.topRight => 'Top Right',
    PositionPreset.bottomLeft => 'Bottom Left',
    PositionPreset.bottomRight => 'Bottom Right',
    PositionPreset.center => 'Center',
  };
  @override
  String hotkeyActionName(HotkeyAction action) => switch (action) {
    HotkeyAction.toggleOverlay => 'Show / hide overlay',
    HotkeyAction.toggleClickThrough => 'Toggle click-through',
    HotkeyAction.sizeUp => 'Increase size',
    HotkeyAction.sizeDown => 'Decrease size',
    HotkeyAction.moveBottomRight => 'Move to bottom-right',
    HotkeyAction.openSettings => 'Open settings',
  };
}

class _Uzbek extends AppStrings {
  const _Uzbek();

  @override
  String get settings => 'Sozlamalar';
  @override
  String get retry => 'Qayta urinish';
  @override
  String get camera => 'Kamera';
  @override
  String get clickThrough => 'Bosishlarni o‘tkazish';
  @override
  String get alwaysOnTop => 'Doim ustda';
  @override
  String get position => 'Joylashuv';
  @override
  String get shape => 'Shakl';

  @override
  String get cameraStarting => 'Kamera ishga tushmoqda…';
  @override
  String get noCameraTitle => 'Kamera topilmadi';
  @override
  String get noCameraMessage =>
      'Kamerani ulang. Tasvir avtomatik ravishda boshlanadi.';
  @override
  String get disconnectedTitle => 'Kamera uzilgan';
  @override
  String disconnectedMessage(String camera) =>
      '$camera ulanmagan.\n'
      'Uni qayta ulang yoki Sozlamalarda boshqa kamerani tanlang.';
  @override
  String get permissionTitle => 'Kameraga ruxsat kerak';
  @override
  String get permissionMessage =>
      'Windows maxfiylik sozlamalarida ilovalarga kameradan foydalanishga '
      'ruxsat bering.';
  @override
  String get inUseTitle => 'Kamera band';
  @override
  String inUseMessage(String camera) =>
      '$camera boshqa ilova tomonidan ishlatilmoqda.\n'
      'Uni o‘sha yerda yoping yoki Sozlamalarda boshqa kamerani tanlang.';
  @override
  String get unavailableTitle => 'Kamera ishlamayapti';
  @override
  String unavailableMessage(String camera) =>
      '$camera hozircha ishlamayapti.\n'
      'Sozlamalarda boshqa kamerani tanlang.';
  @override
  String get theCamera => 'Kamera';
  @override
  String get privacySettings => 'Maxfiylik sozlamalari';

  @override
  String get clickThroughOff => 'Bosishlarni o‘tkazish o‘chirildi';
  @override
  String clickThroughOn(String hotkey) =>
      'Bosishlarni o‘tkazish yoqildi · o‘chirish: $hotkey';
  @override
  String get clickThroughOnTray =>
      'Bosishlarni o‘tkazish yoqildi · treydan o‘chiring';
  @override
  String get virtualCameraFailed => 'Virtual kamerani yoqib bo‘lmadi';
  @override
  String get hintMove => 'Ko‘chirish uchun torting · o‘lcham uchun chetidan';
  @override
  String get hintHover => 'Tugmalar uchun kursorni olib keling';
  @override
  String hintClickThrough(String hotkey) => '$hotkey — bosishlarni o‘tkazish';
  @override
  String get hintClickThroughTray => 'Bosishlarni o‘tkazish: trey menyusi';
  @override
  String get hintDismiss => 'Yopish uchun bosing';
  @override
  String get mirror => 'Ko‘zgu';
  @override
  String get hideToTray => 'Treyga yashirish';

  @override
  String get showCamera => 'Kamerani ko‘rsatish';
  @override
  String get hideCamera => 'Kamerani yashirish';
  @override
  String get exit => 'Chiqish';

  @override
  String get connecting => 'Oynaga ulanmoqda…';
  @override
  String get sectionAppearance => 'Ko‘rinish';
  @override
  String get sectionBehavior => 'Ishlash tartibi';
  @override
  String get sectionHotkeys => 'Global tezkor tugmalar';
  @override
  String get language => 'Til';
  @override
  String get device => 'Qurilma';
  @override
  String get automaticDevice => 'Avtomatik (birinchi mavjud)';
  @override
  String notConnected(String camera) => '$camera (ulanmagan)';
  @override
  String get resolution => 'Aniqlik';
  @override
  String get maximum => 'Maksimal';
  @override
  String get frameRate => 'Kadr tezligi';
  @override
  String get automatic => 'Avtomatik';
  @override
  String fps(int value) => '$value kadr/s';
  @override
  String get mirrorPreview => 'Ko‘zgu tasvir';
  @override
  String get transparentBackground =>
      'Shaffof fon (kamera fonni olib tashlasa)';
  @override
  String get virtualCamera =>
      'OBS uchun virtual kamera (“Preview Cam” qurilmasi)';
  @override
  String get virtualCameraHint =>
      'OBS’da “Video Capture Device” manbasini qo‘shing va “Preview Cam” '
      'qurilmasini tanlang. “Window Capture” shaffoflikni ko‘rsata olmaydi.';
  @override
  String get cornerRadius => 'Burchak radiusi';
  @override
  String get opacity => 'Noshaffoflik';
  @override
  String get overlaySize => 'Oyna o‘lchami';
  @override
  String get lockAspect => 'Tomonlar nisbatini kameraga moslash';
  @override
  String get overlayHidden => 'Oyna yashirilgan.';
  @override
  String get show => 'Ko‘rsatish';
  @override
  String get hideFromTaskbar => 'Vazifalar panelidan yashirish';
  @override
  String get windowCapture =>
      'Oynani yozib olishga ruxsat (OBS oynalar ro‘yxati)';
  @override
  String get startWithWindows => 'Windows bilan birga ishga tushirish';
  @override
  String get rememberPosition => 'Joylashuvni eslab qolish';
  @override
  String get hoverControls => 'Kursor ostida boshqaruv tugmalari';
  @override
  String get pressKeys => 'Tugmalarni bosing…';
  @override
  String get none => 'Yo‘q';
  @override
  String get removeShortcut => 'Tugmalar birikmasini olib tashlash';
  @override
  String get hotkeyInUse => 'Boshqa ilova tomonidan band qilingan';
  @override
  String get resetHotkeys => 'Tugmalarni tiklash';
  @override
  String get statusIdle => 'Oyna yashirilganda kamera o‘chiq.';
  @override
  String statusStarting(String camera) => '$camera ishga tushmoqda…';
  @override
  String get withTransparency => 'shaffoflik bilan';
  @override
  String get statusNoCameras => 'Kamera topilmadi.';
  @override
  String statusDisconnected(String camera) => '$camera ulanmagan.';
  @override
  String get statusPermission =>
      'Kameraga kirish Windows maxfiylik sozlamalarida bloklangan.';
  @override
  String statusInUse(String camera) =>
      '$camera boshqa ilova tomonidan ishlatilmoqda.';
  @override
  String statusUnavailable(String camera) => '$camera ishlamayapti';
  @override
  String get developedBy => 'Dasturchi:';
  @override
  String get supportProject => 'Loyihani qo‘llab-quvvatlash';

  @override
  String shapeName(OverlayShape shape) => switch (shape) {
    OverlayShape.rectangle => 'To‘rtburchak',
    OverlayShape.rounded => 'Yumaloq burchakli',
    OverlayShape.circle => 'Doira',
    OverlayShape.wide => '16:9 yumaloq burchakli',
    OverlayShape.classic => '4:3 yumaloq burchakli',
  };
  @override
  String presetName(PositionPreset preset) => switch (preset) {
    PositionPreset.topLeft => 'Yuqori chap',
    PositionPreset.topRight => 'Yuqori o‘ng',
    PositionPreset.bottomLeft => 'Pastki chap',
    PositionPreset.bottomRight => 'Pastki o‘ng',
    PositionPreset.center => 'Markaz',
  };
  @override
  String hotkeyActionName(HotkeyAction action) => switch (action) {
    HotkeyAction.toggleOverlay => 'Oynani ko‘rsatish / yashirish',
    HotkeyAction.toggleClickThrough => 'Bosishlarni o‘tkazishni almashtirish',
    HotkeyAction.sizeUp => 'Kattalashtirish',
    HotkeyAction.sizeDown => 'Kichiklashtirish',
    HotkeyAction.moveBottomRight => 'Pastki o‘ng burchakka ko‘chirish',
    HotkeyAction.openSettings => 'Sozlamalarni ochish',
  };
}

class _Russian extends AppStrings {
  const _Russian();

  @override
  String get settings => 'Настройки';
  @override
  String get retry => 'Повторить';
  @override
  String get camera => 'Камера';
  @override
  String get clickThrough => 'Сквозные клики';
  @override
  String get alwaysOnTop => 'Поверх всех окон';
  @override
  String get position => 'Положение';
  @override
  String get shape => 'Форма';

  @override
  String get cameraStarting => 'Запуск камеры…';
  @override
  String get noCameraTitle => 'Камера не найдена';
  @override
  String get noCameraMessage =>
      'Подключите камеру. Просмотр запустится автоматически.';
  @override
  String get disconnectedTitle => 'Камера отключена';
  @override
  String disconnectedMessage(String camera) =>
      '$camera: камера не подключена.\n'
      'Подключите её снова или выберите другую камеру в настройках.';
  @override
  String get permissionTitle => 'Требуется доступ к камере';
  @override
  String get permissionMessage =>
      'Разрешите классическим приложениям доступ к камере в параметрах '
      'конфиденциальности Windows.';
  @override
  String get inUseTitle => 'Камера занята';
  @override
  String inUseMessage(String camera) =>
      '$camera: камера используется другим приложением.\n'
      'Закройте её там или выберите другую камеру в настройках.';
  @override
  String get unavailableTitle => 'Камера недоступна';
  @override
  String unavailableMessage(String camera) =>
      '$camera: камера сейчас недоступна.\n'
      'Выберите другую камеру в настройках.';
  @override
  String get theCamera => 'Камера';
  @override
  String get privacySettings => 'Параметры конфиденциальности';

  @override
  String get clickThroughOff => 'Сквозные клики выключены';
  @override
  String clickThroughOn(String hotkey) =>
      'Сквозные клики включены · выключить: $hotkey';
  @override
  String get clickThroughOnTray => 'Сквозные клики включены · выключите в трее';
  @override
  String get virtualCameraFailed => 'Не удалось включить виртуальную камеру';
  @override
  String get hintMove => 'Перетащите, чтобы переместить · края — размер';
  @override
  String get hintHover => 'Наведите курсор для управления';
  @override
  String hintClickThrough(String hotkey) => '$hotkey — сквозные клики';
  @override
  String get hintClickThroughTray => 'Сквозные клики: меню в трее';
  @override
  String get hintDismiss => 'Нажмите, чтобы закрыть';
  @override
  String get mirror => 'Зеркало';
  @override
  String get hideToTray => 'Скрыть в трей';

  @override
  String get showCamera => 'Показать камеру';
  @override
  String get hideCamera => 'Скрыть камеру';
  @override
  String get exit => 'Выход';

  @override
  String get connecting => 'Подключение к окну камеры…';
  @override
  String get sectionAppearance => 'Внешний вид';
  @override
  String get sectionBehavior => 'Поведение';
  @override
  String get sectionHotkeys => 'Глобальные горячие клавиши';
  @override
  String get language => 'Язык';
  @override
  String get device => 'Устройство';
  @override
  String get automaticDevice => 'Автоматически (первая доступная)';
  @override
  String notConnected(String camera) => '$camera (не подключена)';
  @override
  String get resolution => 'Разрешение';
  @override
  String get maximum => 'Максимальное';
  @override
  String get frameRate => 'Частота кадров';
  @override
  String get automatic => 'Автоматически';
  @override
  String fps(int value) => '$value кадр/с';
  @override
  String get mirrorPreview => 'Зеркальное отображение';
  @override
  String get transparentBackground =>
      'Прозрачный фон (если камера его убирает)';
  @override
  String get virtualCamera =>
      'Виртуальная камера для OBS (устройство «Preview Cam»)';
  @override
  String get virtualCameraHint =>
      'В OBS добавьте источник «Устройство захвата видео» и выберите '
      'устройство «Preview Cam». «Захват окна» не передаёт прозрачность.';
  @override
  String get cornerRadius => 'Радиус углов';
  @override
  String get opacity => 'Непрозрачность';
  @override
  String get overlaySize => 'Размер окна';
  @override
  String get lockAspect => 'Сохранять пропорции камеры';
  @override
  String get overlayHidden => 'Окно камеры скрыто.';
  @override
  String get show => 'Показать';
  @override
  String get hideFromTaskbar => 'Скрыть с панели задач';
  @override
  String get windowCapture => 'Разрешить захват окна (список окон OBS)';
  @override
  String get startWithWindows => 'Запускать вместе с Windows';
  @override
  String get rememberPosition => 'Запоминать положение';
  @override
  String get hoverControls => 'Кнопки управления при наведении';
  @override
  String get pressKeys => 'Нажмите клавиши…';
  @override
  String get none => 'Нет';
  @override
  String get removeShortcut => 'Удалить сочетание';
  @override
  String get hotkeyInUse => 'Уже используется другим приложением';
  @override
  String get resetHotkeys => 'Сбросить клавиши';
  @override
  String get statusIdle => 'Камера выключена, пока окно скрыто.';
  @override
  String statusStarting(String camera) => 'Запуск: $camera…';
  @override
  String get withTransparency => 'с прозрачностью';
  @override
  String get statusNoCameras => 'Камера не найдена.';
  @override
  String statusDisconnected(String camera) => '$camera: не подключена.';
  @override
  String get statusPermission =>
      'Доступ к камере заблокирован в параметрах конфиденциальности Windows.';
  @override
  String statusInUse(String camera) =>
      '$camera: используется другим приложением.';
  @override
  String statusUnavailable(String camera) => '$camera: недоступна';
  @override
  String get developedBy => 'Разработчик:';
  @override
  String get supportProject => 'Поддержать проект';

  @override
  String shapeName(OverlayShape shape) => switch (shape) {
    OverlayShape.rectangle => 'Прямоугольник',
    OverlayShape.rounded => 'Скруглённый',
    OverlayShape.circle => 'Круг',
    OverlayShape.wide => '16:9 скруглённый',
    OverlayShape.classic => '4:3 скруглённый',
  };
  @override
  String presetName(PositionPreset preset) => switch (preset) {
    PositionPreset.topLeft => 'Сверху слева',
    PositionPreset.topRight => 'Сверху справа',
    PositionPreset.bottomLeft => 'Снизу слева',
    PositionPreset.bottomRight => 'Снизу справа',
    PositionPreset.center => 'По центру',
  };
  @override
  String hotkeyActionName(HotkeyAction action) => switch (action) {
    HotkeyAction.toggleOverlay => 'Показать / скрыть окно',
    HotkeyAction.toggleClickThrough => 'Переключить сквозные клики',
    HotkeyAction.sizeUp => 'Увеличить',
    HotkeyAction.sizeDown => 'Уменьшить',
    HotkeyAction.moveBottomRight => 'Переместить вправо вниз',
    HotkeyAction.openSettings => 'Открыть настройки',
  };
}
