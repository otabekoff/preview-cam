#include "camera_capture.h"

#include <flutter_plugin_registrar.h>
#include <wrl/client.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <tuple>

#include "utils.h"

using Microsoft::WRL::ComPtr;

// --- Sample Grabber ---------------------------------------------------------
// The Sample Grabber and Null Renderer filters ship with Windows (qedit.dll)
// but their header, qedit.h, is no longer part of the Windows SDK, so the
// interfaces are declared here.

namespace {

const CLSID kClsidSampleGrabber = {
    0xC1F400A0, 0x3F08, 0x11d3, {0x9F, 0x0B, 0x00, 0x60, 0x08, 0x03, 0x9E, 0x37}};
const CLSID kClsidNullRenderer = {
    0xC1F400A4, 0x3F08, 0x11d3, {0x9F, 0x0B, 0x00, 0x60, 0x08, 0x03, 0x9E, 0x37}};
const IID kIidSampleGrabber = {
    0x6B652FFF, 0x11FE, 0x4fce, {0x92, 0xAD, 0x02, 0x66, 0xB5, 0xD7, 0xC7, 0x8F}};
const IID kIidSampleGrabberCB = {
    0x0579154A, 0x2B53, 0x4994, {0xB0, 0xD0, 0xE7, 0x73, 0x14, 0x8E, 0xFF, 0x85}};
// FOURCC 'I420'; not defined in uuids.h.
const GUID kSubtypeI420 = {
    0x30323449, 0x0000, 0x0010, {0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71}};

// lParam of graph-event notifications; wParam 1 marks a posted task instead.
constexpr LONG_PTR kGraphEventParam = 0x43414D;
constexpr WPARAM kTaskParam = 1;

}  // namespace

struct ISampleGrabberCB : public IUnknown {
  virtual HRESULT STDMETHODCALLTYPE SampleCB(double time,
                                             IMediaSample* sample) = 0;
  virtual HRESULT STDMETHODCALLTYPE BufferCB(double time,
                                             BYTE* buffer,
                                             long length) = 0;
};

struct ISampleGrabber : public IUnknown {
  virtual HRESULT STDMETHODCALLTYPE SetOneShot(BOOL one_shot) = 0;
  virtual HRESULT STDMETHODCALLTYPE SetMediaType(const AM_MEDIA_TYPE* type) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetConnectedMediaType(
      AM_MEDIA_TYPE* type) = 0;
  virtual HRESULT STDMETHODCALLTYPE SetBufferSamples(BOOL buffer) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetCurrentBuffer(long* size,
                                                     long* buffer) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetCurrentSample(IMediaSample** sample) = 0;
  virtual HRESULT STDMETHODCALLTYPE SetCallback(ISampleGrabberCB* callback,
                                                long which_method) = 0;
};

// Receives every frame on DirectShow's streaming thread. Owned by
// CameraCapture, so reference counting is a no-op.
class CameraCapture::GrabberCallback : public ISampleGrabberCB {
 public:
  explicit GrabberCallback(CameraCapture* owner) : owner_(owner) {}

  STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
    if (iid == IID_IUnknown || iid == kIidSampleGrabberCB) {
      *object = static_cast<ISampleGrabberCB*>(this);
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }
  STDMETHODIMP_(ULONG) AddRef() override { return 2; }
  STDMETHODIMP_(ULONG) Release() override { return 1; }

  STDMETHODIMP SampleCB(double, IMediaSample*) override { return S_OK; }
  STDMETHODIMP BufferCB(double, BYTE* buffer, long length) override {
    owner_->OnFrame(buffer, length);
    return S_OK;
  }

 private:
  CameraCapture* owner_;
};

