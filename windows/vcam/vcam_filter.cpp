// "Preview Cam" virtual camera: a DirectShow source filter.
//
// This DLL is loaded by camera consumers (OBS's Video Capture Device source,
// or any other DirectShow application), never by Preview Cam itself. It
// exposes one capture pin that delivers the frames the application publishes
// through shared memory (see vcam_protocol.h) as ARGB32 video, i.e. with an
// alpha channel, so the overlay's rounded corners / circle stay transparent.
//
// It is written against the raw DirectShow COM interfaces (no base-class
// library) and links the C runtime statically, so it has no dependencies
// beyond Windows.
//
//   VcamFilter (IBaseFilter)
//     +- OutputPin (IPin, IAMStreamConfig, IKsPropertySet)
//          +- streaming thread: shared memory -> IMemInputPin::Receive
//
// While the application is not running or has no camera, transparent frames
// are delivered, so a scene that uses the camera simply shows nothing.

#include <windows.h>

#include <dshow.h>

#include "vcam_protocol.h"

// Standard IKsPropertySet errors; defined here in case the SDK headers that
// were pulled in do not provide them.
#ifndef E_PROP_SET_UNSUPPORTED
#define E_PROP_SET_UNSUPPORTED HRESULT_FROM_WIN32(ERROR_SET_NOT_FOUND)
#endif
#ifndef E_PROP_ID_UNSUPPORTED
#define E_PROP_ID_UNSUPPORTED HRESULT_FROM_WIN32(ERROR_NOT_FOUND)
#endif

namespace {

volatile LONG g_object_count = 0;

// --- Media types -----------------------------------------------------------

void FreeMediaTypeContents(AM_MEDIA_TYPE& type) {
  if (type.cbFormat) {
    CoTaskMemFree(type.pbFormat);
  }
  if (type.pUnk) {
    type.pUnk->Release();
  }
  ZeroMemory(&type, sizeof(type));
}

bool CopyMediaType(AM_MEDIA_TYPE* target, const AM_MEDIA_TYPE& source) {
  *target = source;
  if (source.cbFormat) {
    target->pbFormat = static_cast<BYTE*>(CoTaskMemAlloc(source.cbFormat));
    if (!target->pbFormat) {
      target->cbFormat = 0;
      return false;
    }
    CopyMemory(target->pbFormat, source.pbFormat, source.cbFormat);
  }
  if (target->pUnk) {
    target->pUnk->AddRef();
  }
  return true;
}

// Fills |type| with uncompressed 32-bit video of the given size.
// |alpha| selects ARGB32 (alpha is meaningful) over RGB32 (alpha ignored).
bool FillVideoType(AM_MEDIA_TYPE* type, int width, int height, bool alpha) {
  ZeroMemory(type, sizeof(*type));
  auto* info =
      static_cast<VIDEOINFOHEADER*>(CoTaskMemAlloc(sizeof(VIDEOINFOHEADER)));
  if (!info) {
    return false;
  }
  ZeroMemory(info, sizeof(*info));
  info->AvgTimePerFrame = kVcamFrameInterval;
  info->bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info->bmiHeader.biWidth = width;
  info->bmiHeader.biHeight = height;  // Positive: bottom-up rows.
  info->bmiHeader.biPlanes = 1;
  info->bmiHeader.biBitCount = 32;
  info->bmiHeader.biCompression = BI_RGB;
  info->bmiHeader.biSizeImage = static_cast<DWORD>(width) * height * 4;
  info->dwBitRate = info->bmiHeader.biSizeImage * 8 * 30;

  type->majortype = MEDIATYPE_Video;
  type->subtype = alpha ? MEDIASUBTYPE_ARGB32 : MEDIASUBTYPE_RGB32;
  type->bFixedSizeSamples = TRUE;
  type->bTemporalCompression = FALSE;
  type->lSampleSize = info->bmiHeader.biSizeImage;
  type->formattype = FORMAT_VideoInfo;
  type->cbFormat = sizeof(VIDEOINFOHEADER);
  type->pbFormat = reinterpret_cast<BYTE*>(info);
  return true;
}

// --- Shared memory ---------------------------------------------------------

// Read access to the application's frame block. Opened lazily and reopened
// until the application has created it.
class FrameSource {
 public:
  ~FrameSource() { Close(); }

  bool Open() {
    if (header_) {
      return true;
    }
    mapping_ = OpenFileMappingW(FILE_MAP_ALL_ACCESS, FALSE, kVcamMappingName);
    if (!mapping_) {
      return false;
    }
    header_ = static_cast<VcamHeader*>(
        MapViewOfFile(mapping_, FILE_MAP_ALL_ACCESS, 0, 0, kVcamMappingSize));
    mutex_ = OpenMutexW(SYNCHRONIZE, FALSE, kVcamMutexName);
    if (!header_ || !mutex_) {
      Close();
      return false;
    }
    return true;
  }

