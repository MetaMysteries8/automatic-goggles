# KeyboardVR v3 gamepad/GTAG patch.
# Applied by CI to the verified v2 source archive before compilation.
$ErrorActionPreference = "Stop"

$controller = Join-Path $PSScriptRoot "..\v2src\KeyboardVR\src\controller\main.cpp"
$controller = [IO.Path]::GetFullPath($controller)
if (-not (Test-Path $controller)) { throw "Controller source not found: $controller" }

$text = Get-Content $controller -Raw
$text = $text -replace "`r`n", "`n"

function Replace-Required([string]$old, [string]$new, [string]$label) {
    if (-not $script:text.Contains($old)) {
        throw "KeyboardVR v3 patch failed: expected block not found: $label"
    }
    $script:text = $script:text.Replace($old, $new)
}


# OpenVR is +Y up, +X right, -Z forward. Positive yaw around +Y rotates
# the forward vector (-Z) toward -X. Keep all pose-relative movement and
# hand-orbit math in that same convention.
$oldMove = @'
    p.x += sy * forward + cy * right;
    p.z += -cy * forward + sy * right;
'@
$newMove = @'
    p.x += -sy * forward + cy * right;
    p.z += -cy * forward - sy * right;
'@
$moveMatches = ([regex]::Matches($text, [regex]::Escape($oldMove))).Count
if ($moveMatches -lt 2) {
    throw "KeyboardVR v3 patch failed: expected two yaw-relative movement blocks, found $moveMatches"
}
$text = $text.Replace($oldMove, $newMove)

$oldOrbit = @'
    hand.x = head.x + rx * c - rz * s;
    hand.z = head.z + rx * s + rz * c;
'@
$newOrbit = @'
    hand.x = head.x + rx * c + rz * s;
    hand.z = head.z - rx * s + rz * c;
'@
if (-not $text.Contains($oldOrbit)) {
    throw "KeyboardVR v3 patch failed: OpenVR hand orbit yaw block not found"
}
$text = $text.Replace($oldOrbit, $newOrbit)

# Global UI/mode state.
Replace-Required @'
bool g_mouseLookActive = false;
'@ @'
bool g_mouseLookActive = false;

enum class GamepadPoseMode {
    Velocity,
    SnapTo,
    GtagWalkSim
};

GamepadPoseMode g_gamepadPoseMode = GamepadPoseMode::Velocity;
bool g_verticalStickMode = false;
std::string g_gamepadModeName = "VELOCITY";
'@ "global gamepad mode state"

