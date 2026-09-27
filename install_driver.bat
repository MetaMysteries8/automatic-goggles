@echo off
setlocal
set "VRPATH=%ProgramFiles(x86)%\Steam\steamapps\common\SteamVR\bin\win64\vrpathreg.exe"
if not exist "%VRPATH%" (
  echo SteamVR vrpathreg.exe not found at the default path.
  echo Edit this script if SteamVR is installed elsewhere.
  pause
  exit /b 1
)

set "DRIVERDIR=%~dp0vrkbd"
if not exist "%DRIVERDIR%\driver.vrdrivermanifest" set "DRIVERDIR=%~dp0build\vrkbd"
if not exist "%DRIVERDIR%\driver.vrdrivermanifest" (
  echo SteamVR driver files were not found.
  echo For a local checkout, run build.bat first.
  pause
  exit /b 1
)

"%VRPATH%" adddriver "%DRIVERDIR%"
if errorlevel 1 (
  echo Failed to register the driver.
  pause
  exit /b 1
)
echo Driver registered from: %DRIVERDIR%
echo Restart SteamVR if it is already running.
pause
