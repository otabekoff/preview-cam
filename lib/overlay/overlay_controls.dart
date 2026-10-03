import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';

/// The small control strip that fades in over the camera while the mouse is
/// on the overlay. It floats above the picture and takes no layout space.
class OverlayControls extends StatelessWidget {
  const OverlayControls({
    super.key,
    required this.strings,
    required this.visible,
    required this.mirrored,
    required this.pinned,
    required this.onSettings,
    required this.onMirror,
    required this.onShape,
    required this.onPin,
    required this.onClose,
  });

  final AppStrings strings;
  final bool visible;
  final bool mirrored;
  final bool pinned;
  final VoidCallback onSettings;
  final VoidCallback onMirror;
  final VoidCallback onShape;
  final VoidCallback onPin;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Material(
            color: const Color(0xB3000000),
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ControlButton(
                    icon: Icons.settings_outlined,
                    label: strings.settings,
                    onPressed: onSettings,
                  ),
                  _ControlButton(
                    icon: Icons.flip,
                    label: strings.mirror,
                    active: mirrored,
                    onPressed: onMirror,
                  ),
                  _ControlButton(
                    icon: Icons.category_outlined,
                    label: strings.shape,
                    onPressed: onShape,
                  ),
                  _ControlButton(
                    icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    label: strings.alwaysOnTop,
                    active: pinned,
                    onPressed: onPin,
                  ),
                  _ControlButton(
                    icon: Icons.close,
                    label: strings.hideToTray,
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onPressed,
        radius: 16,
        child: SizedBox(
          width: 30,
          height: 28,
          child: Icon(
            icon,
            size: 17,
            color: active ? const Color(0xFF8AB4F8) : Colors.white,
          ),
        ),
      ),
    );
  }
}