  void Close() {
    if (header_) {
      UnmapViewOfFile(header_);
      header_ = nullptr;
    }
    if (mapping_) {
      CloseHandle(mapping_);
      mapping_ = nullptr;
    }
    if (mutex_) {
      CloseHandle(mutex_);
      mutex_ = nullptr;
    }
  }

  VcamHeader* header() const { return header_; }
  const BYTE* pixels() const {
    return reinterpret_cast<const BYTE*>(header_) + sizeof(VcamHeader);
  }
  HANDLE mutex() const { return mutex_; }

 private:
  HANDLE mapping_ = nullptr;
  HANDLE mutex_ = nullptr;
  VcamHeader* header_ = nullptr;
};

bool ValidSize(UINT32 width, UINT32 height) {
  return width >= 16 && height >= 16 && width <= kVcamMaxWidth &&
         height <= kVcamMaxHeight;
}

// The size this camera advertises: what the application currently outputs,
// else what it last output, else a default.
void PreferredSize(int* width, int* height) {
  *width = kVcamDefaultWidth;
  *height = kVcamDefaultHeight;

  FrameSource source;
  if (source.Open() && source.header()->magic == kVcamMagic &&
      ValidSize(source.header()->width, source.header()->height)) {
    *width = static_cast<int>(source.header()->width);
    *height = static_cast<int>(source.header()->height);
    return;
  }

  DWORD stored_width = 0;
  DWORD stored_height = 0;
  DWORD size = sizeof(DWORD);
  if (RegGetValueW(HKEY_CURRENT_USER, kVcamRegistryKey, kVcamRegistryWidth,
                   RRF_RT_REG_DWORD, nullptr, &stored_width,
                   &size) == ERROR_SUCCESS) {
    size = sizeof(DWORD);
    if (RegGetValueW(HKEY_CURRENT_USER, kVcamRegistryKey, kVcamRegistryHeight,
                     RRF_RT_REG_DWORD, nullptr, &stored_height,
                     &size) == ERROR_SUCCESS &&
        ValidSize(stored_width, stored_height)) {
      *width = static_cast<int>(stored_width);
      *height = static_cast<int>(stored_height);
    }
  }
}

bool ProcessAlive(DWORD pid) {
  if (pid == 0) {
    return false;
  }
  HANDLE process = OpenProcess(SYNCHRONIZE, FALSE, pid);
  if (!process) {
    return false;
  }
  const bool alive = WaitForSingleObject(process, 0) == WAIT_TIMEOUT;
  CloseHandle(process);
  return alive;
}

class VcamFilter;

// --- IEnumMediaTypes ---------------------------------------------------------

class MediaTypeEnum : public IEnumMediaTypes {
 public:
  MediaTypeEnum(int width, int height, ULONG position)
      : width_(width), height_(height), position_(position) {
    InterlockedIncrement(&g_object_count);
  }
  virtual ~MediaTypeEnum() { InterlockedDecrement(&g_object_count); }

  STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
    if (iid == IID_IUnknown || iid == IID_IEnumMediaTypes) {
      *object = static_cast<IEnumMediaTypes*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }
  STDMETHODIMP_(ULONG) AddRef() override { return InterlockedIncrement(&refs_); }
  STDMETHODIMP_(ULONG) Release() override {
    const LONG refs = InterlockedDecrement(&refs_);
    if (refs == 0) {
      delete this;
    }
    return refs;
  }

  STDMETHODIMP Next(ULONG count, AM_MEDIA_TYPE** types, ULONG* fetched) override {
    ULONG done = 0;
    while (done < count && position_ < 2) {
      auto* type =
          static_cast<AM_MEDIA_TYPE*>(CoTaskMemAlloc(sizeof(AM_MEDIA_TYPE)));
      if (!type || !FillVideoType(type, width_, height_, position_ == 0)) {
        CoTaskMemFree(type);
        break;
      }
      types[done++] = type;
      ++position_;
    }
    if (fetched) {
      *fetched = done;
    }
    return done == count ? S_OK : S_FALSE;
  }
  STDMETHODIMP Skip(ULONG count) override {
    position_ += count;
    return position_ <= 2 ? S_OK : S_FALSE;
  }
  STDMETHODIMP Reset() override {
    position_ = 0;
    return S_OK;
  }
  STDMETHODIMP Clone(IEnumMediaTypes** copy) override {
    *copy = new MediaTypeEnum(width_, height_, position_);
    return S_OK;
  }

