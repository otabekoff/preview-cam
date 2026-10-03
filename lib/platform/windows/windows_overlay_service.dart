import 'package:flutter/services.dart';

import '../../services/monitor_service.dart';
import '../overlay_platform.dart';

/// Windows implementation of [OverlayPlatform].
///
/// A thin, typed wrapper around the `preview/native` method channel served by
/// `windows/runner/overlay_window.cpp`, where the Win32 work happens.
class WindowsOverlayService implements OverlayPlatform {
  WindowsOverlayService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('preview/native') {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final MethodChannel _channel;

  @override
  final OverlayPlatformEvents events = OverlayPlatformEvents();

  Future<void> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onBoundsChanged':
        events.onBoundsChanged?.call(
          WindowBounds.fromMap(call.arguments as Map<Object?, Object?>),
        );
      case 'onHotkey':
        events.onHotkey?.call(call.arguments as int);
      case 'onTrayCommand':
        events.onTrayCommand?.call(call.arguments as String);
      case 'onDeviceChange':
        events.onDeviceChange?.call();
      case 'onDisplayChange':
        events.onDisplayChange?.call();
      case 'onCloseRequested':
        events.onCloseRequested?.call();
      case 'onSecondInstance':
        events.onSecondInstance?.call();
      case 'onSettingsClosed':
        events.onSettingsClosed?.call();
      case 'onRelay':
        final message = call.arguments;
        if (message is Map) events.onRelay?.call(message);
    }
  }

  @override
  Future<List<MonitorInfo>> getMonitors() async {
    final list = await _channel.invokeListMethod<Object?>('getMonitors');
    return [
      for (final item in list ?? const <Object?>[])
        MonitorInfo.fromMap(item! as Map<Object?, Object?>),
    ];
  }

  @override
  Future<WindowBounds> getBounds() async =>
      WindowBounds.fromMap((await _channel.invokeMapMethod('getBounds'))!);

  @override
  Future<WindowBounds> setBounds(PxRect rect) async => WindowBounds.fromMap(
    (await _channel.invokeMapMethod('setBounds', {
      'x': rect.x,
      'y': rect.y,
      'width': rect.width,
      'height': rect.height,
    }))!,
  );

  @override
  Future<void> show({bool activate = false}) =>
      _channel.invokeMethod('show', {'activate': activate});

  @override
  Future<void> hide() => _channel.invokeMethod('hide');

  @override
  Future<void> setAlwaysOnTop(bool value) =>
      _channel.invokeMethod('setAlwaysOnTop', value);

  @override
  Future<void> setClickThrough(bool value) =>
      _channel.invokeMethod('setClickThrough', value);

  @override
  Future<void> setSkipTaskbar(bool value) =>
      _channel.invokeMethod('setSkipTaskbar', value);

  @override
  Future<void> setOpacity(double value) =>
      _channel.invokeMethod('setOpacity', value);

  @override
  Future<void> setShape(NativeShape shape, double radius) => _channel
      .invokeMethod('setShape', {'kind': shape.index, 'radius': radius});

  @override
  Future<void> setAspectRatio(double ratio) =>
      _channel.invokeMethod('setAspectRatio', ratio);

  @override
  Future<void> setMinSize(double logical) =>
      _channel.invokeMethod('setMinSize', logical);

  @override
  Future<void> startDrag() => _channel.invokeMethod('startDrag');

  @override
  Future<bool> registerHotkey({
    required int id,
    required int modifiers,
    required int vk,
    bool repeat = false,
  }) async =>
      await _channel.invokeMethod<bool>('registerHotkey', {
        'id': id,
        'modifiers': modifiers,
        'vk': vk,
        'repeat': repeat,
      }) ??
      false;

  @override
  Future<void> unregisterAllHotkeys() =>
      _channel.invokeMethod('unregisterAllHotkeys');

  @override
  Future<void> setTrayState({
    required bool visible,
    required bool clickThrough,
    required bool alwaysOnTop,
    required Map<String, String> labels,
  }) => _channel.invokeMethod('setTrayState', {
    'visible': visible,
    'clickThrough': clickThrough,
    'alwaysOnTop': alwaysOnTop,
    'labels': labels,
  });

  @override
  Future<bool> getStartup() async =>
      await _channel.invokeMethod<bool>('getStartup') ?? false;

  @override
  Future<bool> setStartup(bool enabled) async =>
      await _channel.invokeMethod<bool>('setStartup', enabled) ?? false;

  @override
  Future<void> openSettings() => _channel.invokeMethod('openSettings');

  @override
  Future<void> relay(Map<String, Object?> message) =>
      _channel.invokeMethod('relay', message);

  @override
  Future<void> openSystemSettings(String uri) =>
      _channel.invokeMethod('openSystemSettings', uri);

  @override
  Future<void> quit() => _channel.invokeMethod('quit');
}