namespace {

void FreeMediaType(AM_MEDIA_TYPE* type) {
  if (!type) {
    return;
  }
  if (type->cbFormat) {
    CoTaskMemFree(type->pbFormat);
  }
  if (type->pUnk) {
    type->pUnk->Release();
  }
  CoTaskMemFree(type);
}

void ClearMediaType(AM_MEDIA_TYPE& type) {
  if (type.cbFormat) {
    CoTaskMemFree(type.pbFormat);
  }
  if (type.pUnk) {
    type.pUnk->Release();
  }
  type = {};
}

// Lower is better. Formats this class converts itself come first, with the
// alpha-carrying one on top; 6 means "let DirectShow decode it to RGB32".
int SubtypeRank(const GUID& subtype) {
  if (subtype == MEDIASUBTYPE_ARGB32) return 0;
  if (subtype == MEDIASUBTYPE_RGB32) return 1;
  if (subtype == MEDIASUBTYPE_NV12) return 2;
  if (subtype == MEDIASUBTYPE_YUY2) return 3;
  if (subtype == kSubtypeI420 || subtype == MEDIASUBTYPE_IYUV) return 4;
  if (subtype == MEDIASUBTYPE_RGB24) return 5;
  return 6;
}

const char* SubtypeName(const GUID& subtype) {
  switch (SubtypeRank(subtype)) {
    case 0:
      return "ARGB32";
    case 1:
      return "RGB32";
    case 2:
      return "NV12";
    case 3:
      return "YUY2";
    case 4:
      return "I420";
    case 5:
      return "RGB24";
    default:
      return "decoded";
  }
}

std::string ErrorCode(HRESULT hr) {
  if (hr == E_ACCESSDENIED) {
    return "accessDenied";
  }
  // What capture drivers return when another application holds the device.
  // The first two are MF_E_HW_MFT_FAILED_START_STREAMING and
  // MF_E_VIDEO_RECORDING_DEVICE_PREEMPTED, raised by the Windows camera
  // frame server.
  if (hr == static_cast<HRESULT>(0xC00D3704) ||
      hr == static_cast<HRESULT>(0xC00D3EA3) ||
      hr == HRESULT_FROM_WIN32(ERROR_NO_SYSTEM_RESOURCES) ||
      hr == HRESULT_FROM_WIN32(ERROR_SHARING_VIOLATION) ||
      hr == HRESULT_FROM_WIN32(ERROR_BUSY) ||
      hr == HRESULT_FROM_WIN32(ERROR_DEVICE_IN_USE)) {
    return "inUse";
  }
  return "failed";
}

std::string Describe(const char* stage, HRESULT hr) {
  char text[96];
  snprintf(text, sizeof(text), "%s (0x%08lX)", stage,
           static_cast<unsigned long>(hr));
  return text;
}

std::wstring MonikerId(IMoniker* moniker) {
  LPOLESTR display = nullptr;
  if (FAILED(moniker->GetDisplayName(nullptr, nullptr, &display)) || !display) {
    return std::wstring();
  }
  std::wstring id(display);
  CoTaskMemFree(display);
  return id;
}

template <typename Visitor>
void ForEachDevice(Visitor visit) {
  ComPtr<ICreateDevEnum> enumerator;
  if (FAILED(CoCreateInstance(CLSID_SystemDeviceEnum, nullptr,
                              CLSCTX_INPROC_SERVER,
                              IID_PPV_ARGS(&enumerator)))) {
    return;
  }
  ComPtr<IEnumMoniker> monikers;
  // S_FALSE (and a null enumerator) means the category is empty.
  if (enumerator->CreateClassEnumerator(CLSID_VideoInputDeviceCategory,
                                        &monikers, 0) != S_OK) {
    return;
  }
  ComPtr<IMoniker> moniker;
  while (monikers->Next(1, moniker.ReleaseAndGetAddressOf(), nullptr) == S_OK) {
    if (!visit(moniker.Get())) {
      break;
    }
  }
}

// The pin that delivers the live video (as opposed to e.g. a still pin).
ComPtr<IPin> FindCapturePin(IBaseFilter* filter) {
  ComPtr<IEnumPins> pins;
  ComPtr<IPin> fallback;
  if (FAILED(filter->EnumPins(&pins))) {
    return fallback;
  }
  ComPtr<IPin> pin;
  while (pins->Next(1, pin.ReleaseAndGetAddressOf(), nullptr) == S_OK) {
    PIN_DIRECTION direction;
    if (FAILED(pin->QueryDirection(&direction)) || direction != PINDIR_OUTPUT) {
      continue;
    }
    if (!fallback) {
      fallback = pin;
    }
    ComPtr<IKsPropertySet> properties;
    GUID category{};
    DWORD returned = 0;
    if (SUCCEEDED(pin.As(&properties)) &&
        SUCCEEDED(properties->Get(AMPROPSETID_Pin, AMPROPERTY_PIN_CATEGORY,
                                  nullptr, 0, &category, sizeof(category),
                                  &returned)) &&
        category == PIN_CATEGORY_CAPTURE) {
      return pin;
    }
  }
  return fallback;
}

ComPtr<IPin> FindPin(IBaseFilter* filter, PIN_DIRECTION wanted) {
  ComPtr<IEnumPins> pins;
  ComPtr<IPin> pin;
  if (FAILED(filter->EnumPins(&pins))) {
    return pin;
  }
  while (pins->Next(1, pin.ReleaseAndGetAddressOf(), nullptr) == S_OK) {
    PIN_DIRECTION direction;
    if (SUCCEEDED(pin->QueryDirection(&direction)) && direction == wanted) {
      return pin;
    }
  }
  return nullptr;
}

// Asks the camera for the mode closest to the requested height and frame
// rate. Returns the subtype that was selected (GUID_NULL if the device has no
// configurable formats, in which case its default is used).
GUID SelectMode(IPin* pin, int target_height, int target_fps) {
  ComPtr<IAMStreamConfig> config;
  if (FAILED(pin->QueryInterface(IID_PPV_ARGS(&config)))) {
    return GUID_NULL;
  }
  int count = 0;
  int size = 0;
  if (FAILED(config->GetNumberOfCapabilities(&count, &size)) ||
      size != sizeof(VIDEO_STREAM_CONFIG_CAPS)) {
    return GUID_NULL;
  }

  // Prefer the aspect ratio the device is currently set to.
  double current_aspect = 0;
  AM_MEDIA_TYPE* current = nullptr;
  if (SUCCEEDED(config->GetFormat(&current)) && current) {
    if (current->formattype == FORMAT_VideoInfo && current->pbFormat) {
      const auto& header =
          reinterpret_cast<VIDEOINFOHEADER*>(current->pbFormat)->bmiHeader;
      if (header.biHeight != 0) {
        current_aspect =
            static_cast<double>(header.biWidth) / std::abs(header.biHeight);
      }
    }
    FreeMediaType(current);
  }

  const double wanted_fps = target_fps > 0 ? target_fps : 30.0;
  using Score = std::tuple<int, double, int, int, int>;
  AM_MEDIA_TYPE* best = nullptr;
  Score best_score;
  REFERENCE_TIME best_interval = 0;

  for (int i = 0; i < count; ++i) {
    VIDEO_STREAM_CONFIG_CAPS caps{};
    AM_MEDIA_TYPE* type = nullptr;
    if (FAILED(config->GetStreamCaps(i, &type, reinterpret_cast<BYTE*>(&caps))) ||
        !type) {
      continue;
    }
    // The Sample Grabber only connects with VIDEOINFOHEADER formats.
    if (type->formattype != FORMAT_VideoInfo || !type->pbFormat) {
      FreeMediaType(type);
      continue;
    }
    auto* info = reinterpret_cast<VIDEOINFOHEADER*>(type->pbFormat);
    const int width = info->bmiHeader.biWidth;
    const int height = std::abs(info->bmiHeader.biHeight);
    if (width <= 0 || height <= 0) {
      FreeMediaType(type);
      continue;
    }

    // Frame interval (100ns units) closest to the wanted rate that this mode
    // supports.
    REFERENCE_TIME interval = static_cast<REFERENCE_TIME>(1e7 / wanted_fps);
    const REFERENCE_TIME shortest = caps.MinFrameInterval;
    const REFERENCE_TIME longest = caps.MaxFrameInterval;
    if (shortest > 0 && longest >= shortest) {
      interval = std::clamp(interval, shortest, longest);
    } else if (info->AvgTimePerFrame > 0) {
      interval = info->AvgTimePerFrame;
    }
    const double fps = 1e7 / static_cast<double>(interval);

    int height_penalty;
    if (target_height <= 0) {
      height_penalty = -height;
    } else if (height <= target_height) {
      height_penalty = target_height - height;
    } else {
      height_penalty = 100000 + height - target_height;
    }
    const double aspect = static_cast<double>(width) / height;
    const int aspect_penalty =
        current_aspect > 0 && std::abs(aspect - current_aspect) > 0.02 ? 1 : 0;
    const Score score(height_penalty, std::abs(fps - wanted_fps),
                      aspect_penalty, SubtypeRank(type->subtype), -width);
    if (!best || score < best_score) {
      FreeMediaType(best);
      best = type;
      best_score = score;
      best_interval = interval;
    } else {
      FreeMediaType(type);
    }
  }

  if (!best) {
    return GUID_NULL;
  }
  reinterpret_cast<VIDEOINFOHEADER*>(best->pbFormat)->AvgTimePerFrame =
      best_interval;
  const GUID subtype = best->subtype;
  // Not fatal if refused: the device then keeps its current mode.
  config->SetFormat(best);
  FreeMediaType(best);
  return subtype;
}

inline uint8_t Clip(int value) {
  return static_cast<uint8_t>(value < 0 ? 0 : (value > 255 ? 255 : value));
}

// Limited-range YUV to RGBA. BT.709 for HD sources, BT.601 otherwise.
struct YuvMatrix {
  int rv, gu, gv, bu;
  explicit YuvMatrix(int height) {
    if (height > 576) {
      rv = 459, gu = 55, gv = 136, bu = 541;
    } else {
      rv = 409, gu = 100, gv = 208, bu = 516;
    }
  }
  inline void Write(uint8_t* out, int y, int u, int v) const {
    const int c = 298 * (y - 16) + 128;
    const int d = u - 128;
    const int e = v - 128;
    out[0] = Clip((c + rv * e) >> 8);
    out[1] = Clip((c - gu * d - gv * e) >> 8);
    out[2] = Clip((c + bu * d) >> 8);
    out[3] = 255;
  }
};

}  // namespace

