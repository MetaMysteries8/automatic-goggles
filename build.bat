@echo off
setlocal
where cmake >nul 2>nul || (echo CMake is required. & pause & exit /b 1)
cmake -S . -B build -A x64
if errorlevel 1 goto fail
cmake --build build --config Release
if errorlevel 1 goto fail
echo.
echo Build complete.
echo Driver: build\vrkbd
echo Controller: build\app\vrkbd_controller.exe
pause
exit /b 0
:fail
echo Build failed.
pause
exit /b 1
