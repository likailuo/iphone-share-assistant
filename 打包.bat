@echo off
REM Build script: package 源码/主程序-3.0.ps1 into a GUI EXE via PS2EXE.
REM This file is pure ASCII so it works under any console codepage.
cd /d "%~dp0"
echo.
echo ==============================================
echo   Building iPhone Share Helper 3.0...
echo ==============================================
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
if %errorlevel% neq 0 (
    echo [ERROR] Build failed.
    pause
    exit /b 1
)
echo Build completed.
pause
