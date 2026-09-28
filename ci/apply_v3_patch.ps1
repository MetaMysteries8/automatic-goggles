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
$moveX = "p.x += sy * forward + cy * right;"
$moveZ = "p.z += -cy * forward + sy * right;"
$moveXCount = ([regex]::Matches($text, [regex]::Escape($moveX))).Count
$moveZCount = ([regex]::Matches($text, [regex]::Escape($moveZ))).Count
if ($moveXCount -lt 2 -or $moveZCount -lt 2) {
    throw "KeyboardVR v3 patch failed: yaw movement lines missing (x=$moveXCount z=$moveZCount)"
}
$text = $text.Replace($moveX, "p.x += -sy * forward + cy * right;")
$text = $text.Replace($moveZ, "p.z += -cy * forward - sy * right;")

$orbitX = "hand.x = head.x + rx * c - rz * s;"
$orbitZ = "hand.z = head.z + rx * s + rz * c;"
if (-not $text.Contains($orbitX) -or -not $text.Contains($orbitZ)) {
    throw "KeyboardVR v3 patch failed: OpenVR hand orbit yaw lines not found"
}
$text = $text.Replace($orbitX, "hand.x = head.x + rx * c + rz * s;")
$text = $text.Replace($orbitZ, "hand.z = head.z - rx * s + rz * c;")

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
    float walkJumpTimer = 0.0f;
    float walkHeightTrim = 0.0f;

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
        walkJumpTimer = 0.0f;
        walkHeightTrim = 0.0f;
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
            // GTAG WalkSim is intentionally ARM-DRIVEN ONLY.
            //
            // We never translate or rotate the HMD here. Gorilla-style movement
            // should come from the VR title reacting to synthetic hand contacts.
            // If the game moves the HMD/body as a result, the next arm pose is
            // generated relative to that updated HMD automatically.
            if (!walkBaseValid) CaptureWalkBase(s);

            const float intentForward = -ly;
            const float intentRight = lx;
            const float walkMagnitude =
                std::clamp(std::sqrt(lx * lx + ly * ly), 0.0f, 1.0f);

            // L3 means stronger/faster arm strokes, not direct body speed.
            const float gaitSpeed = sprinting ? 1.75f : 1.0f;
            const float gaitHz = (4.6f + 3.8f * walkMagnitude) * gaitSpeed;
            walkPhase += dt * gaitHz;

            // Right-stick Y adjusts both hand anchors up/down instead of moving
            // the head. D-pad up/down gives a coarse trim as well.
            walkHeightTrim += (-ry * 0.55f + dpadVertical * 0.35f) * dt;
            walkHeightTrim = std::clamp(walkHeightTrim, -0.75f, 0.35f);

            // Cross/A = a simultaneous two-arm floor push. The stick direction
            // selects the desired jump direction. Centered LS gives a vertical
            // shove. The game, not KeyboardVR, decides the resulting body motion.
            if (south && !prevSouth) {
                walkJumpTimer = 0.30f;
            }

            // Circle/B = manual tag reach with the selected hand.
            if (east && !prevEast) {
                tagLungeLeft = s.activeTarget == keyboardvr::ActiveTarget::Left;
                tagLungeTimer = 0.24f;
            }

            prevSouth = south;
            prevEast = east;

            constexpr float kJumpDuration = 0.30f;
            constexpr float kTagLungeDuration = 0.24f;

            float leftForward = 0.0f;
            float leftRight = 0.0f;
            float leftUp = walkHeightTrim;
            float rightForward = 0.0f;
            float rightRight = 0.0f;
            float rightUp = walkHeightTrim;

            if (walkJumpTimer > 0.0f) {
                // Both hands dive downward and opposite the requested travel
                // direction. On a floor contact, that is the kind of relative
                // hand motion Gorilla Tag can turn into a jump/push.
                const float progress =
                    1.0f - std::clamp(walkJumpTimer / kJumpDuration, 0.0f, 1.0f);
                const float pulse = std::sin(progress * kPi);
                const float jumpReach = sprinting ? 0.80f : 0.62f;
                const float jumpDown = sprinting ? 1.20f : 1.05f;

                leftForward  += -intentForward * jumpReach * pulse;
                rightForward += -intentForward * jumpReach * pulse;
                leftRight    += -intentRight * jumpReach * pulse;
                rightRight   += -intentRight * jumpReach * pulse;
                leftUp       += -jumpDown * pulse;
                rightUp      += -jumpDown * pulse;

                walkJumpTimer = std::max(0.0f, walkJumpTimer - dt);
            }
            else if (walkMagnitude > 0.01f) {
                // Alternating ground strokes:
                // contact half-cycle = down + opposite requested movement;
                // recovery half-cycle = up + forward into the next stroke.
                const float strokeScale = sprinting ? 0.72f : 0.52f;
                const float downReach = sprinting ? 1.08f : 0.92f;
                const float recoveryLift = sprinting ? 0.20f : 0.14f;

                const float leftWave = std::sin(walkPhase);
                const float rightWave = -leftWave;

                auto ApplyStroke = [&](float wave, float& fwd, float& right, float& up) {
                    const float contact = std::max(0.0f, wave);
                    const float recovery = std::max(0.0f, -wave);

                    fwd += -intentForward * strokeScale * walkMagnitude * contact;
                    right += -intentRight * strokeScale * walkMagnitude * contact;
                    up += -downReach * walkMagnitude * contact;

                    // Recover the hand forward/up without trying to propel.
                    fwd += intentForward * 0.26f * walkMagnitude * recovery;
                    right += intentRight * 0.26f * walkMagnitude * recovery;
                    up += recoveryLift * walkMagnitude * recovery;
                };

                ApplyStroke(leftWave, leftForward, leftRight, leftUp);
                ApplyStroke(rightWave, rightForward, rightRight, rightUp);
            }

            // Tag lunge layers on top of the current gait/jump pose.
            if (tagLungeTimer > 0.0f) {
                const float progress =
                    1.0f - std::clamp(tagLungeTimer / kTagLungeDuration, 0.0f, 1.0f);
                const float reach = std::sin(progress * kPi) * 0.58f;
                if (tagLungeLeft) leftForward += reach;
                else rightForward += reach;
                tagLungeTimer = std::max(0.0f, tagLungeTimer - dt);
            }

            SetHandFromHeadLocal(
                s.left, s.hmd, walkLeftBase,
                leftForward, leftRight, leftUp
            );
            SetHandFromHeadLocal(
                s.right, s.hmd, walkRightBase,
                rightForward, rightRight, rightUp
            );

            // WalkSim consumes all locomotion axes/buttons it uses. The HMD is
            // untouched here: no fake translation, jump arc, crouch, or snap turn.
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
    std::printf("WalkSim: ARM-ONLY | LS=stroke direction | L3=stronger/faster strokes      \n");
    std::printf("         Cross=2-arm jump push | Circle=tag lunge | RS Y=hand height trim \n");
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
Write-Host "Applied KeyboardVR v3.5 arm-driven Gorilla locomotion patch."
