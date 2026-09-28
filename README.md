# KeyboardVR v3

KeyboardVR is a Windows SteamVR virtual-device driver and desktop control bridge for using VR software without a physical VR headset.

It exposes a virtual HMD plus left/right tracked controllers, supports keyboard/mouse control, and supports real gamepads through SDL3 including PS5 DualSense touchpad head-look.

## v3 highlights

- **GTAG WalkSim mode**: Options/Start toggles a controller-oriented locomotion mode intended for Gorilla Tag-style testing without real VR hardware.
  - left stick = walk / strafe the whole virtual rig
  - right stick X = turn
  - right stick Y = raise/lower the rig (standing height / crouch-style control)
  - D-pad up/down = extra vertical trim
  - hands automatically alternate through a walking swing while moving
  - physical stick axes are not also forwarded as VR thumbstick locomotion in WalkSim, avoiding accidental double movement
- **SnapTo mode**: Create/Back toggles absolute hand positioning.
  - each stick maps directly to a hand position around the HMD instead of accumulating movement over time
  - letting go of the stick returns that hand to its captured neutral anchor
  - hold Triangle/Y to switch both sticks to an X/Y plane for direct analog up/down placement
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
- live top/front/side rig visualizer showing the active gamepad mode
- virtual 4 m x 4 m standing/chaperone universe
- Index/Knuckles-compatible controller rebinding fallback

## Install the prebuilt Windows release

1. Extract `KeyboardVR-v3-Windows-x64.zip`.
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

WalkSim is implemented at the virtual tracking-rig layer: it moves the synthetic HMD/controllers and generates an automatic hand-swing pattern. It does not patch or modify Gorilla Tag itself. Because VR games differ in how they interpret tracked poses and locomotion, game-specific behavior can still need tuning.
