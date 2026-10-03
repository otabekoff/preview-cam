cmake_minimum_required(VERSION 3.14)
project(preview_vcam LANGUAGES CXX)

# The "Preview Cam" virtual camera: a DirectShow source filter that camera
# consumers such as OBS load in-process. See vcam_filter.cpp.
add_library(preview_vcam SHARED
  "vcam_filter.cpp"
  "vcam.def"
)

target_compile_features(preview_vcam PRIVATE cxx_std_17)
# Static C runtime: the DLL is loaded into other applications and must not
# depend on a particular Visual C++ redistributable being installed there.
target_compile_options(preview_vcam PRIVATE
  /W3 /EHsc
  "$<$<CONFIG:Debug>:/MTd>"
  "$<$<NOT:$<CONFIG:Debug>>:/MT>"
)
target_link_libraries(preview_vcam PRIVATE strmiids ole32 advapi32)