CameraCapture::CameraCapture(FlutterDesktopTextureRegistrarRef registrar,
                             HWND notify_window,
                             UINT notify_message)
    : registrar_(registrar),
      notify_window_(notify_window),
      notify_message_(notify_message) {
  FlutterDesktopTextureInfo info{};
  info.type = kFlutterDesktopPixelBufferTexture;
  info.pixel_buffer_config.callback = CameraCapture::CopyPixelBuffer;
  info.pixel_buffer_config.user_data = this;
  texture_id_ =
      FlutterDesktopTextureRegistrarRegisterExternalTexture(registrar_, &info);

  callback_ = new GrabberCallback(this);
  worker_ = std::thread([this]() { WorkerMain(); });
}

CameraCapture::~CameraCapture() {
  Post([this]() { CloseGraph(); });
  {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    quit_ = true;
  }
  queue_ready_.notify_all();
  if (worker_.joinable()) {
    worker_.join();
  }
  if (texture_id_ >= 0) {
    FlutterDesktopTextureRegistrarUnregisterExternalTexture(
        registrar_, texture_id_, nullptr, nullptr);
  }
  delete callback_;
}

// static
std::vector<CameraCapture::Device> CameraCapture::ListDevices() {
  std::vector<Device> devices;
  ForEachDevice([&devices](IMoniker* moniker) {
    ComPtr<IPropertyBag> properties;
    if (FAILED(moniker->BindToStorage(nullptr, nullptr,
                                      IID_PPV_ARGS(&properties)))) {
      return true;
    }
    VARIANT name;
    VariantInit(&name);
    if (SUCCEEDED(properties->Read(L"FriendlyName", &name, nullptr)) &&
        name.vt == VT_BSTR) {
      Device device;
      device.name = Utf8FromUtf16(name.bstrVal);
      const std::wstring id = MonikerId(moniker);
      device.id = Utf8FromUtf16(id.c_str());
      // The application's own virtual camera is an output, not a source.
      const bool own = id.find(VCAM_CLSID_STRING) != std::wstring::npos;
      if (!device.id.empty() && !own) {
        devices.push_back(std::move(device));
      }
    }
    VariantClear(&name);
    return true;
  });
  return devices;
}

