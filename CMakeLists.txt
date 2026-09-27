cmake_minimum_required(VERSION 3.21)
project(VRKeyboardEmulator LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(FetchContent)
FetchContent_Declare(
  openvr
  GIT_REPOSITORY https://github.com/ValveSoftware/openvr.git
  GIT_TAG v2.15.6
  GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(openvr)

set(OPENVR_HEADERS ${openvr_SOURCE_DIR}/headers)

add_library(driver_vrkbd SHARED
  src/driver.cpp
  src/shared_state.cpp
)
target_include_directories(driver_vrkbd PRIVATE ${OPENVR_HEADERS} src)
if(TARGET openvr_api64)
  target_link_libraries(driver_vrkbd PRIVATE openvr_api64)
elseif(TARGET openvr_api)
  target_link_libraries(driver_vrkbd PRIVATE openvr_api)
elseif(EXISTS "${openvr_SOURCE_DIR}/lib/win64/openvr_api.lib")
  target_link_libraries(driver_vrkbd PRIVATE "${openvr_SOURCE_DIR}/lib/win64/openvr_api.lib")
else()
  message(FATAL_ERROR "Could not find an OpenVR library target or Windows x64 library")
endif()
target_compile_definitions(driver_vrkbd PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
set_target_properties(driver_vrkbd PROPERTIES PREFIX "" OUTPUT_NAME "driver_vrkbd")

add_executable(vrkbd_controller WIN32
  src/controller.cpp
  src/shared_state.cpp
)
target_include_directories(vrkbd_controller PRIVATE src)
target_compile_definitions(vrkbd_controller PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)

# SteamVR expects a driver folder layout.
set(DRIVER_ROOT ${CMAKE_BINARY_DIR}/vrkbd)
add_custom_command(TARGET driver_vrkbd POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory ${DRIVER_ROOT}/bin/win64
  COMMAND ${CMAKE_COMMAND} -E make_directory ${DRIVER_ROOT}/resources/input
  COMMAND ${CMAKE_COMMAND} -E make_directory ${DRIVER_ROOT}/resources/settings
  COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:driver_vrkbd> ${DRIVER_ROOT}/bin/win64/driver_vrkbd.dll
  COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/resources ${DRIVER_ROOT}/resources
  COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_SOURCE_DIR}/driver.vrdrivermanifest ${DRIVER_ROOT}/driver.vrdrivermanifest
)

add_custom_command(TARGET vrkbd_controller POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E make_directory ${CMAKE_BINARY_DIR}/app
  COMMAND ${CMAKE_COMMAND} -E copy $<TARGET_FILE:vrkbd_controller> ${CMAKE_BINARY_DIR}/app/vrkbd_controller.exe
)