# Local-space helpers used by SnapTo and GTAG WalkSim.
Replace-Required @'
void RotateHandAroundHeadYaw(
'@ @'
struct LocalOffset {
    float forward = 0.0f;
    float right = 0.0f;
    float up = 0.0f;
};

LocalOffset ToHeadLocal(const keyboardvr::PoseState& head, const keyboardvr::PoseState& hand) {
    const float dx = hand.x - head.x;
    const float dz = hand.z - head.z;
    const float sy = std::sin(head.yaw);
    const float cy = std::cos(head.yaw);
    LocalOffset out{};
    out.forward = -sy * dx - cy * dz;
    out.right = cy * dx - sy * dz;
    out.up = hand.y - head.y;
    return out;
}

void SetHandFromHeadLocal(
    keyboardvr::PoseState& hand,
    const keyboardvr::PoseState& head,
    const LocalOffset& base,
    float extraForward = 0.0f,
    float extraRight = 0.0f,
    float extraUp = 0.0f
) {
    hand.x = head.x;
    hand.y = head.y;
    hand.z = head.z;
    MoveRelativeToYaw(
        hand,
        head.yaw,
        base.forward + extraForward,
        base.right + extraRight,
        base.up + extraUp
    );
}

void MoveWholeRig(keyboardvr::SharedState& s, float forward, float right, float up) {
    const float oldX = s.hmd.x;
    const float oldY = s.hmd.y;
    const float oldZ = s.hmd.z;
    MoveRelativeToYaw(s.hmd, s.hmd.yaw, forward, right, up);
    const float dx = s.hmd.x - oldX;
    const float dy = s.hmd.y - oldY;
    const float dz = s.hmd.z - oldZ;
    s.left.x += dx;  s.left.y += dy;  s.left.z += dz;
    s.right.x += dx; s.right.y += dy; s.right.z += dz;
}

void RecenterHandsAroundCurrentHead(keyboardvr::SharedState& s) {
    const auto d = keyboardvr::DefaultState();
    const LocalOffset leftDefault = ToHeadLocal(d.hmd, d.left);
    const LocalOffset rightDefault = ToHeadLocal(d.hmd, d.right);
    SetHandFromHeadLocal(s.left, s.hmd, leftDefault);
    SetHandFromHeadLocal(s.right, s.hmd, rightDefault);
}

void AlignControllersToHead(keyboardvr::SharedState& s) {
    // A physical gamepad has no independent 3D orientation sensors for each hand.
    // Keep both synthetic controllers pointing where the HMD is facing so position
    // controls and controller direction stay in one intuitive coordinate frame.
    s.left.yaw = s.hmd.yaw;
    s.right.yaw = s.hmd.yaw;
    s.left.pitch = s.hmd.pitch;
    s.right.pitch = s.hmd.pitch;
    s.left.roll = 0.0f;
    s.right.roll = 0.0f;
}

void RotateHandAroundHeadYaw(
'@ "local pose helpers"

# Extra GamepadBridge state.
Replace-Required @'
    std::chrono::steady_clock::time_point lastScan{};
'@ @'
    std::chrono::steady_clock::time_point lastScan{};

    bool prevBack = false;
    bool prevStart = false;
    bool prevWest = false;
    bool prevSouth = false;
    bool prevEast = false;
    bool snapBaseValid = false;
    bool walkBaseValid = false;
    LocalOffset snapLeftBase{};
    LocalOffset snapRightBase{};
    LocalOffset walkLeftBase{};
    LocalOffset walkRightBase{};
    float walkPhase = 0.0f;
    bool walkAirborne = false;
    float walkGroundY = 0.0f;
    float jumpVerticalVelocity = 0.0f;
    float jumpForwardVelocity = 0.0f;
    float jumpRightVelocity = 0.0f;
    float tagLungeTimer = 0.0f;
    bool tagLungeLeft = false;

    void CaptureSnapBase(const keyboardvr::SharedState& s) {
        snapLeftBase = ToHeadLocal(s.hmd, s.left);
        snapRightBase = ToHeadLocal(s.hmd, s.right);
        snapBaseValid = true;
    }

    void CaptureWalkBase(const keyboardvr::SharedState& s) {
        walkLeftBase = ToHeadLocal(s.hmd, s.left);
        walkRightBase = ToHeadLocal(s.hmd, s.right);
        walkBaseValid = true;
        walkPhase = 0.0f;
        walkGroundY = s.hmd.y;
        walkAirborne = false;
        jumpVerticalVelocity = 0.0f;
        jumpForwardVelocity = 0.0f;
        jumpRightVelocity = 0.0f;
        tagLungeTimer = 0.0f;
    }

    void SetMode(GamepadPoseMode mode, keyboardvr::SharedState& s) {
        g_gamepadPoseMode = mode;
        snapBaseValid = false;
        walkBaseValid = false;
        switch (mode) {
            case GamepadPoseMode::Velocity:
                g_gamepadModeName = "VELOCITY";
                break;
            case GamepadPoseMode::SnapTo:
                g_gamepadModeName = "SNAPTO";
                s.leftInput = {};
                s.rightInput = {};
                RecenterHandsAroundCurrentHead(s);
                AlignControllersToHead(s);
                CaptureSnapBase(s);
                break;
            case GamepadPoseMode::GtagWalkSim:
                g_gamepadModeName = "GTAG WALKSIM";
                s.leftInput = {};
                s.rightInput = {};
                RecenterHandsAroundCurrentHead(s);
                AlignControllersToHead(s);
                CaptureWalkBase(s);
                break;
        }
    }
'@ "GamepadBridge mode fields"

$updatePattern = '(?s)    void Update\(keyboardvr::SharedState& s, float dt\) \{.*?\r?\n    \}\r?\n\};'
$updateReplacement = @'
    void Update(keyboardvr::SharedState& s, float dt) {
        Scan();
        if (!pad) return;
        SDL_UpdateGamepads();
        if (!SDL_GamepadConnected(pad)) {
            Scan(true);
            return;
        }

        const float lx = NormalizeAxis(SDL_GetGamepadAxis(pad, SDL_GAMEPAD_AXIS_LEFTX));
        const float ly = NormalizeAxis(SDL_GetGamepadAxis(pad, SDL_GAMEPAD_AXIS_LEFTY));
        const float rx = NormalizeAxis(SDL_GetGamepadAxis(pad, SDL_GAMEPAD_AXIS_RIGHTX));
        const float ry = NormalizeAxis(SDL_GetGamepadAxis(pad, SDL_GAMEPAD_AXIS_RIGHTY));
        const float poseSpeed = s.moveSpeed * dt;
        const float lt = NormalizeTrigger(SDL_GetGamepadAxis(pad, SDL_GAMEPAD_AXIS_LEFT_TRIGGER));
        const float rt = NormalizeTrigger(SDL_GetGamepadAxis(pad, SDL_GAMEPAD_AXIS_RIGHT_TRIGGER));

        const bool back = SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_BACK);
        const bool start = SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_START);
        const bool west = SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_WEST);
        const bool north = SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_NORTH);
        const bool south = SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_SOUTH);
        const bool east = SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_EAST);
        const bool sprinting = SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_LEFT_STICK);

        // Create/Back toggles absolute SnapTo hand positioning.
        if (back && !prevBack) {
            SetMode(
                g_gamepadPoseMode == GamepadPoseMode::SnapTo
                    ? GamepadPoseMode::Velocity
                    : GamepadPoseMode::SnapTo,
                s
            );
        }

        // Options/Start toggles the dedicated Gorilla Tag-style walk simulator.
        if (start && !prevStart) {
            SetMode(
                g_gamepadPoseMode == GamepadPoseMode::GtagWalkSim
                    ? GamepadPoseMode::Velocity
                    : GamepadPoseMode::GtagWalkSim,
                s
            );
        }

        g_verticalStickMode = north;

        // Square/X recaptures anchors. In normal mode it recenters the hands
        // around the current HMD without moving the head.
        if (west && !prevWest) {
            if (g_gamepadPoseMode == GamepadPoseMode::SnapTo) {
                CaptureSnapBase(s);
            } else if (g_gamepadPoseMode == GamepadPoseMode::GtagWalkSim) {
                CaptureWalkBase(s);
            } else {
                RecenterHandsAroundCurrentHead(s);
            }
        }

        prevBack = back;
        prevStart = start;
        prevWest = west;

        const float dpadVertical =
            (SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_DPAD_UP) ? 1.0f : 0.0f)
          - (SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_DPAD_DOWN) ? 1.0f : 0.0f);

        if (SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_DPAD_LEFT)) {
            s.activeTarget = keyboardvr::ActiveTarget::Left;
        }
        if (SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_DPAD_RIGHT)) {
            s.activeTarget = keyboardvr::ActiveTarget::Right;
        }

        if (g_gamepadPoseMode == GamepadPoseMode::Velocity) {
            // Normal mode: each stick continuously moves one hand.
            // Hold Triangle/Y to switch both sticks from X/Z to X/Y,
            // giving direct analog up/down control for both hands at once.
            if (g_verticalStickMode) {
                MoveRelativeToYaw(s.left, s.hmd.yaw, 0.0f, lx * poseSpeed, -ly * poseSpeed);
                MoveRelativeToYaw(s.right, s.hmd.yaw, 0.0f, rx * poseSpeed, -ry * poseSpeed);
            } else {
                MoveRelativeToYaw(s.left, s.hmd.yaw, -ly * poseSpeed, lx * poseSpeed, 0.0f);
                MoveRelativeToYaw(s.right, s.hmd.yaw, -ry * poseSpeed, rx * poseSpeed, 0.0f);
            }

            if (dpadVertical != 0.0f) {
                TargetPose(s).y += dpadVertical * poseSpeed;
            }

            // In general-purpose mode also expose the real sticks as actual
            // virtual-controller thumbsticks, not only tracker motion.
            s.leftInput.joyX = lx;
            s.leftInput.joyY = -ly;
            s.rightInput.joyX = rx;
            s.rightInput.joyY = -ry;
        }
        else if (g_gamepadPoseMode == GamepadPoseMode::SnapTo) {
            if (!snapBaseValid) CaptureSnapBase(s);

            constexpr float kSnapHorizontalReach = 0.65f;
            constexpr float kSnapDepthReach = 0.70f;
            constexpr float kSnapVerticalReach = 0.75f;
            constexpr float kSnapTriggerDrop = 0.85f;

            // Absolute stick -> hand position. Letting go of a stick returns
            // the hand to its captured neutral anchor instead of drifting.
            if (g_verticalStickMode) {
                SetHandFromHeadLocal(
                    s.left, s.hmd, snapLeftBase,
                    0.0f,
                    lx * kSnapHorizontalReach,
                    -ly * kSnapVerticalReach - lt * kSnapTriggerDrop
                );
                SetHandFromHeadLocal(
                    s.right, s.hmd, snapRightBase,
                    0.0f,
                    rx * kSnapHorizontalReach,
                    -ry * kSnapVerticalReach - rt * kSnapTriggerDrop
                );
            } else {
                SetHandFromHeadLocal(
                    s.left, s.hmd, snapLeftBase,
                    -ly * kSnapDepthReach,
                    lx * kSnapHorizontalReach,
                    -lt * kSnapTriggerDrop
                );
                SetHandFromHeadLocal(
                    s.right, s.hmd, snapRightBase,
                    -ry * kSnapDepthReach,
                    rx * kSnapHorizontalReach,
                    -rt * kSnapTriggerDrop
                );
            }

            // D-pad trims the neutral vertical anchor of the selected hand.
            // If HEAD is selected, it moves the whole head height while both
            // hands stay locked relative to it.
            if (dpadVertical != 0.0f) {
                if (s.activeTarget == keyboardvr::ActiveTarget::Left) {
                    snapLeftBase.up += dpadVertical * poseSpeed;
                } else if (s.activeTarget == keyboardvr::ActiveTarget::Right) {
                    snapRightBase.up += dpadVertical * poseSpeed;
                } else {
                    s.hmd.y += dpadVertical * poseSpeed;
                }
            }

            s.leftInput.joyX = lx;
            s.leftInput.joyY = -ly;
            s.rightInput.joyX = rx;
            s.rightInput.joyY = -ry;
        }
        else {
            // GTAG WalkSim:
            // LS = move/strafe, L3 = sprint, Cross/A = directional jump,
            // RS X = turn, RS Y = standing/crouch height, Circle/B = tag lunge.
            if (!walkBaseValid) CaptureWalkBase(s);

            const float sprintMultiplier = sprinting ? 2.10f : 1.0f;
            const float moveScale = s.moveSpeed * 1.55f * sprintMultiplier * dt;
            const float verticalScale = s.moveSpeed * 0.70f * dt;

            // Directional jump impulse comes from the left stick at takeoff.
            // Forward/back/diagonal jumps therefore fall out naturally from
            // the same stick you are already using to run.
            if (south && !prevSouth && !walkAirborne) {
                walkGroundY = s.hmd.y;
                walkAirborne = true;
                jumpVerticalVelocity = sprinting ? 3.85f : 3.45f;
                const float jumpHorizontal = sprinting ? 3.10f : 2.25f;
                jumpForwardVelocity = -ly * jumpHorizontal;
                jumpRightVelocity = lx * jumpHorizontal;
            }

            // Manual tag lunge. Use selected hand; HEAD defaults to right hand.
            if (east && !prevEast) {
                tagLungeLeft = s.activeTarget == keyboardvr::ActiveTarget::Left;
                tagLungeTimer = 0.24f;
            }

            prevSouth = south;
            prevEast = east;

            // Ground movement remains available in air, but reduced slightly.
            const float airControl = walkAirborne ? 0.42f : 1.0f;
            MoveWholeRig(
                s,
                -ly * moveScale * airControl,
                lx * moveScale * airControl,
                0.0f
            );

            // Right stick / D-pad adjust standing height only while grounded.
            if (!walkAirborne) {
                const float manualY =
                    -ry * verticalScale + dpadVertical * verticalScale;
                if (manualY != 0.0f) {
                    MoveWholeRig(s, 0.0f, 0.0f, manualY);
                    walkGroundY = s.hmd.y;
                }
            }

            // Simple deterministic jump arc at the tracking-rig layer.
            if (walkAirborne) {
                constexpr float kGravity = 9.81f;
                constexpr float kAirDrag = 2.35f;

                MoveWholeRig(
                    s,
                    jumpForwardVelocity * dt,
                    jumpRightVelocity * dt,
                    jumpVerticalVelocity * dt
                );

                jumpVerticalVelocity -= kGravity * dt;
                const float drag = std::max(0.0f, 1.0f - kAirDrag * dt);
                jumpForwardVelocity *= drag;
                jumpRightVelocity *= drag;

                if (jumpVerticalVelocity <= 0.0f && s.hmd.y <= walkGroundY) {
                    const float correction = walkGroundY - s.hmd.y;
                    MoveWholeRig(s, 0.0f, 0.0f, correction);
                    walkAirborne = false;
                    jumpVerticalVelocity = 0.0f;
                    jumpForwardVelocity = 0.0f;
                    jumpRightVelocity = 0.0f;
                }
            }

            const float turnStep = DegToRad(s.rotationSpeed * 1.20f * rx * dt);
            s.hmd.yaw = keyboardvr::WrapAngle(s.hmd.yaw - turnStep);

            const float walkMagnitude = std::clamp(std::sqrt(lx * lx + ly * ly), 0.0f, 1.0f);
            const float gaitSpeed = sprinting ? 1.55f : 1.0f;
            walkPhase += dt * (4.5f + 4.0f * walkMagnitude) * gaitSpeed;
            const float wave = std::sin(walkPhase);
            const float swingScale = sprinting ? 0.28f : 0.20f;
            const float swing = wave * swingScale * walkMagnitude;
            const float leftLift = std::max(0.0f, wave) * 0.065f * walkMagnitude;
            const float rightLift = std::max(0.0f, -wave) * 0.065f * walkMagnitude;

            constexpr float kTagLungeDuration = 0.24f;
            float tagLeftForward = 0.0f;
            float tagRightForward = 0.0f;
            if (tagLungeTimer > 0.0f) {
                const float progress =
                    1.0f - std::clamp(tagLungeTimer / kTagLungeDuration, 0.0f, 1.0f);
                const float reach = std::sin(progress * kPi) * 0.55f;
                if (tagLungeLeft) tagLeftForward = reach;
                else tagRightForward = reach;
                tagLungeTimer = std::max(0.0f, tagLungeTimer - dt);
            }

            SetHandFromHeadLocal(
                s.left, s.hmd, walkLeftBase,
                swing + tagLeftForward, 0.0f, leftLift
            );
            SetHandFromHeadLocal(
                s.right, s.hmd, walkRightBase,
                -swing + tagRightForward, 0.0f, rightLift
            );

            // WalkSim consumes the locomotion controls so the VR title does
            // not simultaneously apply thumbstick locomotion.
            s.leftInput.joyX = 0.0f;
            s.leftInput.joyY = 0.0f;
            s.rightInput.joyX = 0.0f;
            s.rightInput.joyY = 0.0f;
        }

        // Keep controller direction synchronized with head direction in every
        // physical-gamepad pose mode. This prevents hands from being in the
        // correct place while still pointing along an old world-space rotation.
        AlignControllersToHead(s);

        // In SnapTo, analog triggers are dedicated hand-height controls.
        // In the other modes they remain normal VR trigger inputs.
        if (g_gamepadPoseMode != GamepadPoseMode::SnapTo) {
            s.leftInput.trigger = std::max(s.leftInput.trigger, lt);
            s.rightInput.trigger = std::max(s.rightInput.trigger, rt);
            if (lt > 0.80f) s.leftInput.buttons |= keyboardvr::Button_Trigger;
            if (rt > 0.80f) s.rightInput.buttons |= keyboardvr::Button_Trigger;
        }

        if (SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_LEFT_SHOULDER)) {
            s.leftInput.grip = 1.0f;
            s.leftInput.buttons |= keyboardvr::Button_Grip;
        }
        if (SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER)) {
            s.rightInput.grip = 1.0f;
            s.rightInput.buttons |= keyboardvr::Button_Grip;
        }
        if (g_gamepadPoseMode != GamepadPoseMode::GtagWalkSim &&
            SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_LEFT_STICK)) {
            s.leftInput.buttons |= keyboardvr::Button_Joystick;
        }
        if (SDL_GetGamepadButton(pad, SDL_GAMEPAD_BUTTON_RIGHT_STICK)) {
            s.rightInput.buttons |= keyboardvr::Button_Joystick;
        }

        if (g_gamepadPoseMode != GamepadPoseMode::GtagWalkSim) {
            MergeSelectedFaceButtons(pad, s);
        }

        // DualSense/DualShock touchpad (and any SDL gamepad touchpad) = head look.
        if (SDL_GetNumGamepadTouchpads(pad) > 0 && SDL_GetNumGamepadTouchpadFingers(pad, 0) > 0) {
            bool down = false;
            float x = 0.0f, y = 0.0f, pressure = 0.0f;
            if (SDL_GetGamepadTouchpadFinger(pad, 0, 0, &down, &x, &y, &pressure)) {
                if (down && touchDown) {
                    ApplyHeadLook(
                        s,
                        -(x - touchX) * kTouchLookRadiansPerUnit,
                        -(y - touchY) * kTouchLookRadiansPerUnit
                    );
                }
                touchDown = down;
                touchX = x;
                touchY = y;
            }
        } else {
            touchDown = false;
        }
    }
};
'@