 private:
  volatile LONG refs_ = 1;
  int width_;
  int height_;
  ULONG position_;
};

// --- Output pin ------------------------------------------------------------

// The single capture pin. Its lifetime is the filter's: reference counting is
// forwarded there.
class OutputPin : public IPin, public IAMStreamConfig, public IKsPropertySet {
 public:
  explicit OutputPin(VcamFilter* filter) : filter_(filter) {
    PreferredSize(&width_, &height_);
    InitializeCriticalSection(&lock_);
  }
  ~OutputPin() {
    StopStreaming();
    BreakConnection();
    DeleteCriticalSection(&lock_);
  }

  // IUnknown
  STDMETHODIMP QueryInterface(REFIID iid, void** object) override;
  STDMETHODIMP_(ULONG) AddRef() override;
  STDMETHODIMP_(ULONG) Release() override;

  // IPin
  STDMETHODIMP Connect(IPin* receiver, const AM_MEDIA_TYPE* type) override;
  STDMETHODIMP ReceiveConnection(IPin*, const AM_MEDIA_TYPE*) override {
    return E_UNEXPECTED;  // Output pins initiate connections.
  }
  STDMETHODIMP Disconnect() override;
  STDMETHODIMP ConnectedTo(IPin** pin) override {
    if (!connected_) {
      *pin = nullptr;
      return VFW_E_NOT_CONNECTED;
    }
    *pin = connected_;
    connected_->AddRef();
    return S_OK;
  }
  STDMETHODIMP ConnectionMediaType(AM_MEDIA_TYPE* type) override {
    if (!connected_) {
      ZeroMemory(type, sizeof(*type));
      return VFW_E_NOT_CONNECTED;
    }
    return FillVideoType(type, width_, height_, alpha_) ? S_OK : E_OUTOFMEMORY;
  }
  STDMETHODIMP QueryPinInfo(PIN_INFO* info) override;
  STDMETHODIMP QueryDirection(PIN_DIRECTION* direction) override {
    *direction = PINDIR_OUTPUT;
    return S_OK;
  }
  STDMETHODIMP QueryId(LPWSTR* id) override {
    static const wchar_t kId[] = L"Video";
    *id = static_cast<LPWSTR>(CoTaskMemAlloc(sizeof(kId)));
    if (!*id) {
      return E_OUTOFMEMORY;
    }
    CopyMemory(*id, kId, sizeof(kId));
    return S_OK;
  }
  STDMETHODIMP QueryAccept(const AM_MEDIA_TYPE* type) override {
    bool alpha;
    return Accepts(type, &alpha) ? S_OK : S_FALSE;
  }
  STDMETHODIMP EnumMediaTypes(IEnumMediaTypes** types) override {
    *types = new MediaTypeEnum(width_, height_, 0);
    return S_OK;
  }
  STDMETHODIMP QueryInternalConnections(IPin**, ULONG*) override {
    return E_NOTIMPL;
  }
  STDMETHODIMP EndOfStream() override { return E_UNEXPECTED; }
  STDMETHODIMP BeginFlush() override { return E_UNEXPECTED; }
  STDMETHODIMP EndFlush() override { return E_UNEXPECTED; }
  STDMETHODIMP NewSegment(REFERENCE_TIME, REFERENCE_TIME, double) override {
    return S_OK;
  }

  // IAMStreamConfig
  STDMETHODIMP SetFormat(AM_MEDIA_TYPE* type) override {
    if (!type) {
      alpha_ = true;
      return S_OK;
    }
    bool alpha;
    if (!Accepts(type, &alpha)) {
      return VFW_E_INVALIDMEDIATYPE;
    }
    if (connected_) {
      return alpha == alpha_ ? S_OK : VFW_E_ALREADY_CONNECTED;
    }
    alpha_ = alpha;
    return S_OK;
  }
  STDMETHODIMP GetFormat(AM_MEDIA_TYPE** type) override {
    *type = static_cast<AM_MEDIA_TYPE*>(CoTaskMemAlloc(sizeof(AM_MEDIA_TYPE)));
    if (!*type || !FillVideoType(*type, width_, height_, alpha_)) {
      CoTaskMemFree(*type);
      *type = nullptr;
      return E_OUTOFMEMORY;
    }
    return S_OK;
  }
  STDMETHODIMP GetNumberOfCapabilities(int* count, int* size) override {
    *count = 2;
    *size = sizeof(VIDEO_STREAM_CONFIG_CAPS);
    return S_OK;
  }
  STDMETHODIMP GetStreamCaps(int index,
                             AM_MEDIA_TYPE** type,
                             BYTE* caps_bytes) override {
    if (index < 0 || index > 1) {
      return S_FALSE;
    }
    *type = static_cast<AM_MEDIA_TYPE*>(CoTaskMemAlloc(sizeof(AM_MEDIA_TYPE)));
    if (!*type || !FillVideoType(*type, width_, height_, index == 0)) {
      CoTaskMemFree(*type);
      *type = nullptr;
      return E_OUTOFMEMORY;
    }
    auto* caps = reinterpret_cast<VIDEO_STREAM_CONFIG_CAPS*>(caps_bytes);
    ZeroMemory(caps, sizeof(*caps));
    caps->guid = FORMAT_VideoInfo;
    caps->InputSize.cx = caps->MinCroppingSize.cx = caps->MaxCroppingSize.cx =
        caps->MinOutputSize.cx = caps->MaxOutputSize.cx = width_;
    caps->InputSize.cy = caps->MinCroppingSize.cy = caps->MaxCroppingSize.cy =
        caps->MinOutputSize.cy = caps->MaxOutputSize.cy = height_;
    caps->MinFrameInterval = caps->MaxFrameInterval = kVcamFrameInterval;
    caps->MinBitsPerSecond = caps->MaxBitsPerSecond =
        static_cast<LONG>(width_) * height_ * 4 * 8 * 30;
    return S_OK;
  }

