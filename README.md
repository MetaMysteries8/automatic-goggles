# VR Keyboard Emulator

A Windows SteamVR/OpenVR proof-of-concept that lets you drive a virtual VR setup without a physical headset.

The SteamVR driver exposes:

- a virtual HMD
- a virtual left controller
- a virtual right controller

A separate Windows controller app writes head, hand, button, trigger, grip, and joystick state into shared memory. The SteamVR driver reads that state and reports it to SteamVR as tracked devices.

## Current controls

### Select a device

- `1` / `F1` — head
- `2` / `F2` — left hand
- `3` / `F3` — right hand

### Pose controls

- `WASD` — move horizontally
- `Q` / `E` — down / up
- Arrow keys — yaw / pitch
- `Z` / `X` — roll
- `Shift` — faster movement
- `R` — reset selected device

### Controller input

When either hand is selected:

- `Space` — trigger
- `Ctrl` — grip
- `F` — primary button
- `G` — secondary button
- `Tab` — menu
- `C` — stick click
- `I/J/K/L` — joystick

## Automated Windows builds

GitHub Actions builds the project on Windows x64 on pushes and pull requests. You can also start a build manually from **Actions → Windows Build → Run workflow**.

The workflow uploads a `VRKeyboardEmulator-Windows-x64` artifact containing the virtual SteamVR driver, controller executable, install/uninstall scripts, and this README.

## Local build

Requirements:

- Windows 10/11 x64
- Steam + SteamVR
- Visual Studio 2022 Build Tools with **Desktop development with C++**
- CMake
- Git

Run:

```bat
build.bat
```

Outputs:

- `build/vrkbd/` — SteamVR driver
- `build/app/vrkbd_controller.exe` — keyboard controller

## Install

1. Close SteamVR.
2. Run `install_driver.bat`.
3. Run `vrkbd_controller.exe` from a packaged build, or `build\app\vrkbd_controller.exe` from a local build.
4. Start SteamVR.
5. Use SteamVR VR View or the game's desktop mirror as the display.

The install script currently looks for SteamVR in the normal Steam install location.

## Architecture

```text
Keyboard
   |
   v
vrkbd_controller.exe
   |
   | Windows named shared memory
   v
driver_vrkbd.dll
   |
   v
vrserver.exe / SteamVR
   |
   +-- Virtual HMD
   +-- Virtual left controller
   +-- Virtual right controller
```

## Current limitations

This is an early MVP, not a complete universal VR compatibility layer.

- rigid controller poses only; skeletal finger input is not implemented yet
- no dedicated compositor/mirror application yet
- bindings may need adjustment for games expecting a particular controller profile
- some games perform headset/vendor-specific checks beyond ordinary SteamVR tracking
- native OpenXR titles depend on SteamVR being their active OpenXR runtime

## Planned upgrades

- mouse-controlled head look
- simultaneous independent left/right hand controls
- configurable controls and saved profiles
- motion smoothing and interpolation
- recenter, snap-turn, and smooth-turn modes
- skeletal hand/finger simulation
- gamepad controls
- virtual waist/foot trackers
- desktop VR camera window
- stronger OpenXR compatibility
