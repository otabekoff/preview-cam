#ifndef VCAM_PROTOCOL_H_
#define VCAM_PROTOCOL_H_

// Contract between the application (which produces frames) and the virtual
// camera filter DLL (which is loaded into OBS or any other camera consumer
// and hands those frames out as a DirectShow capture device).
//
// Transport is a named shared-memory block: a VcamHeader followed by one
// frame of pixels. The application overwrites the frame in place and bumps
// |frame|; consumers copy the newest frame whenever the counter changes.
// |kVcamMutexName| serialises access to the block.
//
// Pixels are 32-bit BGRA with straight (non-premultiplied) alpha, stored
// top-down, |width| * |height| * 4 bytes. Everything outside the overlay's
// shape has alpha 0, which is what gives OBS real transparent corners.

#include <windows.h>

// CLSID of the virtual camera filter: {5C2A7B1E-9D43-4E8A-B6F1-3A7C2D9E4F10}
static const GUID kVcamClsid = {
    0x5c2a7b1e, 0x9d43, 0x4e8a, {0xb6, 0xf1, 0x3a, 0x7c, 0x2d, 0x9e, 0x4f, 0x10}};
#define VCAM_CLSID_STRING L"{5C2A7B1E-9D43-4E8A-B6F1-3A7C2D9E4F10}"

// Name shown in camera lists (OBS: Video Capture Device > Device).
#define VCAM_DEVICE_NAME L"Preview Cam"
// File name of the filter DLL, installed next to the application.
#define VCAM_DLL_NAME L"preview_vcam.dll"

static const wchar_t kVcamMappingName[] = L"Local\\PreviewCam.Vcam.Frame";
static const wchar_t kVcamMutexName[] = L"Local\\PreviewCam.Vcam.Mutex";

// Per-user registry key where the application records the size of its
// output, so the camera can advertise it even before the application runs.
static const wchar_t kVcamRegistryKey[] = L"Software\\PreviewCam";
static const wchar_t kVcamRegistryWidth[] = L"OutputWidth";
static const wchar_t kVcamRegistryHeight[] = L"OutputHeight";

static const UINT32 kVcamMagic = 0x4D435650;  // 'PVCM'
static const UINT32 kVcamMaxWidth = 3840;
static const UINT32 kVcamMaxHeight = 2160;
static const UINT32 kVcamDefaultWidth = 1280;
static const UINT32 kVcamDefaultHeight = 720;
// The camera delivers at this rate; frames are repeated when the
// application produces fewer.
static const LONGLONG kVcamFrameInterval = 333333;  // 100ns units, 30 fps

struct VcamHeader {
  UINT32 magic;   // kVcamMagic once the application has initialised the block
  UINT32 width;   // size of the current frame
  UINT32 height;
  UINT32 frame;   // incremented for every published frame
  UINT32 active;  // 1 while the application is delivering camera frames
  UINT32 producer_pid;  // process that writes frames (to detect a crash)
  // Number of consumers currently streaming. The application only spends
  // time composing frames while this is non-zero.
  volatile LONG clients;
  UINT32 reserved[9];
};

static const SIZE_T kVcamMappingSize =
    sizeof(VcamHeader) +
    static_cast<SIZE_T>(kVcamMaxWidth) * kVcamMaxHeight * 4;

#endif  // VCAM_PROTOCOL_H_