void CameraCapture::Open(const std::string& device_id,
                         int target_height,
                         int target_fps,
                         std::function<void(const OpenResult&)> done) {
  Post([this, device_id, target_height, target_fps, done]() {
    const OpenResult result = OpenGraph(device_id, target_height, target_fps);
    if (!result.ok) {
      CloseGraph();
    }
    RunOnPlatformThread([done, result]() { done(result); });
  });
}

void CameraCapture::Close(std::function<void()> done) {
  Post([this, done]() {
    CloseGraph();
    RunOnPlatformThread(done);
  });
}

void CameraCapture::HandleNotify(WPARAM wparam, LPARAM lparam) {
  if (wparam == kTaskParam) {
    auto* task = reinterpret_cast<std::function<void()>*>(lparam);
    (*task)();
    delete task;
  } else if (lparam == kGraphEventParam) {
    Post([this]() { DrainGraphEvents(); });
  }
}

void CameraCapture::Post(std::function<void()> task) {
  {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    queue_.push_back(std::move(task));
  }
  queue_ready_.notify_one();
}

void CameraCapture::RunOnPlatformThread(std::function<void()> task) {
  auto* posted = new std::function<void()>(std::move(task));
  if (!PostMessage(notify_window_, notify_message_, kTaskParam,
                   reinterpret_cast<LPARAM>(posted))) {
    delete posted;
  }
}

