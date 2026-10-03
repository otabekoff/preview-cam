/// A video capture device: a physical webcam or a virtual camera such as
/// "Camera (NVIDIA Broadcast)" or "OBS Virtual Camera". The application
/// treats both the same way.
class CameraDevice {
  const CameraDevice({required this.id, required this.name});

  /// Rebuilds a device from the string stored in settings (see [key]).
  factory CameraDevice.fromKey(String key) {
    final split = key.lastIndexOf(' <');
    if (split <= 0 || !key.endsWith('>')) {
      return CameraDevice(id: key, name: key);
    }
    return CameraDevice(
      id: key.substring(split + 2, key.length - 1),
      name: key.substring(0, split),
    );
  }

  /// System identifier (the DirectShow moniker name on Windows).
  final String id;

  /// The friendly name shown to the user.
  final String name;

  /// What is persisted as the selected camera: `name <id>`. Keeping the name
  /// lets the camera be found again when its identifier changes (a USB
  /// camera moved to another port) and be named while it is unplugged.
  String get key => '$name <$id>';

  static String nameOf(String key) => CameraDevice.fromKey(key).name;

  @override
  bool operator ==(Object other) => other is CameraDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
