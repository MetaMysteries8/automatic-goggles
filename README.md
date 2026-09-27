# KeyboardVR v2

KeyboardVR is a Windows SteamVR virtual-device driver for using VR software without a physical VR headset.

## v2 adds

- virtual SteamVR HMD + left/right controllers
- live top/front/side VR rig visualizer
- PS5 DualSense and standard gamepad input through SDL3
- left stick -> left hand movement
- right stick -> right hand movement
- DualSense touchpad drag -> head look
- right-mouse drag -> head look
- keyboard pose editing
- virtual 4 m x 4 m standing/chaperone universe so SteamVR can skip the normal Room Setup flow
- Index/Knuckles-compatible controller rebinding fallback

## Download the prebuilt Windows version

You do **not** need to compile it yourself.

Open **Releases** and download:

`KeyboardVR-v2-Windows-x64.zip`

A fresh build is also attached to every successful **Build KeyboardVR for Windows** workflow run under the Actions tab.

## Install

1. Extract the Windows ZIP.
2. Fully close SteamVR.
3. Open PowerShell in the extracted folder.
4. Run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install.ps1
.\run.ps1
```

If SteamVR still says no headset is connected, run:

```powershell
.\diagnose.ps1
```

## Controls

Keyboard:

- `1 / 2 / 3` — head / left hand / right hand
- `WASD` — move selected device
- `R/F` — up/down
- arrows — yaw/pitch
- `Z/X` — roll
- right mouse drag — head look
- `G` — rig-follow
- `F1` — reset rig
- `F2` — reset selected device
- `F3` — show/hide visualizer

Gamepad:

- left stick — left virtual hand X/Z
- right stick — right virtual hand X/Z
- L2/R2 — left/right trigger
- L1/R1 — left/right grip
- L3/R3 — corresponding virtual thumbstick click
- DualSense touchpad drag — head yaw/pitch

## Source

The exact v2 source used by CI is stored at:

`source/KeyboardVR-Windows-SteamVR-v2.zip`

The build workflow unpacks that source, builds the Windows x64 EXE and SteamVR driver DLL with MSVC/CMake, packages them, uploads the Actions artifact, and publishes/updates the v0.2.0 GitHub Release.

The older browseable root source is retained temporarily as the original prototype snapshot.