  // IKsPropertySet: lets applications recognise this as a capture pin.
  STDMETHODIMP Set(REFGUID, DWORD, LPVOID, DWORD, LPVOID, DWORD) override {
    return E_NOTIMPL;
  }
  STDMETHODIMP Get(REFGUID property_set,
                   DWORD id,
                   LPVOID,
                   DWORD,
                   LPVOID data,
                   DWORD length,
                   DWORD* returned) override {
    if (property_set != AMPROPSETID_Pin) {
      return E_PROP_SET_UNSUPPORTED;
    }
    if (id != AMPROPERTY_PIN_CATEGORY) {
      return E_PROP_ID_UNSUPPORTED;
    }
    if (returned) {
      *returned = sizeof(GUID);
    }
    if (!data) {
      return returned ? S_OK : E_POINTER;
    }
    if (length < sizeof(GUID)) {
      return E_UNEXPECTED;
    }
    *static_cast<GUID*>(data) = PIN_CATEGORY_CAPTURE;
    return S_OK;
  }
  STDMETHODIMP QuerySupported(REFGUID property_set,
                              DWORD id,
                              DWORD* support) override {
    if (property_set != AMPROPSETID_Pin) {
      return E_PROP_SET_UNSUPPORTED;
    }
    if (id != AMPROPERTY_PIN_CATEGORY) {
      return E_PROP_ID_UNSUPPORTED;
    }
    if (support) {
      *support = KSPROPERTY_SUPPORT_GET;
    }
    return S_OK;
  }

  bool connected() const { return connected_ != nullptr; }

  // Called by the filter on state changes.
  HRESULT StartStreaming();
  void StopStreaming();

 private:
  bool Accepts(const AM_MEDIA_TYPE* type, bool* alpha) const {
    if (!type || type->majortype != MEDIATYPE_Video ||
        type->formattype != FORMAT_VideoInfo ||
        type->cbFormat < sizeof(VIDEOINFOHEADER) || !type->pbFormat) {
      return false;
    }
    if (type->subtype == MEDIASUBTYPE_ARGB32) {
      *alpha = true;
    } else if (type->subtype == MEDIASUBTYPE_RGB32) {
      *alpha = false;
    } else {
      return false;
    }
    const auto& header =
        reinterpret_cast<const VIDEOINFOHEADER*>(type->pbFormat)->bmiHeader;
    return header.biWidth == width_ && header.biHeight == height_ &&
           header.biBitCount == 32;
  }

  HRESULT TryConnect(IPin* receiver, bool alpha);
  void BreakConnection();

  static DWORD WINAPI ThreadProc(LPVOID self) {
    static_cast<OutputPin*>(self)->StreamLoop();
    return 0;
  }
  void StreamLoop();
  // Writes one bottom-up |width_| x |height_| frame into |target|.
  void Render(BYTE* target);

  VcamFilter* filter_;
  CRITICAL_SECTION lock_;
  int width_ = kVcamDefaultWidth;
  int height_ = kVcamDefaultHeight;
  bool alpha_ = true;

  IPin* connected_ = nullptr;
  IMemInputPin* input_ = nullptr;
  IMemAllocator* allocator_ = nullptr;

  HANDLE thread_ = nullptr;
  volatile LONG stop_ = 0;

  // Streaming-thread state.
  FrameSource source_;
  bool counted_ = false;       // This consumer is included in header->clients.
  UINT32 last_frame_ = 0;
  DWORD last_alive_check_ = 0;
  bool producer_alive_ = false;
};

// --- IEnumPins ---------------------------------------------------------------

class PinEnum : public IEnumPins {
 public:
  PinEnum(IPin* pin, ULONG position) : pin_(pin), position_(position) {
    pin_->AddRef();
    InterlockedIncrement(&g_object_count);
  }
  virtual ~PinEnum() {
    pin_->Release();
    InterlockedDecrement(&g_object_count);
  }

  STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
    if (iid == IID_IUnknown || iid == IID_IEnumPins) {
      *object = static_cast<IEnumPins*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }
  STDMETHODIMP_(ULONG) AddRef() override { return InterlockedIncrement(&refs_); }
  STDMETHODIMP_(ULONG) Release() override {
    const LONG refs = InterlockedDecrement(&refs_);
    if (refs == 0) {
      delete this;
    }
    return refs;
  }

  STDMETHODIMP Next(ULONG count, IPin** pins, ULONG* fetched) override {
    ULONG done = 0;
    if (count > 0 && position_ == 0) {
      pins[0] = pin_;
      pin_->AddRef();
      position_ = 1;
      done = 1;
    }
    if (fetched) {
      *fetched = done;
    }
    return done == count ? S_OK : S_FALSE;
  }
  STDMETHODIMP Skip(ULONG count) override {
    position_ += count;
    return position_ <= 1 ? S_OK : S_FALSE;
  }
  STDMETHODIMP Reset() override {
    position_ = 0;
    return S_OK;
  }
  STDMETHODIMP Clone(IEnumPins** copy) override {
    *copy = new PinEnum(pin_, position_);
    return S_OK;
  }

 private:
  volatile LONG refs_ = 1;
  IPin* pin_;
  ULONG position_;
};

// --- Filter ------------------------------------------------------------------

class VcamFilter : public IBaseFilter, public IAMFilterMiscFlags {
 public:
  VcamFilter() : pin_(this) { InterlockedIncrement(&g_object_count); }
  virtual ~VcamFilter() {
    if (clock_) {
      clock_->Release();
    }
    InterlockedDecrement(&g_object_count);
  }

  // IUnknown
  STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
    if (iid == IID_IUnknown || iid == IID_IPersist || iid == IID_IMediaFilter ||
        iid == IID_IBaseFilter) {
      *object = static_cast<IBaseFilter*>(this);
    } else if (iid == IID_IAMFilterMiscFlags) {
      *object = static_cast<IAMFilterMiscFlags*>(this);
    } else {
      *object = nullptr;
      return E_NOINTERFACE;
    }
    AddRef();
    return S_OK;
  }
  STDMETHODIMP_(ULONG) AddRef() override { return InterlockedIncrement(&refs_); }
  STDMETHODIMP_(ULONG) Release() override {
    const LONG refs = InterlockedDecrement(&refs_);
    if (refs == 0) {
      delete this;
    }
    return refs;
  }

  // IPersist
  STDMETHODIMP GetClassID(CLSID* clsid) override {
    *clsid = kVcamClsid;
    return S_OK;
  }

  // IMediaFilter
  STDMETHODIMP Stop() override {
    pin_.StopStreaming();
    state_ = State_Stopped;
    return S_OK;
  }
  STDMETHODIMP Pause() override {
    // A live source delivers nothing while paused; streaming continues from
    // Run. Coming from Run, the thread simply idles.
    HRESULT hr = S_OK;
    if (state_ == State_Stopped) {
      hr = pin_.StartStreaming();
    }
    if (SUCCEEDED(hr)) {
      state_ = State_Paused;
    }
    return hr;
  }
  STDMETHODIMP Run(REFERENCE_TIME start) override {
    HRESULT hr = S_OK;
    if (state_ == State_Stopped) {
      hr = pin_.StartStreaming();
    }
    if (SUCCEEDED(hr)) {
      run_start_ = start;
      state_ = State_Running;
    }
    return hr;
  }
  STDMETHODIMP GetState(DWORD, FILTER_STATE* state) override {
    *state = state_;
    // Live sources cannot preroll data while paused.
    return state_ == State_Paused ? VFW_S_CANT_CUE : S_OK;
  }
  STDMETHODIMP SetSyncSource(IReferenceClock* clock) override {
    if (clock) {
      clock->AddRef();
    }
    if (clock_) {
      clock_->Release();
    }
    clock_ = clock;
    return S_OK;
  }
  STDMETHODIMP GetSyncSource(IReferenceClock** clock) override {
    *clock = clock_;
    if (clock_) {
      clock_->AddRef();
    }
    return S_OK;
  }

  // IBaseFilter
  STDMETHODIMP EnumPins(IEnumPins** pins) override {
    *pins = new PinEnum(&pin_, 0);
    return S_OK;
  }
  STDMETHODIMP FindPin(LPCWSTR id, IPin** pin) override {
    if (id && lstrcmpW(id, L"Video") == 0) {
      *pin = &pin_;
      pin_.AddRef();
      return S_OK;
    }
    *pin = nullptr;
    return VFW_E_NOT_FOUND;
  }
  STDMETHODIMP QueryFilterInfo(FILTER_INFO* info) override {
    lstrcpynW(info->achName, name_, ARRAYSIZE(info->achName));
    info->pGraph = graph_;
    if (graph_) {
      graph_->AddRef();
    }
    return S_OK;
  }
  STDMETHODIMP JoinFilterGraph(IFilterGraph* graph, LPCWSTR name) override {
    // Not reference counted: the graph owns the filter, not the reverse.
    graph_ = graph;
    lstrcpynW(name_, name ? name : L"", ARRAYSIZE(name_));
    return S_OK;
  }
  STDMETHODIMP QueryVendorInfo(LPWSTR*) override { return E_NOTIMPL; }

