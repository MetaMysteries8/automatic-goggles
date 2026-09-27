#pragma once
#include <windows.h>
#include <cstdint>

namespace vrkbd {

constexpr wchar_t kMappingName[] = L"Local\\VRKeyboardEmulatorState_v1";
constexpr uint32_t kMagic = 0x564B4244; // VKBD
constexpr uint32_t kVersion = 1;

enum class Device : uint32_t { Head = 0, Left = 1, Right = 2 };

struct PoseState {
    double x, y, z;
    double yaw, pitch, roll; // radians
};

struct ControllerState {
    PoseState pose;
    float trigger;
    float grip;
    float joyX;
    float joyY;
    uint32_t buttons; // bit 0 primary, 1 secondary, 2 menu, 3 stickClick
};

struct SharedState {
    uint32_t magic;
    uint32_t version;
    volatile LONG sequence;
    volatile LONG controllerAlive;
    PoseState head;
    ControllerState left;
    ControllerState right;
};

struct Mapping {
    HANDLE handle = nullptr;
    SharedState* state = nullptr;
};

Mapping OpenOrCreateMapping(bool initialize);
void CloseMapping(Mapping& m);
void InitializeDefaults(SharedState& s);

} // namespace vrkbd
