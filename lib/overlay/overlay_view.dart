import 'dart:async';

import 'package:flutter/material.dart';

import '../camera/camera_view.dart';
import '../l10n/app_strings.dart';
import '../services/hotkey_service.dart';
import '../settings/settings_model.dart';
import 'overlay_controller.dart';
import 'overlay_controls.dart';

/// How long the hover controls stay after the mouse leaves.
const Duration kControlsHideDelay = Duration(milliseconds: 700);

/// The whole content of the overlay window: the camera clipped to the chosen
/// shape, with controls, toast and first-launch hint layered on top.
///
/// Everything outside the shape is left unpainted, which the native window
/// shows as real transparency.
class OverlayView extends StatefulWidget {
  const OverlayView({super.key, required this.controller});

  final OverlayController controller;

  @override
  State<OverlayView> createState() => _OverlayViewState();
}

class _OverlayViewState extends State<OverlayView> {
  bool _hovering = false;
  Timer? _hideTimer;

  OverlayController get _controller => widget.controller;

  void _onEnter() {
    _hideTimer?.cancel();
    if (!_hovering) setState(() => _hovering = true);
  }

  void _onExit() {
    _hideTimer?.cancel();
    _hideTimer = Timer(kControlsHideDelay, () {
      if (mounted) setState(() => _hovering = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_controller.settings, _controller.camera]),
      builder: (context, _) {
        final settings = _controller.settings.value;
        final circle = settings.shape == OverlayShape.circle;
        return MouseRegion(
          onEnter: (_) => _onEnter(),
          onHover: (_) => _onEnter(),
          onExit: (_) => _onExit(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // The drag is handed to Windows, which moves the window natively.
            onPanStart: (_) => _controller.startDrag(),
            child: _ShapeClip(
              shape: settings.shape,
              radius: settings.cornerRadius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildFeed(settings),
                  Align(
                    alignment: Alignment(0, circle ? 0.72 : 1),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: OverlayControls(
                        strings: _controller.strings,
                        visible: _hovering && settings.hoverControls,
                        mirrored: settings.mirror,
                        pinned: settings.alwaysOnTop,
                        onSettings: _controller.openSettings,
                        onMirror: _controller.toggleMirror,
                        onShape: _controller.cycleShape,
                        onPin: _controller.toggleAlwaysOnTop,
                        onClose: _controller.hide,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<String?>(
                    valueListenable: _controller.toast,
                    builder: (context, message, _) => _Toast(message: message),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: _controller.hint,
                    builder: (context, show, _) => show
                        ? _Hint(
                            strings: _controller.strings,
                            clickThrough: settings
                                .hotkeys[HotkeyAction.toggleClickThrough],
                            onDismiss: _controller.dismissHint,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeed(AppSettings settings) {
    final camera = _controller.camera;
    final session = camera.session;
    if (session != null) {
      final view = CameraView(
        textureId: session.textureId,
        previewSize: Size(session.width.toDouble(), session.height.toDouble()),
        mirror: settings.mirror,
      );
      // A camera that supplies its own transparency (background removal) is
      // drawn with nothing behind it, so the desktop shows through.
      return session.hasAlpha && settings.cameraTransparency
          ? view
          : ColoredBox(color: Colors.black, child: view);
    }
    return CameraStatusView(
      status: camera.status,
      strings: _controller.strings,
      cameraLabel: camera.active?.name,
      detail: camera.detail,
      onRetry: _controller.retryCamera,
      onOpenSettings: _controller.openSettings,
      onOpenPrivacySettings: _controller.openPrivacySettings,
    );
  }
}

/// Clips its child to the overlay shape with anti-aliased edges.
class _ShapeClip extends StatelessWidget {
  const _ShapeClip({
    required this.shape,
    required this.radius,
    required this.child,
  });

  final OverlayShape shape;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (shape == OverlayShape.circle) return ClipOval(child: child);
    if (shape.hasCornerRadius && radius > 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      );
    }
    return child;
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: text == null ? 0 : 1,
        duration: const Duration(milliseconds: 150),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: DecoratedBox(
                decoration: const ShapeDecoration(
                  color: Color(0xCC000000),
                  shape: StadiumBorder(),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Text(
                    text ?? '',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({
    required this.strings,
    required this.clickThrough,
    required this.onDismiss,
  });

  final AppStrings strings;
  final Hotkey? clickThrough;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.white, fontSize: 12, height: 1.35);
    return GestureDetector(
      onTap: onDismiss,
      child: ColoredBox(
        color: const Color(0xD9000000),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(strings.hintMove, style: style),
                Text(strings.hintHover, style: style),
                Text(
                  clickThrough == null
                      ? strings.hintClickThroughTray
                      : strings.hintClickThrough(clickThrough!.label),
                  style: style,
                ),
                const SizedBox(height: 6),
                Text(
                  strings.hintDismiss,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