  // IAMFilterMiscFlags
  STDMETHODIMP_(ULONG) GetMiscFlags() override {
    return AM_FILTER_MISC_FLAGS_IS_SOURCE;
  }

  FILTER_STATE state() const { return state_; }

  // Stream time of "now": time since Run according to the graph's clock.
  REFERENCE_TIME StreamTime() {
    REFERENCE_TIME now = 0;
    if (clock_ && SUCCEEDED(clock_->GetTime(&now))) {
      return now - run_start_;
    }
    return -1;
  }

 private:
  volatile LONG refs_ = 1;
  OutputPin pin_;
  volatile FILTER_STATE state_ = State_Stopped;
  IFilterGraph* graph_ = nullptr;
  IReferenceClock* clock_ = nullptr;
  REFERENCE_TIME run_start_ = 0;
  wchar_t name_[128] = L"";
};

// --- OutputPin implementation -------------------------------------------------

STDMETHODIMP OutputPin::QueryInterface(REFIID iid, void** object) {
  if (iid == IID_IUnknown || iid == IID_IPin) {
    *object = static_cast<IPin*>(this);
  } else if (iid == IID_IAMStreamConfig) {
    *object = static_cast<IAMStreamConfig*>(this);
  } else if (iid == IID_IKsPropertySet) {
    *object = static_cast<IKsPropertySet*>(this);
  } else {
    *object = nullptr;
    return E_NOINTERFACE;
  }
  AddRef();
  return S_OK;
}

STDMETHODIMP_(ULONG) OutputPin::AddRef() {
  return filter_->AddRef();
}

STDMETHODIMP_(ULONG) OutputPin::Release() {
  return filter_->Release();
}

STDMETHODIMP OutputPin::QueryPinInfo(PIN_INFO* info) {
  info->pFilter = filter_;
  filter_->AddRef();
  info->dir = PINDIR_OUTPUT;
  lstrcpynW(info->achName, L"Video", ARRAYSIZE(info->achName));
  return S_OK;
}

HRESULT OutputPin::TryConnect(IPin* receiver, bool alpha) {
  AM_MEDIA_TYPE type;
  if (!FillVideoType(&type, width_, height_, alpha)) {
    return E_OUTOFMEMORY;
  }
  HRESULT hr = receiver->ReceiveConnection(static_cast<IPin*>(this), &type);
  FreeMediaTypeContents(type);
  if (FAILED(hr)) {
    return hr;
  }

  hr = receiver->QueryInterface(IID_PPV_ARGS(&input_));
  if (SUCCEEDED(hr)) {
    // Prefer the receiver's allocator; fall back to the standard one.
    ALLOCATOR_PROPERTIES wanted{};
    wanted.cBuffers = 2;
    wanted.cbBuffer = width_ * height_ * 4;
    wanted.cbAlign = 1;
    ALLOCATOR_PROPERTIES actual{};
    hr = input_->GetAllocator(&allocator_);
    if (SUCCEEDED(hr)) {
      hr = allocator_->SetProperties(&wanted, &actual);
    }
    if (FAILED(hr)) {
      if (allocator_) {
        allocator_->Release();
        allocator_ = nullptr;
      }
      hr = CoCreateInstance(CLSID_MemoryAllocator, nullptr,
                            CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&allocator_));
      if (SUCCEEDED(hr)) {
        hr = allocator_->SetProperties(&wanted, &actual);
      }
    }
    if (SUCCEEDED(hr) && actual.cbBuffer < wanted.cbBuffer) {
      hr = VFW_E_BUFFER_OVERFLOW;
    }
    if (SUCCEEDED(hr)) {
      hr = input_->NotifyAllocator(allocator_, FALSE);
    }
  }
  if (FAILED(hr)) {
    receiver->Disconnect();
    BreakConnection();
    return hr;
  }

  alpha_ = alpha;
  connected_ = receiver;
  connected_->AddRef();
  return S_OK;
}

