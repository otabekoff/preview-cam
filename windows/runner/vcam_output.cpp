#include "vcam_output.h"

#include <algorithm>
#include <cmath>
#include <string>

namespace {

// DirectShow's "video capture sources" category.
constexpr wchar_t kClassKey[] =
    L"Software\\Classes\\CLSID\\" VCAM_CLSID_STRING;
constexpr wchar_t kServerKey[] =
    L"Software\\Classes\\CLSID\\" VCAM_CLSID_STRING L"\\InprocServer32";
constexpr wchar_t kInstanceKey[] =
    L"Software\\Classes\\CLSID\\{860BB310-5D01-11D0-BD3B-00A0C911CE86}"
    L"\\Instance\\" VCAM_CLSID_STRING;

bool SetString(const wchar_t* key, const wchar_t* name, const std::wstring& value) {
  return RegSetKeyValueW(
             HKEY_CURRENT_USER, key, name, REG_SZ, value.c_str(),
             static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t))) ==
         ERROR_SUCCESS;
}

// Converts one premultiplied RGBA pixel to straight BGRA, scaling its alpha
// by |coverage| (0..256) for the anti-aliased edge of the shape.
inline void WritePixel(uint8_t* out, const uint8_t* in, unsigned coverage) {
  unsigned a = in[3];
  if (a == 0 || coverage == 0) {
    out[0] = out[1] = out[2] = out[3] = 0;
    return;
  }
  if (a == 255) {
    out[0] = in[2];
    out[1] = in[1];
    out[2] = in[0];
  } else {
    // Undo the premultiplication done for Flutter.
    out[0] = static_cast<uint8_t>(std::min(255u, in[2] * 255u / a));
    out[1] = static_cast<uint8_t>(std::min(255u, in[1] * 255u / a));
    out[2] = static_cast<uint8_t>(std::min(255u, in[0] * 255u / a));
  }
  out[3] = static_cast<uint8_t>(coverage >= 256 ? a : (a * coverage) >> 8);
}

}  // namespace

VcamOutput::VcamOutput() {}

VcamOutput::~VcamOutput() {
  SetInactive();
  if (header_) {
    UnmapViewOfFile(header_);
  }
  if (mapping_) {
    CloseHandle(mapping_);
  }
  if (mutex_) {
    CloseHandle(mutex_);
  }
}

// static
bool VcamOutput::Register() {
  wchar_t path[MAX_PATH];
  const DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
  std::wstring dll(path, length);
  const size_t slash = dll.find_last_of(L'\\');
  dll = dll.substr(0, slash + 1) + VCAM_DLL_NAME;
  if (GetFileAttributesW(dll.c_str()) == INVALID_FILE_ATTRIBUTES) {
    return false;
  }
  // The COM class, and its entry in the capture-device category that camera
  // applications enumerate. Per-user keys are merged into HKEY_CLASSES_ROOT.
  return SetString(kClassKey, nullptr, VCAM_DEVICE_NAME) &&
         SetString(kServerKey, nullptr, dll) &&
         SetString(kServerKey, L"ThreadingModel", L"Both") &&
         SetString(kInstanceKey, L"FriendlyName", VCAM_DEVICE_NAME) &&
         SetString(kInstanceKey, L"CLSID", VCAM_CLSID_STRING);
}

// static
void VcamOutput::Unregister() {
  RegDeleteTreeW(HKEY_CURRENT_USER, kInstanceKey);
  RegDeleteTreeW(HKEY_CURRENT_USER, kClassKey);
}

bool VcamOutput::EnsureMapping() {
  if (header_) {
    return true;
  }
  // Opens the existing block if a consumer is still holding it from an
  // earlier run of the application.
  mutex_ = CreateMutexW(nullptr, FALSE, kVcamMutexName);
  mapping_ = CreateFileMappingW(
      INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE,
      static_cast<DWORD>(static_cast<ULONGLONG>(kVcamMappingSize) >> 32),
      static_cast<DWORD>(kVcamMappingSize & 0xFFFFFFFF), kVcamMappingName);
  if (mapping_) {
    header_ = static_cast<VcamHeader*>(
        MapViewOfFile(mapping_, FILE_MAP_ALL_ACCESS, 0, 0, kVcamMappingSize));
  }
  if (!header_ || !mutex_) {
    return false;
  }
  header_->producer_pid = GetCurrentProcessId();
  header_->active = 0;
  header_->magic = kVcamMagic;
  return true;
}

void VcamOutput::SetConfig(const Config& config) {
  std::lock_guard<std::mutex> lock(config_mutex_);
  config_ = config;
  if (config.enabled) {
    EnsureMapping();
  } else if (header_) {
    header_->active = 0;
  }
  enabled_ = config.enabled && header_ != nullptr;
}



void VcamOutput::SetInactive() {
  if (header_) {
    header_->active = 0;
    ++header_->frame;  // Wakes consumers so they switch to transparent.
  }
}

