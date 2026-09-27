@echo off
setlocal
set "VRPATH=%ProgramFiles(x86)%\Steam\steamapps\common\SteamVR\bin\win64\vrpathreg.exe"
if not exist "%VRPATH%" (
  echo SteamVR vrpathreg.exe not found at the default path.
  pause
  exit /b 1
)

set "DRIVERDIR=%~dp0vrkbd"
if not exist "%DRIVERDIR%\driver.vrdrivermanifest" set "DRIVERDIR=%~dp0build\vrkbd"
if not exist "%DRIVERDIR%\driver.vrdrivermanifest" (
  echo Driver directory was not found next to this script or under build\vrkbd.
  pause
  exit /b 1
)

"%VRPATH%" removedriver "%DRIVERDIR%"
if errorlevel 1 (
  echo Failed to unregister the driver.
  pause
  exit /b 1
)
echo Driver unregistered. Restart SteamVR if it is already running.
pause