STDMETHODIMP OutputPin::Connect(IPin* receiver, const AM_MEDIA_TYPE* type) {
  if (!receiver) {
    return E_POINTER;
  }
  if (connected_) {
    return VFW_E_ALREADY_CONNECTED;
  }
  if (filter_->state() != State_Stopped) {
    return VFW_E_NOT_STOPPED;
  }
  // The size may have changed since this filter was created.
  PreferredSize(&width_, &height_);

  // A fully or partially specified type restricts which format is offered.
  bool allow_alpha = true;
  bool allow_opaque = true;
  if (type && type->majortype != GUID_NULL &&
      type->majortype != MEDIATYPE_Video) {
    return VFW_E_TYPE_NOT_ACCEPTED;
  }
  if (type && type->subtype != GUID_NULL) {
    allow_alpha = type->subtype == MEDIASUBTYPE_ARGB32;
    allow_opaque = type->subtype == MEDIASUBTYPE_RGB32;
  }

  // The format chosen with IAMStreamConfig::SetFormat goes first.
  HRESULT hr = VFW_E_NO_ACCEPTABLE_TYPES;
  const bool order[2] = {alpha_, !alpha_};
  for (bool alpha : order) {
    if (alpha ? !allow_alpha : !allow_opaque) {
      continue;
    }
    hr = TryConnect(receiver, alpha);
    if (SUCCEEDED(hr)) {
      return S_OK;
    }
  }
  return FAILED(hr) ? hr : VFW_E_NO_ACCEPTABLE_TYPES;
}

void OutputPin::BreakConnection() {
  if (allocator_) {
    allocator_->Release();
    allocator_ = nullptr;
  }
  if (input_) {
    input_->Release();
    input_ = nullptr;
  }
  if (connected_) {
    connected_->Release();
    connected_ = nullptr;
  }
}

STDMETHODIMP OutputPin::Disconnect() {
  if (filter_->state() != State_Stopped) {
    return VFW_E_NOT_STOPPED;
  }
  if (!connected_) {
    return S_FALSE;
  }
  BreakConnection();
  return S_OK;
}

HRESULT OutputPin::StartStreaming() {
  if (!connected_ || !allocator_ || thread_) {
    return S_OK;  // An unconnected source filter simply has nothing to do.
  }
  HRESULT hr = allocator_->Commit();
  if (FAILED(hr)) {
    return hr;
  }
  stop_ = 0;
  thread_ = CreateThread(nullptr, 0, ThreadProc, this, 0, nullptr);
  return thread_ ? S_OK : E_OUTOFMEMORY;
}

void OutputPin::StopStreaming() {
  if (!thread_) {
    return;
  }
  InterlockedExchange(&stop_, 1);
  if (allocator_) {
    allocator_->Decommit();  // Unblocks a pending GetBuffer.
  }
  WaitForSingleObject(thread_, INFINITE);
  CloseHandle(thread_);
  thread_ = nullptr;
}

void OutputPin::StreamLoop() {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  LARGE_INTEGER frequency;
  QueryPerformanceFrequency(&frequency);
  LARGE_INTEGER started;
  QueryPerformanceCounter(&started);
  DWORD last_sent = 0;
  const DWORD frame_ms = static_cast<DWORD>(kVcamFrameInterval / 10000);

  while (!stop_) {
    if (filter_->state() != State_Running) {
      Sleep(5);
      continue;
    }

    // Deliver as soon as the application publishes a frame; otherwise repeat
    // the last picture at the nominal rate so the stream never stalls.
    const DWORD now = GetTickCount();
    const bool fresh = source_.Open() && source_.header()->magic == kVcamMagic &&
                       source_.header()->frame != last_frame_;
    if (!fresh && now - last_sent < frame_ms + frame_ms / 2) {
      Sleep(2);
      continue;
    }
    if (fresh && now - last_sent < frame_ms / 3) {
      Sleep(1);  // Never faster than ~3x the nominal rate.
      continue;
    }

    IMediaSample* sample = nullptr;
    if (FAILED(allocator_->GetBuffer(&sample, nullptr, nullptr, 0)) || !sample) {
      Sleep(5);
      continue;
    }
    BYTE* data = nullptr;
    const long size = width_ * height_ * 4;
    if (SUCCEEDED(sample->GetPointer(&data)) && data &&
        sample->GetSize() >= size) {
      Render(data);
      sample->SetActualDataLength(size);
      sample->SetSyncPoint(TRUE);
      sample->SetDiscontinuity(last_sent == 0);

      REFERENCE_TIME start = filter_->StreamTime();
      if (start < 0) {
        LARGE_INTEGER counter;
        QueryPerformanceCounter(&counter);
        start = (counter.QuadPart - started.QuadPart) * 10000000 /
                frequency.QuadPart;
      }
      REFERENCE_TIME end = start + kVcamFrameInterval;
      sample->SetTime(&start, &end);
      input_->Receive(sample);
      last_sent = now ? now : 1;
    }
    sample->Release();
  }

  if (counted_ && source_.header()) {
    InterlockedDecrement(&source_.header()->clients);
  }
  counted_ = false;
  source_.Close();
  CoUninitialize();
}