void CameraCapture::WorkerMain() {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  for (;;) {
    std::function<void()> task;
    {
      std::unique_lock<std::mutex> lock(queue_mutex_);
      queue_ready_.wait(lock, [this]() { return quit_ || !queue_.empty(); });
      if (queue_.empty()) {
        break;  // quit_ and nothing left to do.
      }
      task = std::move(queue_.front());
      queue_.pop_front();
    }
    task();
  }
  CoUninitialize();
}

CameraCapture::OpenResult CameraCapture::OpenGraph(const std::string& device_id,
                                                   int target_height,
                                                   int target_fps) {
  CloseGraph();
  OpenResult result;
  auto fail = [&result](const char* stage, HRESULT hr) {
    result.ok = false;
    result.error_code = ErrorCode(hr);
    result.error_message = Describe(stage, hr);
    return result;
  };

  // Locate the device by its moniker name.
  ComPtr<IMoniker> device;
  ForEachDevice([&](IMoniker* moniker) {
    if (Utf8FromUtf16(MonikerId(moniker).c_str()) == device_id) {
      device = moniker;
      return false;
    }
    return true;
  });
  if (!device) {
    result.error_code = "notFound";
    result.error_message = "The camera is not connected.";
    return result;
  }

  ComPtr<IBaseFilter> source;
  HRESULT hr = device->BindToObject(nullptr, nullptr, IID_PPV_ARGS(&source));
  if (FAILED(hr)) {
    return fail("Could not open the camera", hr);
  }

  hr = CoCreateInstance(CLSID_FilterGraph, nullptr, CLSCTX_INPROC_SERVER,
                        IID_PPV_ARGS(&graph_));
  if (FAILED(hr)) {
    return fail("Could not create the capture graph", hr);
  }
  graph_->AddFilter(source.Get(), L"Camera");

  ComPtr<IPin> capture_pin = FindCapturePin(source.Get());
  if (!capture_pin) {
    return fail("The camera has no video output", E_FAIL);
  }
  const GUID wanted_subtype =
      SelectMode(capture_pin.Get(), target_height, target_fps);

  ComPtr<IBaseFilter> grabber_filter;
  hr = CoCreateInstance(kClsidSampleGrabber, nullptr, CLSCTX_INPROC_SERVER,
                        IID_PPV_ARGS(&grabber_filter));
  if (SUCCEEDED(hr)) {
    hr = grabber_filter->QueryInterface(kIidSampleGrabber,
                                        reinterpret_cast<void**>(&grabber_));
  }
  ComPtr<IBaseFilter> renderer;
  if (SUCCEEDED(hr)) {
    hr = CoCreateInstance(kClsidNullRenderer, nullptr, CLSCTX_INPROC_SERVER,
                          IID_PPV_ARGS(&renderer));
  }
  if (FAILED(hr)) {
    return fail("DirectShow capture components are unavailable", hr);
  }
  graph_->AddFilter(grabber_filter.Get(), L"Grabber");
  graph_->AddFilter(renderer.Get(), L"Sink");

  ComPtr<IPin> grabber_in = FindPin(grabber_filter.Get(), PINDIR_INPUT);
  ComPtr<IPin> grabber_out = FindPin(grabber_filter.Get(), PINDIR_OUTPUT);
  ComPtr<IPin> renderer_in = FindPin(renderer.Get(), PINDIR_INPUT);

  // First choice: take the camera's own format and convert it here. If that
  // is not possible (MJPEG, H.264, ...), ask for RGB32 and let DirectShow
  // insert its decoders.
  AM_MEDIA_TYPE accept{};
  accept.majortype = MEDIATYPE_Video;
  hr = E_FAIL;
  if (wanted_subtype != GUID_NULL && SubtypeRank(wanted_subtype) < 6) {
    accept.subtype = wanted_subtype;
    grabber_->SetMediaType(&accept);
    hr = graph_->ConnectDirect(capture_pin.Get(), grabber_in.Get(), nullptr);
  }
  if (FAILED(hr)) {
    accept.subtype = MEDIASUBTYPE_RGB32;
    grabber_->SetMediaType(&accept);
    hr = graph_->Connect(capture_pin.Get(), grabber_in.Get());
  }
  if (FAILED(hr)) {
    return fail("The camera's video format is not supported", hr);
  }
  hr = graph_->ConnectDirect(grabber_out.Get(), renderer_in.Get(), nullptr);
  if (FAILED(hr)) {
    return fail("Could not build the capture graph", hr);
  }

  // What was actually negotiated.
  AM_MEDIA_TYPE connected{};
  hr = grabber_->GetConnectedMediaType(&connected);
  if (FAILED(hr) || connected.formattype != FORMAT_VideoInfo ||
      !connected.pbFormat) {
    ClearMediaType(connected);
    return fail("The camera's video format is not supported", E_FAIL);
  }
  const auto* info = reinterpret_cast<VIDEOINFOHEADER*>(connected.pbFormat);
  const int rank = SubtypeRank(connected.subtype);
  static const PixelFormat kFormats[] = {
      PixelFormat::kARGB32, PixelFormat::kRGB32, PixelFormat::kNV12,
      PixelFormat::kYUY2,   PixelFormat::kI420,  PixelFormat::kRGB24};
  if (rank >= 6) {
    ClearMediaType(connected);
    return fail("The camera's video format is not supported", E_FAIL);
  }
  format_ = kFormats[rank];
  width_ = info->bmiHeader.biWidth;
  height_ = std::abs(info->bmiHeader.biHeight);
  // Uncompressed RGB is stored bottom-up unless the height is negative.
  bottom_up_ = rank <= 1 || rank == 5 ? info->bmiHeader.biHeight > 0 : false;
  result.width = width_;
  result.height = height_;
  result.fps = info->AvgTimePerFrame > 0 ? 1e7 / info->AvgTimePerFrame : 0;
  result.has_alpha = format_ == PixelFormat::kARGB32;
  result.format = SubtypeName(connected.subtype);
  ClearMediaType(connected);
  if (width_ <= 0 || height_ <= 0) {
    return fail("The camera reported an invalid frame size", E_FAIL);
  }

  {
    // Drop whatever the previous camera left behind.
    std::lock_guard<std::mutex> lock(frame_mutex_);
    ready_.width = ready_.height = 0;
    ready_is_new_ = true;
  }

  grabber_->SetOneShot(FALSE);
  grabber_->SetBufferSamples(FALSE);
  grabber_->SetCallback(callback_, 1);  // 1 = BufferCB

  // No reference clock: deliver frames as soon as they arrive.
  ComPtr<IMediaFilter> media_filter;
  if (SUCCEEDED(graph_->QueryInterface(IID_PPV_ARGS(&media_filter)))) {
    media_filter->SetSyncSource(nullptr);
  }

  graph_->QueryInterface(IID_PPV_ARGS(&events_));
  if (events_) {
    events_->SetNotifyWindow(reinterpret_cast<OAHWND>(notify_window_),
                             notify_message_, kGraphEventParam);
  }

  hr = graph_->QueryInterface(IID_PPV_ARGS(&control_));
  if (SUCCEEDED(hr)) {
    hr = control_->Run();
  }
  if (hr == S_FALSE) {
    // Still starting; wait for the real outcome. This is where a camera that
    // is held by another application reports its failure.
    OAFilterState state = State_Stopped;
    hr = control_->GetState(5000, &state);
    if (hr == VFW_S_STATE_INTERMEDIATE || hr == VFW_S_CANT_CUE) {
      hr = S_OK;
    }
  }
  if (FAILED(hr)) {
    return fail("The camera could not be started", hr);
  }

  result.ok = true;
  return result;
}

