#ifndef RUNNER_CAMERA_CAPTURE_H_
#define RUNNER_CAMERA_CAPTURE_H_

#include <windows.h>

#include <dshow.h>
#include <flutter_texture_registrar.h>

#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "vcam_output.h"

struct ISampleGrabber;

// Camera capture through DirectShow, rendered into a Flutter texture.
//
// DirectShow is used (rather than Media Foundation) because it is the one
// API through which every kind of camera on Windows is reachable: physical
// webcams, and virtual cameras that exist only as DirectShow filters such as
// "Camera (NVIDIA Broadcast)" and "OBS Virtual Camera".
//
// Pipeline (all inside this process, nothing device-global is changed):
//
//   camera filter -> Sample Grabber -> Null Renderer
//                         |
//                         +-> convert to RGBA -> Flutter pixel-buffer texture
//
// The camera's native pixel format is requested where this class can convert
// it itself (ARGB32, RGB32, RGB24, NV12, YUY2, I420); anything else, such as
// MJPEG, is decoded to RGB32 by DirectShow's own decoders. ARGB32 sources
// keep their alpha channel, so a camera that removes the background (NVIDIA
// Broadcast) shows up with a transparent background.
//
// Threading: the filter graph lives on a private worker thread so opening a
// slow USB camera never blocks the UI. Frames arrive on DirectShow's
// streaming thread. Completion callbacks and |on_error| always run on the
// platform (window) thread: results are posted to |notify_window| as
// |notify_message| and dispatched by HandleNotify().
class CameraCapture {
 public:
  struct Device {
    std::string id;    // DirectShow moniker display name (stable identifier)
    std::string name;  // Friendly name
  };

  struct OpenResult {
    bool ok = false;
    // "accessDenied", "inUse", "notFound" or "failed" when !ok.
    std::string error_code;
    std::string error_message;
    int width = 0;
    int height = 0;
    double fps = 0;
    // The source delivers a meaningful alpha channel (ARGB32).
    bool has_alpha = false;
    std::string format;
  };

  CameraCapture(FlutterDesktopTextureRegistrarRef registrar,
                HWND notify_window,
                UINT notify_message);
  ~CameraCapture();

  CameraCapture(const CameraCapture&) = delete;
  CameraCapture& operator=(const CameraCapture&) = delete;

  // The texture that shows the camera; constant for the process lifetime.
  int64_t texture_id() const { return texture_id_; }

  // Enumerates video capture devices. Does not open any of them.
  static std::vector<Device> ListDevices();

  // Opens |device_id| with the mode closest to |target_height| (0 = largest)
  // and |target_fps| (0 = automatic). Replaces any camera already open.
  void Open(const std::string& device_id,
            int target_height,
            int target_fps,
            std::function<void(const OpenResult&)> done);

  // Stops capturing and releases the device.
  void Close(std::function<void()> done);

  // Configures the virtual camera output (see VcamOutput).
  void SetOutput(const VcamOutput::Config& config) { vcam_.SetConfig(config); }

  // Must be called by the window procedure for |notify_message|.
  void HandleNotify(WPARAM wparam, LPARAM lparam);

  // The running camera stopped unexpectedly (unplugged, driver error).
  // |code| uses the same values as OpenResult::error_code.
  std::function<void(const std::string& code, const std::string& message)>
      on_error;

 private:
  class GrabberCallback;
  enum class PixelFormat { kARGB32, kRGB32, kRGB24, kNV12, kYUY2, kI420 };

  void WorkerMain();
  void Post(std::function<void()> task);
  void RunOnPlatformThread(std::function<void()> task);

  // Worker-thread only.
  OpenResult OpenGraph(const std::string& device_id,
                       int target_height,
                       int target_fps);
  void CloseGraph();
  void DrainGraphEvents();

  // Streaming thread.
  void OnFrame(const BYTE* data, long length);

  static const FlutterDesktopPixelBuffer* CopyPixelBuffer(size_t width,
                                                          size_t height,
                                                          void* user_data);

  FlutterDesktopTextureRegistrarRef registrar_;
  HWND notify_window_;
  UINT notify_message_;
  int64_t texture_id_ = -1;

  // Worker thread and its task queue.
  std::thread worker_;
  std::mutex queue_mutex_;
  std::condition_variable queue_ready_;
  std::deque<std::function<void()>> queue_;
  bool quit_ = false;

  // Filter graph (worker thread only).
  IGraphBuilder* graph_ = nullptr;
  IMediaControl* control_ = nullptr;
  IMediaEventEx* events_ = nullptr;
  ISampleGrabber* grabber_ = nullptr;
  GrabberCallback* callback_ = nullptr;

  // Format of the frames the grabber receives; set before the graph runs.
  PixelFormat format_ = PixelFormat::kRGB32;
  int width_ = 0;
  int height_ = 0;
  bool bottom_up_ = false;

  // Three RGBA buffers so no thread ever waits for another:
  //   back_  - being written by the streaming thread
  //   ready_ - newest complete frame, guarded by frame_mutex_
  //   front_ - the frame Flutter is reading (raster thread only)
  struct Frame {
    std::vector<uint8_t> pixels;
    int width = 0;
    int height = 0;
  };
  Frame back_;
  Frame ready_;
  Frame front_;
  bool ready_is_new_ = false;
  std::mutex frame_mutex_;
  FlutterDesktopPixelBuffer pixel_buffer_ = {};

  // Publishes the finished picture as the "Preview Cam" virtual camera.
  VcamOutput vcam_;
};

#endif  // RUNNER_CAMERA_CAPTURE_H_
