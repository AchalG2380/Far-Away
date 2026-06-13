@echo off
title ASL Retail — Device A (Signer + Camera)
color 0B
echo.
echo  ================================================
echo   ASL Retail Assistant — DEVICE A (Signer)
echo   This machine: has the camera + runs models
echo  ================================================
echo.

REM ── Root folder of the project ────────────────────────────────────────────
set ROOT=%~dp0
set ROOT=%ROOT:~0,-1%
set PYTHON=%ROOT%\.venv\Scripts\python.exe
set ACTIVATE=%ROOT%\.venv\Scripts\activate.bat
set BACKEND=%ROOT%\asl_pipeline\backend

REM ── Check setup done ──────────────────────────────────────────────────────
if not exist "%PYTHON%" (
    echo [ERROR] .venv not found. Run SETUP.bat first!
    pause
    exit /b 1
)

REM ── Print Device A's network IP (for Device B to use) ─────────────────────
echo  Your Network IP (tell this to Device B):
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "IPv4"') do (
    for /f "tokens=1" %%b in ("%%a") do echo   http://%%b:8000
)
echo.

REM ── Start FastAPI backend in a new window ─────────────────────────────────
echo [1/3] Starting FastAPI backend on port 8000...
start "ASL Backend" cmd /k "call %ACTIVATE% && cd /d %BACKEND% && uvicorn main:app --host 0.0.0.0 --port 8000 --reload"
timeout /t 3 /nobreak >nul

REM ── Start ASL Python engine (camera + WebSocket) ──────────────────────────
echo [2/3] Starting ASL camera engine (WebSocket on port 8765)...
start "ASL Camera Engine" cmd /k "call %ACTIVATE% && cd /d %ROOT% && python combined_asl_live.py"
timeout /t 4 /nobreak >nul

REM ── Start Flutter app ─────────────────────────────────────────────────────
echo [3/3] Launching Flutter app (Device A - Signer view)...
echo.
echo  ┌──────────────────────────────────────────────────────────────┐
echo  │  Choose option 1 (Windows) or 2 (Chrome) in the next window  │
echo  └──────────────────────────────────────────────────────────────┘
echo.
cd /d "%ROOT%\frontend"
flutter run

echo.
echo  All services started. Press any key to exit this window.
pause
