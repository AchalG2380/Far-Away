@echo off
setlocal EnableDelayedExpansion
title ASL Retail — Device A (Signer)
color 0B

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "VENV=%ROOT%\.venv"
set "VPYTHON=%VENV%\Scripts\python.exe"
set "BACKEND=%ROOT%\asl_pipeline\backend"

echo.
echo  =====================================================
echo   ASL Retail Assistant  ^|  DEVICE A  (Signer)
echo   This machine: camera + models + backend
echo  =====================================================
echo.

REM ── Auto-setup if .venv missing ───────────────────────────────────────────
if not exist "%VPYTHON%" (
    echo [AUTO-SETUP] .venv not found — running first-time setup...
    echo              (This will take 5-10 minutes on first run)
    echo.
    python --version >nul 2>&1
    if errorlevel 1 (
        echo [ERROR] Python not found. Install Python 3.10 first:
        echo         https://www.python.org/downloads/release/python-31011/
        echo         Tick "Add Python to PATH" during install!
        pause & exit /b 1
    )
    echo Creating virtual environment...
    python -m venv "%VENV%"
    echo Upgrading pip...
    "%VPYTHON%" -m pip install --upgrade pip --quiet
    echo Installing core packages...
    "%VPYTHON%" -m pip install --timeout 300 ^
        "numpy==1.26.4" "protobuf==4.25.9" "ml_dtypes==0.5.4" ^
        "websockets==12.0" "python-dotenv==1.0.1" "python-multipart==0.0.9" ^
        "fastapi==0.110.0" "uvicorn[standard]==0.27.1" "groq==0.11.0" ^
        "deep-translator==1.11.4" "gtts==2.5.1" "scikit-learn==1.4.0" ^
        "pandas==2.2.0" "scipy==1.13.1" "opencv-python==4.10.0.84"
    echo Installing TensorFlow (large download, may take a few minutes)...
    "%VPYTHON%" -m pip install --timeout 600 "tensorflow-cpu==2.15.1"
    echo Installing TFLite runtime + MediaPipe...
    "%VPYTHON%" -m pip install --timeout 600 ^
        "ai_edge_litert" "jax==0.5.3" "jaxlib==0.5.3" "mediapipe==0.10.14"
    echo [OK] Setup complete.
    echo.
)

REM ── Create .env if missing ────────────────────────────────────────────────
if not exist "%BACKEND%\.env" (
    if exist "%BACKEND%\.env.example" (
        copy "%BACKEND%\.env.example" "%BACKEND%\.env" >nul
    ) else (
        echo GROQ_API_KEY=> "%BACKEND%\.env"
    )
    echo [NOTE] .env created. Add GROQ_API_KEY to enable AI suggestions (optional).
)

REM ── Flutter pub get if needed ─────────────────────────────────────────────
if not exist "%ROOT%\frontend\.dart_tool\package_config.json" (
    flutter --version >nul 2>&1
    if not errorlevel 1 (
        echo [INFO] Running flutter pub get...
        cd /d "%ROOT%\frontend"
        flutter pub get 2>nul
        cd /d "%ROOT%"
    )
)

REM ── Show Device A's IP (for Device B) ─────────────────────────────────────
echo.
echo  +---------------------------------------------------------+
echo  ^|  YOUR NETWORK IP  (tell this to Device B / cashier):   ^|
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /C:"IPv4 Address"') do (
    for /f "tokens=1" %%b in ("%%a") do echo  ^|    http://%%b:8000                                     ^|
)
echo  +---------------------------------------------------------+
echo.

REM ── Start FastAPI backend ─────────────────────────────────────────────────
echo [1/3] Starting backend server (port 8000)...
start "ASL Backend" cmd /k ""%VPYTHON%" -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload --app-dir "%BACKEND%""
timeout /t 3 /nobreak >nul

REM ── Start Python ASL engine ───────────────────────────────────────────────
echo [2/3] Starting ASL camera engine (port 8765)...
start "ASL Camera" cmd /k ""%VPYTHON%" "%ROOT%\combined_asl_live.py""
timeout /t 4 /nobreak >nul

REM ── Start Flutter app ─────────────────────────────────────────────────────
echo [3/3] Launching Flutter app...
echo.
echo        Choose a device to run on:
echo          1 = Windows (recommended — best camera access)
echo          2 = Chrome  (works without camera driver)
echo.
cd /d "%ROOT%\frontend"
flutter run

echo.
pause
