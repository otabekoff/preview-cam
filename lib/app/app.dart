import 'package:flutter/material.dart';

import '../overlay/overlay_controller.dart';
import '../overlay/overlay_view.dart';

/// Root widget of the overlay window.
///
/// Nothing here paints a background: any pixel the overlay does not cover
/// stays fully transparent, which the native window turns into see-through
/// desktop.
class OverlayApp extends StatelessWidget {
  const OverlayApp({super.key, required this.controller});

  final OverlayController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Preview Cam',
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
      ),
      home: Material(
        type: MaterialType.transparency,
        child: OverlayView(controller: controller),
      ),
    );
  }
}

/// Shown when the application is started on a platform that has no
/// `OverlayPlatform` implementation yet.
class UnsupportedPlatformApp extends StatelessWidget {
  const UnsupportedPlatformApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Text('Preview Cam currently supports Windows only.'),
        ),
      ),
    );
  }
}
