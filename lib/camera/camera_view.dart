import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import 'camera_controller.dart';

/// The live camera texture, scaled to cover the available space while
/// keeping the camera's aspect ratio (excess is cropped, never stretched).
class CameraView extends StatelessWidget {
  const CameraView({
    super.key,
    required this.textureId,
    required this.previewSize,
    required this.mirror,
  });

  final int textureId;
  final Size previewSize;

  /// Whether the user sees themselves as in a mirror.
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    // Mirroring is done here, while compositing, so it only ever affects
    // this application's preview.
    Widget texture = Texture(textureId: textureId);
    if (mirror) {
      texture = Transform.flip(flipX: true, child: texture);
    }
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: previewSize.width,
          height: previewSize.height,
          child: texture,
        ),
      ),
    );
  }
}

/// Explains why there is no picture and offers a way out, so the overlay is
/// never an unexplained empty window.
class CameraStatusView extends StatelessWidget {
  const CameraStatusView({
    super.key,
    required this.status,
    required this.strings,
    this.cameraLabel,
    this.detail,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onOpenPrivacySettings,
  });

  final CameraStatus status;
  final AppStrings strings;
  final String? cameraLabel;
  final String? detail;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenPrivacySettings;

  @override
  Widget build(BuildContext context) {
    final t = strings;
    final camera = cameraLabel ?? t.theCamera;
    final (IconData icon, String title, String message) = switch (status) {
      CameraStatus.idle ||
      CameraStatus.starting ||
      CameraStatus.running => (Icons.videocam_outlined, t.cameraStarting, ''),
      CameraStatus.noCameras => (
        Icons.videocam_off_outlined,
        t.noCameraTitle,
        t.noCameraMessage,
      ),
      CameraStatus.disconnected => (
        Icons.usb_off_outlined,
        t.disconnectedTitle,
        t.disconnectedMessage(camera),
      ),
      CameraStatus.permissionDenied => (
        Icons.lock_outline,
        t.permissionTitle,
        t.permissionMessage,
      ),
      CameraStatus.inUse => (
        Icons.videocam_off_outlined,
        t.inUseTitle,
        t.inUseMessage(camera),
      ),
      CameraStatus.unavailable => (
        Icons.videocam_off_outlined,
        t.unavailableTitle,
        t.unavailableMessage(camera),
      ),
    };
    final waiting =
        status == CameraStatus.idle ||
        status == CameraStatus.starting ||
        status == CameraStatus.running;

    return ColoredBox(
      color: const Color(0xFF14161A),
      child: Padding(
        padding: const EdgeInsets.all(10),
        // Scales the whole message down in very small overlays.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white70, size: 26),
                const SizedBox(height: 6),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (message.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
                if (!waiting) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: [
                      if (status == CameraStatus.permissionDenied)
                        _Action(t.privacySettings, onOpenPrivacySettings),
                      _Action(t.retry, onRetry),
                      _Action(t.settings, onOpenSettings),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action(this.label, this.onPressed);

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF8AB4F8),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text(label),
    );
  }
}