void CameraCapture::CloseGraph() {
  if (control_) {
    control_->Stop();
  }
  vcam_.SetInactive();
  if (events_) {
    events_->SetNotifyWindow(0, 0, 0);
  }
  if (grabber_) {
    grabber_->SetCallback(nullptr, 1);
  }
  if (control_) {
    control_->Release();
    control_ = nullptr;
  }
  if (events_) {
    events_->Release();
    events_ = nullptr;
  }
  if (grabber_) {
    grabber_->Release();
    grabber_ = nullptr;
  }
  if (graph_) {
    // Releasing the graph releases its filters, which closes the device.
    graph_->Release();
    graph_ = nullptr;
  }
}

void CameraCapture::DrainGraphEvents() {
  if (!events_) {
    return;
  }
  bool lost = false;
  HRESULT reason = E_FAIL;
  long code = 0;
  LONG_PTR param1 = 0;
  LONG_PTR param2 = 0;
  while (events_ && SUCCEEDED(events_->GetEvent(&code, &param1, &param2, 0))) {
    if (code == EC_ERRORABORT) {
      lost = true;
      reason = static_cast<HRESULT>(param1);
    } else if (code == EC_DEVICE_LOST && param2 == 0) {
      // (param2 == 1 would announce the device coming back.)
      lost = true;
      reason = HRESULT_FROM_WIN32(ERROR_DEVICE_NOT_CONNECTED);
    }
    events_->FreeEventParams(code, param1, param2);
  }
  if (lost) {
    CloseGraph();
    const std::string error_code = ErrorCode(reason);
    const std::string message =
        Describe("The camera stopped delivering video", reason);
    RunOnPlatformThread([this, error_code, message]() {
      if (on_error) {
        on_error(error_code, message);
      }
    });
  }
}

