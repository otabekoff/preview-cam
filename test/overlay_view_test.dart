import 'dart:ui';

import 'package:preview/camera/camera_backend.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:preview/app/app.dart';
import 'package:preview/camera/camera_controller.dart';
import 'package:preview/overlay/overlay_controller.dart';
import 'package:preview/overlay/overlay_controls.dart';
import 'package:preview/overlay/overlay_view.dart';
import 'package:preview/settings/settings_controller.dart';
import 'package:preview/settings/settings_model.dart';

import 'fakes.dart';

void main() {
  late FakeOverlayPlatform platform;
  late FakeCameraBackend cameraBackend;
  late OverlayController controller;

  Future<void> pumpOverlay(WidgetTester tester, {AppSettings? saved}) async {
    tester.view.physicalSize = const Size(320, 180);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    platform = FakeOverlayPlatform();
    // Built inside runAsync so the controllers' futures and timers live in
    // the real event loop rather than the test's fake clock.
    await tester.runAsync(() async {
      controller = OverlayController(
        platform: platform,
        settings: SettingsController(
          MemoryStore(saved ?? const AppSettings(onboardingShown: true)),
          saveDelay: Duration.zero,
        ),
        camera: CameraFeedController(cameraBackend),
      );
    });
    addTearDown(controller.dispose);
    await tester.pumpWidget(OverlayApp(controller: controller));
    await tester.runAsync(() async {
      await controller.init();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  setUp(() => cameraBackend = FakeCameraBackend());

  testWidgets('shows the camera texture when running', (tester) async {
    await pumpOverlay(tester);
    expect(find.byType(Texture), findsOneWidget);
    expect(find.byType(ClipRRect), findsWidgets);
  });

  testWidgets('a camera with its own transparency gets no black backdrop', (
    tester,
  ) async {
    Finder blackBackdrop() => find.byWidgetPredicate(
      (widget) => widget is ColoredBox && widget.color == Colors.black,
    );

    await pumpOverlay(tester);
    expect(blackBackdrop(), findsOneWidget);

    cameraBackend.hasAlpha = true;
    await tester.runAsync(() => controller.camera.retry());
    await tester.pump();
    expect(find.byType(Texture), findsOneWidget);
    expect(blackBackdrop(), findsNothing);

    // The user can opt out and keep the black background.
    controller.settings.update((s) => s.copyWith(cameraTransparency: false));
    await tester.pump();
    expect(blackBackdrop(), findsOneWidget);
    await tester.runAsync(() => controller.settings.flush());
  });

  testWidgets('explains a missing camera instead of an empty window', (
    tester,
  ) async {
    cameraBackend.available = [];
    await pumpOverlay(tester);

    expect(find.byType(Texture), findsNothing);
    expect(find.text('No camera found'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('offers the privacy settings when permission is denied', (
    tester,
  ) async {
    cameraBackend.openError = const CameraOpenException(
      CameraFailure.accessDenied,
    );
    await pumpOverlay(tester);

    expect(find.text('Camera permission required'), findsOneWidget);
    await tester.tap(find.text('Privacy settings'));
    expect(
      platform.calls,
      contains('openSystemSettings ms-settings:privacy-webcam'),
    );
  });

  testWidgets('controls appear on hover and hide after the mouse leaves', (
    tester,
  ) async {
    await pumpOverlay(tester);
    bool visible() =>
        tester.widget<OverlayControls>(find.byType(OverlayControls)).visible;
    expect(visible(), isFalse);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 400));
    addTearDown(mouse.removePointer);
    await mouse.moveTo(const Offset(160, 90));
    await tester.pump();
    expect(visible(), isTrue);

    await mouse.moveTo(const Offset(400, 400));
    await tester.pump(kControlsHideDelay ~/ 2);
    expect(visible(), isTrue);
    await tester.pump(kControlsHideDelay);
    expect(visible(), isFalse);
  });

  testWidgets('dragging the picture starts a native window drag', (
    tester,
  ) async {
    await pumpOverlay(tester);
    await tester.drag(
      find.byType(OverlayView),
      const Offset(40, 30),
      kind: PointerDeviceKind.mouse,
      touchSlopX: kPrecisePointerPanSlop,
      touchSlopY: kPrecisePointerPanSlop,
    );
    expect(platform.calls, contains('startDrag'));
  });

  testWidgets('first launch shows the hint until dismissed', (tester) async {
    await pumpOverlay(tester, saved: const AppSettings());
    expect(find.textContaining('toggles click-through'), findsOneWidget);

    await tester.tap(find.text('Click to dismiss'));
    await tester.pump();
    expect(find.textContaining('toggles click-through'), findsNothing);
  });
}