$regex = [regex]::new($updatePattern)
if (-not $regex.IsMatch($text)) {
    throw "KeyboardVR v3 patch failed: GamepadBridge::Update block not found"
}
$text = $regex.Replace($text, $updateReplacement, 1)

# Console status + help.
Replace-Required @'
                s.moveSpeed, s.rotationSpeed, g_mouseLookActive ? "ON" : "off");
'@ @'
                s.moveSpeed, s.rotationSpeed, g_mouseLookActive ? "ON" : "off");
    std::printf("Gamepad mode: %-12.12s   Vertical-stick modifier: %-3s                 \n",
                g_gamepadModeName.c_str(), g_verticalStickMode ? "ON" : "off");
'@ "console mode status"

Replace-Required @'
    std::printf("Gamepad: LS=left hand X/Z | RS=right hand X/Z | D-pad up/down=selected Y\n");
'@ @'
    std::printf("Gamepad: Create=SnapTo | Options=GTAG WalkSim | modes reset hand anchors \n");
    std::printf("Normal: LS/RS hands X/Z | hold Triangle for analog X/Y + up/down         \n");
    std::printf("SnapTo: sticks=absolute X/Z | L2/R2=analog hand height (squeeze=lower)  \n");
    std::printf("         hold Triangle for absolute X/Y positioning too                  \n");
    std::printf("WalkSim: LS move | L3 sprint | Cross jump | Circle tag lunge              \n");
    std::printf("         jump direction follows LS | RS X turn | RS Y body height         \n");
'@ "console gamepad movement help"

Replace-Required @'
    std::printf("L2/R2 triggers | L1/R1 grips | stick clicks | face buttons=selected hand\n");
'@ @'
    std::printf("Hands auto-face with HMD yaw/pitch | roll neutral                        \n");
    std::printf("L2/R2 triggers* | L1/R1 grips | stick clicks | D-pad Y trim/select       \n");
'@ "console gamepad button help"

# Visualizer status includes the active gamepad control mode.
Replace-Required @'
            status += L"   |   white ring = selected   |   grid = 1 meter";
'@ @'
            status += L"   |   mode: ";
            status += std::wstring(g_gamepadModeName.begin(), g_gamepadModeName.end());
            status += L"   |   white ring = selected   |   grid = 1 meter";
'@ "visualizer mode status"

[IO.File]::WriteAllText($controller, $text)
Write-Host "Applied KeyboardVR v3.4 yaw-sign + deterministic mode-reset patch."