void CameraCapture::OnFrame(const BYTE* data, long length) {
  const int width = width_;
  const int height = height_;
  const size_t pixels = static_cast<size_t>(width) * height;
  size_t required = 0;
  switch (format_) {
    case PixelFormat::kARGB32:
    case PixelFormat::kRGB32:
      required = pixels * 4;
      break;
    case PixelFormat::kRGB24:
      required = static_cast<size_t>((width * 3 + 3) & ~3) * height;
      break;
    case PixelFormat::kYUY2:
      required = pixels * 2;
      break;
    case PixelFormat::kNV12:
    case PixelFormat::kI420:
      required = pixels + 2 * (static_cast<size_t>(width / 2) * (height / 2));
      break;
  }
  if (!data || length < 0 || static_cast<size_t>(length) < required) {
    return;  // Truncated frame.
  }

  back_.pixels.resize(pixels * 4);
  back_.width = width;
  back_.height = height;
  uint8_t* out = back_.pixels.data();

  switch (format_) {
    case PixelFormat::kARGB32:
    case PixelFormat::kRGB32: {
      const bool alpha = format_ == PixelFormat::kARGB32;
      for (int y = 0; y < height; ++y) {
        const uint8_t* in =
            data + static_cast<size_t>(bottom_up_ ? height - 1 - y : y) *
                       width * 4;
        uint8_t* row = out + static_cast<size_t>(y) * width * 4;
        for (int x = 0; x < width; ++x, in += 4, row += 4) {
          // Source is BGRA; Flutter wants premultiplied RGBA.
          const unsigned a = alpha ? in[3] : 255;
          if (a == 255) {
            row[0] = in[2];
            row[1] = in[1];
            row[2] = in[0];
          } else if (a == 0) {
            row[0] = row[1] = row[2] = 0;
          } else {
            row[0] = static_cast<uint8_t>((in[2] * a + 127) / 255);
            row[1] = static_cast<uint8_t>((in[1] * a + 127) / 255);
            row[2] = static_cast<uint8_t>((in[0] * a + 127) / 255);
          }
          row[3] = static_cast<uint8_t>(a);
        }
      }
      break;
    }
    case PixelFormat::kRGB24: {
      const size_t stride = static_cast<size_t>((width * 3 + 3) & ~3);
      for (int y = 0; y < height; ++y) {
        const uint8_t* in = data + (bottom_up_ ? height - 1 - y : y) * stride;
        uint8_t* row = out + static_cast<size_t>(y) * width * 4;
        for (int x = 0; x < width; ++x, in += 3, row += 4) {
          row[0] = in[2];
          row[1] = in[1];
          row[2] = in[0];
          row[3] = 255;
        }
      }
      break;
    }
    case PixelFormat::kYUY2: {
      const YuvMatrix matrix(height);
      const uint8_t* in = data;
      for (size_t i = 0; i + 1 < pixels; i += 2, in += 4, out += 8) {
        matrix.Write(out, in[0], in[1], in[3]);
        matrix.Write(out + 4, in[2], in[1], in[3]);
      }
      break;
    }
    case PixelFormat::kNV12:
    case PixelFormat::kI420: {
      const YuvMatrix matrix(height);
      const bool interleaved = format_ == PixelFormat::kNV12;
      const int chroma_width = width / 2;
      const uint8_t* luma = data;
      const uint8_t* chroma = data + pixels;
      const uint8_t* chroma_v =
          chroma + static_cast<size_t>(chroma_width) * (height / 2);
      for (int y = 0; y < height; ++y) {
        const int chroma_row = std::min(y / 2, height / 2 - 1);
        const uint8_t* u_row =
            chroma + static_cast<size_t>(chroma_row) *
                         (interleaved ? chroma_width * 2 : chroma_width);
        const uint8_t* v_row =
            chroma_v + static_cast<size_t>(chroma_row) * chroma_width;
        for (int x = 0; x < width; ++x, out += 4) {
          const int cx = std::min(x / 2, chroma_width - 1);
          const int u = interleaved ? u_row[cx * 2] : u_row[cx];
          const int v = interleaved ? u_row[cx * 2 + 1] : v_row[cx];
          matrix.Write(out, luma[x], u, v);
        }
        luma += width;
      }
      break;
    }
  }

  if (vcam_.enabled()) {
    vcam_.Publish(back_.pixels.data(), width, height);
  }

  {
    std::lock_guard<std::mutex> lock(frame_mutex_);
    std::swap(back_, ready_);
    ready_is_new_ = true;
  }
  FlutterDesktopTextureRegistrarMarkExternalTextureFrameAvailable(registrar_,
                                                                  texture_id_);
}

// static
const FlutterDesktopPixelBuffer* CameraCapture::CopyPixelBuffer(
    size_t width,
    size_t height,
    void* user_data) {
  auto* self = static_cast<CameraCapture*>(user_data);
  {
    std::lock_guard<std::mutex> lock(self->frame_mutex_);
    if (self->ready_is_new_) {
      std::swap(self->ready_, self->front_);
      self->ready_is_new_ = false;
    }
  }
  const Frame& frame = self->front_;
  if (frame.width <= 0 || frame.height <= 0 || frame.pixels.empty()) {
    return nullptr;
  }
  self->pixel_buffer_.buffer = frame.pixels.data();
  self->pixel_buffer_.width = static_cast<size_t>(frame.width);
  self->pixel_buffer_.height = static_cast<size_t>(frame.height);
  self->pixel_buffer_.release_callback = nullptr;
  self->pixel_buffer_.release_context = nullptr;
  return &self->pixel_buffer_;
}
