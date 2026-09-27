#include <openvr_driver.h>
#include "shared_state.h"
#include <windows.h>
#include <array>
#include <cmath>
#include <cstring>
#include <string>

using namespace vrkbd;

namespace {

vr::HmdQuaternion_t Q(double w, double x, double y, double z) { return {w,x,y,z}; }

vr::HmdQuaternion_t Euler(double yaw, double pitch, double roll) {
    const double cy = std::cos(yaw * 0.5), sy = std::sin(yaw * 0.5);
    const double cp = std::cos(pitch * 0.5), sp = std::sin(pitch * 0.5);
    const double cr = std::cos(roll * 0.5), sr = std::sin(roll * 0.5);
    return Q(cr*cp*cy + sr*sp*sy,
             sr*cp*cy - cr*sp*sy,
             cr*sp*cy + sr*cp*sy,
             cr*cp*sy - sr*sp*cy);
}

vr::DriverPose_t MakePose(const PoseState& p) {
    vr::DriverPose_t out{};
    out.poseIsValid = true;
    out.deviceIsConnected = true;
    out.result = vr::TrackingResult_Running_OK;
    out.qWorldFromDriverRotation = Q(1,0,0,0);
    out.qDriverFromHeadRotation = Q(1,0,0,0);
    out.qRotation = Euler(p.yaw, p.pitch, p.roll);
    out.vecPosition[0] = p.x;
    out.vecPosition[1] = p.y;
    out.vecPosition[2] = p.z;
    return out;
}

class VirtualDisplay final : public vr::IVRDisplayComponent {
public:
    void GetWindowBounds(int32_t* x, int32_t* y, uint32_t* w, uint32_t* h) override {
        *x = 0; *y = 0; *w = 1920; *h = 1080;
    }
    bool IsDisplayOnDesktop() override { return false; }
    bool IsDisplayRealDisplay() override { return false; }
    void GetRecommendedRenderTargetSize(uint32_t* w, uint32_t* h) override { *w = 1512; *h = 1680; }
    void GetEyeOutputViewport(vr::EVREye eye, uint32_t* x, uint32_t* y, uint32_t* w, uint32_t* h) override {
        *x = eye == vr::Eye_Left ? 0 : 960; *y = 0; *w = 960; *h = 1080;
    }
    void GetProjectionRaw(vr::EVREye, float* l, float* r, float* t, float* b) override {
        *l = -1.0f; *r = 1.0f; *t = -1.0f; *b = 1.0f;
    }
    vr::DistortionCoordinates_t ComputeDistortion(vr::EVREye, float u, float v) override {
        vr::DistortionCoordinates_t d{};
        d.rfRed[0]=d.rfGreen[0]=d.rfBlue[0]=u;
        d.rfRed[1]=d.rfGreen[1]=d.rfBlue[1]=v;
        return d;
    }
    bool ComputeInverseDistortion(vr::HmdVector2_t* result, vr::EVREye, uint32_t, float u, float v) override {
        result->v[0] = u; result->v[1] = v;
        return true;
    }
};

class Hmd final : public vr::ITrackedDeviceServerDriver {
public:
    Hmd(SharedState* s): state_(s) {}
    vr::EVRInitError Activate(uint32_t id) override {
        id_ = id;
        auto p = vr::VRProperties()->TrackedDeviceToPropertyContainer(id_);
        vr::VRProperties()->SetStringProperty(p, vr::Prop_ModelNumber_String, "VRKBD Virtual HMD");
        vr::VRProperties()->SetStringProperty(p, vr::Prop_RenderModelName_String, "generic_hmd");
        vr::VRProperties()->SetStringProperty(p, vr::Prop_ManufacturerName_String, "VRKeyboardEmulator");
        vr::VRProperties()->SetStringProperty(p, vr::Prop_SerialNumber_String, "VRKBD-HMD-001");
        vr::VRProperties()->SetBoolProperty(p, vr::Prop_IsOnDesktop_Bool, false);
        vr::VRProperties()->SetFloatProperty(p, vr::Prop_DisplayFrequency_Float, 90.0f);
        vr::VRProperties()->SetFloatProperty(p, vr::Prop_UserIpdMeters_Float, 0.064f);
        vr::VRProperties()->SetBoolProperty(p, vr::Prop_NeverTracked_Bool, false);
        return vr::VRInitError_None;
    }
    void Deactivate() override { id_ = vr::k_unTrackedDeviceIndexInvalid; }
    void EnterStandby() override {}
    void* GetComponent(const char* name) override {
        if (std::strcmp(name, vr::IVRDisplayComponent_Version) == 0) return &display_;
        return nullptr;
    }
    void DebugRequest(const char*, char* response, uint32_t n) override { if (n) response[0] = 0; }
    vr::DriverPose_t GetPose() override { return MakePose(state_->head); }
    void Update() {
        if (id_ != vr::k_unTrackedDeviceIndexInvalid)
            vr::VRServerDriverHost()->TrackedDevicePoseUpdated(id_, GetPose(), sizeof(vr::DriverPose_t));
    }
private:
    SharedState* state_;
    uint32_t id_ = vr::k_unTrackedDeviceIndexInvalid;
    VirtualDisplay display_;
};

class Controller final : public vr::ITrackedDeviceServerDriver {
public:
    Controller(SharedState* s, bool left): state_(s), left_(left) {}
    vr::EVRInitError Activate(uint32_t id) override {
        id_ = id;
        auto p = vr::VRProperties()->TrackedDeviceToPropertyContainer(id_);
        const char* side = left_ ? "Left" : "Right";
        const char* role = left_ ? "left_hand" : "right_hand";
        vr::VRProperties()->SetStringProperty(p, vr::Prop_ModelNumber_String, "VRKBD Virtual Controller");
        vr::VRProperties()->SetStringProperty(p, vr::Prop_ManufacturerName_String, "VRKeyboardEmulator");
        std::string serial = std::string("VRKBD-") + side + "-001";
        vr::VRProperties()->SetStringProperty(p, vr::Prop_SerialNumber_String, serial.c_str());
        vr::VRProperties()->SetStringProperty(p, vr::Prop_InputProfilePath_String, "{vrkbd}/input/virtual_controller_profile.json");
        vr::VRProperties()->SetStringProperty(p, vr::Prop_ControllerType_String, "vrkbd_controller");
        vr::VRProperties()->SetInt32Property(p, vr::Prop_ControllerRoleHint_Int32,
            left_ ? vr::TrackedControllerRole_LeftHand : vr::TrackedControllerRole_RightHand);
        vr::VRProperties()->SetStringProperty(p, vr::Prop_RegisteredDeviceType_String, role);

        auto* in = vr::VRDriverInput();
        in->CreateBooleanComponent(p, "/input/system/click", &system_);
        in->CreateBooleanComponent(p, "/input/application_menu/click", &menu_);
        in->CreateBooleanComponent(p, "/input/a/click", &primary_);
        in->CreateBooleanComponent(p, "/input/b/click", &secondary_);
        in->CreateBooleanComponent(p, "/input/joystick/click", &stickClick_);
        in->CreateScalarComponent(p, "/input/trigger/value", &trigger_, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedOneSided);
        in->CreateScalarComponent(p, "/input/grip/value", &grip_, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedOneSided);
        in->CreateScalarComponent(p, "/input/joystick/x", &joyX_, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedTwoSided);
        in->CreateScalarComponent(p, "/input/joystick/y", &joyY_, vr::VRScalarType_Absolute, vr::VRScalarUnits_NormalizedTwoSided);
        return vr::VRInitError_None;
    }
    void Deactivate() override { id_ = vr::k_unTrackedDeviceIndexInvalid; }
    void EnterStandby() override {}
    void* GetComponent(const char*) override { return nullptr; }
    void DebugRequest(const char*, char* response, uint32_t n) override { if (n) response[0] = 0; }
    vr::DriverPose_t GetPose() override { return MakePose(Current().pose); }
    void Update() {
        if (id_ == vr::k_unTrackedDeviceIndexInvalid) return;
        vr::VRServerDriverHost()->TrackedDevicePoseUpdated(id_, GetPose(), sizeof(vr::DriverPose_t));
        const auto& c = Current();
        auto* in = vr::VRDriverInput();
        in->UpdateBooleanComponent(primary_, (c.buttons & 1u) != 0, 0);
        in->UpdateBooleanComponent(secondary_, (c.buttons & 2u) != 0, 0);
        in->UpdateBooleanComponent(menu_, (c.buttons & 4u) != 0, 0);
        in->UpdateBooleanComponent(system_, false, 0);
        in->UpdateBooleanComponent(stickClick_, (c.buttons & 8u) != 0, 0);
        in->UpdateScalarComponent(trigger_, c.trigger, 0);
        in->UpdateScalarComponent(grip_, c.grip, 0);
        in->UpdateScalarComponent(joyX_, c.joyX, 0);
        in->UpdateScalarComponent(joyY_, c.joyY, 0);
    }
private:
    const ControllerState& Current() const { return left_ ? state_->left : state_->right; }
    SharedState* state_;
    bool left_;
    uint32_t id_ = vr::k_unTrackedDeviceIndexInvalid;
    vr::VRInputComponentHandle_t system_=0, menu_=0, primary_=0, secondary_=0, stickClick_=0;
    vr::VRInputComponentHandle_t trigger_=0, grip_=0, joyX_=0, joyY_=0;
};

class Provider final : public vr::IServerTrackedDeviceProvider {
public:
    vr::EVRInitError Init(vr::IVRDriverContext* ctx) override {
        VR_INIT_SERVER_DRIVER_CONTEXT(ctx);
        mapping_ = OpenOrCreateMapping(false);
        if (!mapping_.state) return vr::VRInitError_Driver_Failed;
        hmd_ = new Hmd(mapping_.state);
        left_ = new Controller(mapping_.state, true);
        right_ = new Controller(mapping_.state, false);
        vr::VRServerDriverHost()->TrackedDeviceAdded("VRKBD-HMD-001", vr::TrackedDeviceClass_HMD, hmd_);
        vr::VRServerDriverHost()->TrackedDeviceAdded("VRKBD-LEFT-001", vr::TrackedDeviceClass_Controller, left_);
        vr::VRServerDriverHost()->TrackedDeviceAdded("VRKBD-RIGHT-001", vr::TrackedDeviceClass_Controller, right_);
        vr::VRDriverLog()->Log("VRKeyboardEmulator: virtual HMD + controllers registered");
        return vr::VRInitError_None;
    }
    void Cleanup() override {
        delete hmd_; delete left_; delete right_;
        hmd_=nullptr; left_=nullptr; right_=nullptr;
        CloseMapping(mapping_);
        VR_CLEANUP_SERVER_DRIVER_CONTEXT();
    }
    const char* const* GetInterfaceVersions() override { return vr::k_InterfaceVersions; }
    void RunFrame() override {
        if (!mapping_.state) return;
        hmd_->Update(); left_->Update(); right_->Update();
    }
    bool ShouldBlockStandbyMode() override { return true; }
    void EnterStandby() override {}
    void LeaveStandby() override {}
private:
    Mapping mapping_{};
    Hmd* hmd_=nullptr;
    Controller* left_=nullptr;
    Controller* right_=nullptr;
};

Provider g_provider;

} // namespace

extern "C" __declspec(dllexport) void* HmdDriverFactory(const char* name, int* error) {
    if (std::strcmp(name, vr::IServerTrackedDeviceProvider_Version) == 0) return &g_provider;
    if (error) *error = vr::VRInitError_Init_InterfaceNotFound;
    return nullptr;
}
