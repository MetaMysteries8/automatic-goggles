# KeyboardVR v3.6

KeyboardVR is a Windows SteamVR virtual-device driver and desktop control bridge for using VR software without a physical VR headset.

It exposes a virtual HMD plus left/right tracked controllers, supports keyboard/mouse control, and supports real gamepads through SDL3 including PS5 DualSense touchpad head-look.

## v3.6 highlights

- **Yaw/anchor fixes**
  - hand positions now use the same OpenVR +Y yaw convention as the HMD quaternion
  - turning the head and orbiting the hands now travel in the same direction
  - entering SnapTo always restores the two hands to the canonical neutral offsets around the current HMD before capturing anchors
  - entering GTAG WalkSim does the same reset before its gait/jump/tag simulation starts
  - switching directly between SnapTo and WalkSim also gets a clean hand reset


- **Dual WalkSim modes**
  - Options/Start enters/exits WalkSim
  - **R3 while in WalkSim toggles Modern ↔ Legacy**
  - both variants reset the hands to neutral anchors when selected
- **Legacy WalkSim** (kept intentionally as a joke)
  - left stick directly moves the virtual body/HMD
  - right stick X directly turns the HMD
  - right stick Y moves body height
  - L3 = direct sprint
  - Cross/A = fake directional jump arc
  - Circle/B = exaggerated tag-punch lunge
  - this is intentionally not how Gorilla Tag locomotion really works

- **GTAG WalkSim mode — arm-driven**
  - WalkSim does **not directly translate or rotate the HMD**
  - left stick controls the direction of alternating synthetic arm pushes
  - the contact half of each stroke moves a hand down and opposite the requested travel direction
  - the recovery half brings that hand back up/forward for the next stroke
  - Gorilla Tag (or another arm-locomotion title) is expected to move the body from its own hand-collision physics
  - if the game moves the HMD/body, subsequent synthetic hand poses automatically follow the updated HMD
  - **L3 held = sprint strokes**: faster cycle, longer push, deeper reach
  - **Cross/A = directional jump push**: both hands shove downward together; left-stick direction biases the shove for forward/back/diagonal jumps
  - **Circle/B = manual tag lunge** with the selected hand
  - **right stick Y = hand-height trim**, so you can lower/raise the whole WalkSim stroke envelope without moving the head
  - D-pad up/down also trims WalkSim hand height
  - touchpad/mouse remain the head-look controls
- **SnapTo mode**: Create/Back toggles absolute hand positioning.
  - each stick maps directly to a hand position around the HMD instead of accumulating movement over time
  - letting go of the stick returns that hand to its captured neutral anchor
  - hold Triangle/Y to switch both sticks to an X/Y plane for direct analog up/down placement
  - **L2 controls left-hand height and R2 controls right-hand height**
  - trigger travel is analog: a light squeeze lowers the matching hand a little; a full squeeze lowers it by about 0.85 m
  - in SnapTo, L2/R2 are consumed for height control so they do not accidentally fire VR trigger actions
  - Square/X recaptures the current neutral anchors
- **Improved normal gamepad mode**
  - left stick moves left hand, right stick moves right hand
  - hold Triangle/Y for analog vertical hand movement
  - Square/X recenters the hands around the current HMD
  - D-pad left/right selects left/right hand
  - D-pad up/down vertically trims the selected target
  - physical stick values are also exposed to SteamVR as real virtual-controller thumbstick axes
- L2/R2 = left/right trigger
- L1/R1 = left/right grip
- L3/R3 = corresponding virtual thumbstick click
- South/East face buttons = A/B on selected hand
- DualSense/DualShock touchpad drag = head look
- right mouse drag = head look
- **controller direction automatically follows the HMD**
  - both virtual hands inherit head yaw and pitch while a physical gamepad is driving the rig
  - controller roll stays neutral
  - applies to Velocity, SnapTo, and GTAG WalkSim so hand position and facing direction stay aligned
- live top/front/side rig visualizer showing the active gamepad mode
- virtual 4 m x 4 m standing/chaperone universe
- Index/Knuckles-compatible controller rebinding fallback

## Install the prebuilt Windows release

1. Extract `KeyboardVR-v3.6-Windows-x64.zip`.
2. Fully close SteamVR.
3. Double-click `Install Driver.bat`.
4. Run `KeyboardVR.exe`.
5. Start SteamVR.

No compiler or local build step is required for the release ZIP.

## Keyboard controls

- `1 / 2 / 3` — select head / left hand / right hand
- `WASD` — move selected device
- `R/F` — up/down
- arrows — yaw/pitch
- `Z/X` — roll
- right mouse drag — head look
- `G` — rig-follow
- `F1` — reset rig
- `F2` — reset selected device
- `F3` — show/hide rig visualizer
- Shift — fast movement
- Ctrl — precision movement

Selected virtual-controller keyboard inputs:

- `C` — trigger
- `V` — grip
- `B` — A
- `N` — B
- `M` — system/menu
- `,` — thumbstick click
- numpad `4/6/8/2` — thumbstick axes

## Notes about GTAG WalkSim

WalkSim now only synthesizes tracked hand poses. It intentionally does not fake player translation, jump arcs, crouching, or snap-turn movement at the HMD layer. Actual body movement depends on the game's own locomotion/collision code reacting to the virtual hands, so the exact stroke depth and timing may still need tuning against Gorilla Tag itself.