void OutputPin::Render(BYTE* target) {
  const int width = width_;
  const int height = height_;
  const size_t row_bytes = static_cast<size_t>(width) * 4;
  bool drawn = false;

  if (source_.Open()) {
    VcamHeader* header = source_.header();
    if (!counted_) {
      // Tells the application that someone is watching.
      InterlockedIncrement(&header->clients);
      counted_ = true;
    }
    // Checked about once a second: a crashed application leaves |active| set.
    const DWORD now = GetTickCount();
    if (now - last_alive_check_ > 1000 || last_alive_check_ == 0) {
      last_alive_check_ = now ? now : 1;
      producer_alive_ = ProcessAlive(header->producer_pid);
    }

    if (WaitForSingleObject(source_.mutex(), 50) != WAIT_TIMEOUT) {
      last_frame_ = header->frame;
      const int source_width = static_cast<int>(header->width);
      const int source_height = static_cast<int>(header->height);
      if (header->magic == kVcamMagic && header->active && producer_alive_ &&
          ValidSize(header->width, header->height)) {
        const BYTE* pixels = source_.pixels();
        if (source_width == width && source_height == height) {
          // Same size: copy rows, flipping top-down to bottom-up.
          for (int y = 0; y < height; ++y) {
            CopyMemory(target + (height - 1 - y) * row_bytes,
                       pixels + y * row_bytes, row_bytes);
          }
        } else {
          // The overlay's shape changed after this camera was connected:
          // fit the picture inside the negotiated size, padded with
          // transparency. Reactivating the source picks up the new size.
          ZeroMemory(target, row_bytes * height);
          const double scale =
              min(static_cast<double>(width) / source_width,
                  static_cast<double>(height) / source_height);
          const int out_width = max(1, static_cast<int>(source_width * scale));
          const int out_height =
              max(1, static_cast<int>(source_height * scale));
          const int left = (width - out_width) / 2;
          const int top = (height - out_height) / 2;
          for (int y = 0; y < out_height; ++y) {
            const int source_y = min(source_height - 1,
                                     static_cast<int>(y / scale));
            const UINT32* in = reinterpret_cast<const UINT32*>(
                pixels + static_cast<size_t>(source_y) * source_width * 4);
            UINT32* out = reinterpret_cast<UINT32*>(
                target + (height - 1 - (top + y)) * row_bytes) + left;
            for (int x = 0; x < out_width; ++x) {
              out[x] = in[min(source_width - 1, static_cast<int>(x / scale))];
            }
          }
        }
        drawn = true;
      }
      ReleaseMutex(source_.mutex());
    }
  }

  if (!drawn) {
    ZeroMemory(target, row_bytes * height);  // Fully transparent.
    return;
  }
  if (!alpha_) {
    // The consumer ignores alpha (RGB32): blend onto black so the area
    // outside the shape is black instead of leftover colour.
    BYTE* pixel = target;
    for (size_t i = 0, count = static_cast<size_t>(width) * height; i < count;
         ++i, pixel += 4) {
      const unsigned a = pixel[3];
      if (a != 255) {
        pixel[0] = static_cast<BYTE>(pixel[0] * a / 255);
        pixel[1] = static_cast<BYTE>(pixel[1] * a / 255);
        pixel[2] = static_cast<BYTE>(pixel[2] * a / 255);
        pixel[3] = 255;
      }
    }
  }
}

// --- Class factory and DLL entry points ---------------------------------------

class ClassFactory : public IClassFactory {
 public:
  STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
    if (iid == IID_IUnknown || iid == IID_IClassFactory) {
      *object = static_cast<IClassFactory*>(this);
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }
  // A static object: not reference counted.
  STDMETHODIMP_(ULONG) AddRef() override { return 2; }
  STDMETHODIMP_(ULONG) Release() override { return 1; }

  STDMETHODIMP CreateInstance(IUnknown* outer, REFIID iid, void** object) override {
    *object = nullptr;
    if (outer) {
      return CLASS_E_NOAGGREGATION;
    }
    VcamFilter* filter = new VcamFilter();
    const HRESULT hr = filter->QueryInterface(iid, object);
    filter->Release();
    return hr;
  }
  STDMETHODIMP LockServer(BOOL lock) override {
    if (lock) {
      InterlockedIncrement(&g_object_count);
    } else {
      InterlockedDecrement(&g_object_count);
    }
    return S_OK;
  }
};

ClassFactory g_factory;

}  // namespace

STDAPI DllGetClassObject(REFCLSID clsid, REFIID iid, void** object) {
  if (clsid != kVcamClsid) {
    *object = nullptr;
    return CLASS_E_CLASSNOTAVAILABLE;
  }
  return g_factory.QueryInterface(iid, object);
}

STDAPI DllCanUnloadNow() {
  return g_object_count == 0 ? S_OK : S_FALSE;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    DisableThreadLibraryCalls(instance);
  }
  return TRUE;
}