void VcamOutput::Publish(const uint8_t* rgba, int width, int height) {
  Config config;
  {
    std::lock_guard<std::mutex> lock(config_mutex_);
    config = config_;
  }
  if (!config.enabled || !header_ || width < 16 || height < 16) {
    return;
  }

  // Centre crop to the overlay's aspect ratio ("cover", as on screen).
  const double aspect = std::clamp(config.aspect, 0.1, 10.0);
  int out_width = width;
  int out_height = height;
  if (aspect < static_cast<double>(width) / height) {
    out_width = static_cast<int>(std::lround(height * aspect));
  } else {
    out_height = static_cast<int>(std::lround(width / aspect));
  }
  out_width = std::clamp(out_width & ~1, 16, std::min(width, static_cast<int>(kVcamMaxWidth)));
  out_height = std::clamp(out_height & ~1, 16, std::min(height, static_cast<int>(kVcamMaxHeight)));
  const int crop_x = (width - out_width) / 2;
  const int crop_y = (height - out_height) / 2;

  // Corner radius in output pixels. A circle is the limiting case.
  double radius = 0;
  const double half = std::min(out_width, out_height) / 2.0;
  if (config.shape == Shape::kCircle) {
    radius = half;
  } else if (config.shape == Shape::kRounded) {
    radius = std::clamp(config.radius * out_height, 0.0, half);
  }

  // Keep the advertised size current even while nobody is watching, so a
  // consumer that connects later negotiates the right format.
  if (header_->width != static_cast<UINT32>(out_width) ||
      header_->height != static_cast<UINT32>(out_height)) {
    if (WaitForSingleObject(mutex_, 100) == WAIT_TIMEOUT) {
      return;
    }
    header_->active = 0;  // The stored pixels no longer match the size.
    header_->width = static_cast<UINT32>(out_width);
    header_->height = static_cast<UINT32>(out_height);
    ReleaseMutex(mutex_);
    RegSetKeyValueW(HKEY_CURRENT_USER, kVcamRegistryKey, kVcamRegistryWidth,
                    REG_DWORD, &header_->width, sizeof(DWORD));
    RegSetKeyValueW(HKEY_CURRENT_USER, kVcamRegistryKey, kVcamRegistryHeight,
                    REG_DWORD, &header_->height, sizeof(DWORD));
  }
  if (header_->clients <= 0) {
    return;  // Nobody is watching: skip the per-pixel work entirely.
  }

  if (WaitForSingleObject(mutex_, 20) == WAIT_TIMEOUT) {
    return;  // A consumer is mid-copy; drop this frame rather than wait.
  }
  uint8_t* target = reinterpret_cast<uint8_t*>(header_) + sizeof(VcamHeader);

  for (int y = 0; y < out_height; ++y) {
    const uint8_t* in_row =
        rgba + (static_cast<size_t>(crop_y + y) * width + crop_x) * 4;
    uint8_t* out_row = target + static_cast<size_t>(y) * out_width * 4;

    // Within the rounded band, pixels left of |edge| (and their mirror
    // image on the right) are outside the shape, pixels from |solid| on are
    // fully inside, and those in between get anti-aliased coverage.
    int edge = 0;
    int solid = 0;
    double corner_y = 0;
    const double pixel_y = y + 0.5;
    if (radius > 0 && (pixel_y < radius || pixel_y > out_height - radius)) {
      corner_y = pixel_y < radius ? radius : out_height - radius;
      const double dy = pixel_y - corner_y;
      const double inset =
          radius - std::sqrt(std::max(0.0, radius * radius - dy * dy));
      edge = std::clamp(static_cast<int>(std::floor(inset - 1)), 0, out_width / 2);
      solid = std::clamp(static_cast<int>(std::ceil(inset + 1)), 0, out_width / 2);
    }

    for (int x = 0; x < out_width; ++x) {
      const int from_side = std::min(x, out_width - 1 - x);
      uint8_t* out = out_row + static_cast<size_t>(x) * 4;
      if (from_side < edge) {
        out[0] = out[1] = out[2] = out[3] = 0;
        continue;
      }
      unsigned coverage = 256;
      if (from_side < solid) {
        const double pixel_x = x + 0.5;
        const double corner_x = pixel_x < out_width / 2.0 ? radius : out_width - radius;
        const double distance = std::hypot(pixel_x - corner_x, pixel_y - corner_y);
        coverage = static_cast<unsigned>(
            std::clamp(radius - distance + 0.5, 0.0, 1.0) * 256.0);
      }
      const int source_x = config.mirror ? out_width - 1 - x : x;
      WritePixel(out, in_row + static_cast<size_t>(source_x) * 4, coverage);
    }
  }

  header_->producer_pid = GetCurrentProcessId();
  header_->active = 1;
  ++header_->frame;
  ReleaseMutex(mutex_);
}
