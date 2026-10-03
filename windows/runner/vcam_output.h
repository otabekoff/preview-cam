#ifndef RUNNER_VCAM_OUTPUT_H_
#define RUNNER_VCAM_OUTPUT_H_

#include <windows.h>

#include <atomic>
#include <cstdint>
#include <mutex>

#include "../vcam/vcam_protocol.h"

// Producer side of the "Preview Cam" virtual camera.
//
// Takes the camera frames the overlay shows and publishes the *finished*
// picture for other applications: cropped to the overlay's aspect ratio,
// mirrored if mirroring is on, and masked to the overlay's shape with
// anti-aliased, genuinely transparent edges. The result goes into shared
// memory, from where the filter DLL (windows/vcam) serves it to OBS and
// other camera consumers. See vcam_protocol.h for the contract.
//
// Composition is done here rather than by reading back what Flutter drew:
// it needs no GPU read-back, leaves the hover controls and toasts out of the
// recording, and costs nothing unless a consumer is actually connected.
class VcamOutput {
 public:
  enum class Shape { kRectangle = 0, kRounded = 1, kCircle = 2 };

  struct Config {
    bool enabled = false;
    bool mirror = true;
    // Width / height of the overlay.
    double aspect = 16.0 / 9.0;
    Shape shape = Shape::kRectangle;
    // Corner radius as a fraction of the overlay's height.
    double radius = 0;
  };

  VcamOutput();
  ~VcamOutput();

  VcamOutput(const VcamOutput&) = delete;
  VcamOutput& operator=(const VcamOutput&) = delete;

  // Adds / removes the camera device for the current user (HKCU, no
  // administrator rights). Register returns false if the filter DLL is
  // missing or the registry could not be written.
  static bool Register();
  static void Unregister();

  void SetConfig(const Config& config);

  bool enabled() const { return enabled_; }

  // Publishes one camera frame. |rgba| is premultiplied RGBA, top-down.
  // Cheap while no consumer is connected: only the advertised size is kept
  // up to date; pixels are composed only when someone is streaming.
  void Publish(const uint8_t* rgba, int width, int height);

  // Marks the feed as stopped; consumers then receive transparent frames.
  void SetInactive();

 private:
  bool EnsureMapping();

  std::mutex config_mutex_;
  Config config_;
  std::atomic<bool> enabled_{false};

  HANDLE mapping_ = nullptr;
  HANDLE mutex_ = nullptr;
  VcamHeader* header_ = nullptr;
};

#endif  // RUNNER_VCAM_OUTPUT_H_
