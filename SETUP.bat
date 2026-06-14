@echo off
setlocal EnableDelayedExpansion
title ASL Retail Assistant — SETUP
color 0A

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "VENV=%ROOT%\.venv"
set "VPYTHON=%VENV%\Scripts\python.exe"

echo.
echo  =====================================================
echo   ASL Retail Assistant  ^|  First-Time Setup
echo  =====================================================
echo.

REM ── 1. Python check ───────────────────────────────────────────────────────
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found!
    echo.
    echo   Download Python 3.10 from:
    echo   https://www.python.org/downloads/release/python-31011/
    echo.
    echo   IMPORTANT: Tick "Add Python to PATH" during install.
    pause & exit /b 1
)
for /f "tokens=2" %%v in ('python --version 2^>^&1') do set PYVER=%%v
echo [OK] Python %PYVER%

REM ── 2. Flutter check ──────────────────────────────────────────────────────
set FLUTTER_OK=0
flutter --version >nul 2>&1
if not errorlevel 1 set FLUTTER_OK=1
if %FLUTTER_OK%==1 (echo [OK] Flutter found) else (
    echo [WARN] Flutter not in PATH.
    echo        Download: https://flutter.dev/docs/get-started/install/windows
    echo        App will still build once Flutter is installed.
)

REM ── 3. Create virtual environment ─────────────────────────────────────────
echo.
echo [1/5] Setting up Python virtual environment...
if exist "%VPYTHON%" (
    echo       .venv already exists — skipping creation.
) else (
    python -m venv "%VENV%"
    if errorlevel 1 (
        echo [ERROR] Failed to create .venv
        pause & exit /b 1
    )
    echo       .venv created.
)

REM ── 4. Upgrade pip (use python -m pip to avoid launcher issues) ───────────
echo.
echo [2/5] Upgrading pip...
"%VPYTHON%" -m pip install --upgrade pip --quiet

REM ── 5. Install Python packages (pinned for Python 3.10 compatibility) ─────
echo.
echo [3/5] Installing Python packages...
echo       (First run: 5-10 min depending on internet speed — please wait)
echo.

REM Install in groups: core deps first, then big ML packages
echo       Step A: Core packages...
"%VPYTHON%" -m pip install --timeout 300 ^
    "numpy==1.26.4" ^
    "protobuf==4.25.9" ^
    "ml_dtypes==0.5.4" ^
    "websockets==12.0" ^
    "python-dotenv==1.0.1" ^
    "python-multipart==0.0.9" ^
    "fastapi==0.110.0" ^
    "uvicorn[standard]==0.27.1" ^
    "groq==0.11.0" ^
    "httpx==0.27.2" ^
    "deep-translator==1.11.4" ^
    "gtts==2.5.1" ^
    "scikit-learn==1.4.0" ^
    "pandas==2.2.0" ^
    "scipy==1.13.1"

echo       Step B: OpenCV (pinned — 4.11+ breaks numpy 1.x!)...
"%VPYTHON%" -m pip install --timeout 300 "opencv-contrib-python==4.10.0.84" "opencv-python==4.10.0.84"

echo       Step C: TensorFlow (large download ~500MB)...
"%VPYTHON%" -m pip install --timeout 600 "tensorflow-cpu==2.15.1"

echo       Step D: ai_edge_litert (modern TFLite runtime)...
"%VPYTHON%" -m pip install --timeout 300 "ai_edge_litert"

echo       Step E: MediaPipe + JAX (pinned to avoid Python 3.10 conflicts)...
"%VPYTHON%" -m pip install --timeout 600 ^
    "jax==0.5.3" ^
    "jaxlib==0.5.3" ^
    "mediapipe==0.10.14"

echo       Step F: Enforce numpy 1.26.4 (must run last!)...
"%VPYTHON%" -m pip install "numpy==1.26.4"

echo.
echo [OK] Python packages installed.

REM ── 6. Verify critical imports ────────────────────────────────────────────
echo.
echo [4/5] Verifying installation...
"%VPYTHON%" -c "import tensorflow as tf; import mediapipe; import websockets; import cv2; from ai_edge_litert.interpreter import Interpreter; print('[OK] All imports verified - TF', tf.__version__)" 2>&1 | findstr /C:"[OK]" /C:"Error" /C:"error"

REM ── 7. Flutter pub get ────────────────────────────────────────────────────
echo.
echo [5/5] Installing Flutter packages...
if %FLUTTER_OK%==1 (
    cd /d "%ROOT%\frontend"
    flutter pub get 2>&1 | findstr /v "^$"
    cd /d "%ROOT%"
    echo [OK] Flutter packages ready.
) else (
    echo [SKIP] Flutter not found — install Flutter then re-run SETUP.bat
)

REM ── 8. Create .env if missing ─────────────────────────────────────────────
if not exist "%ROOT%\asl_pipeline\backend\.env" (
    if exist "%ROOT%\asl_pipeline\backend\.env.example" (
        copy "%ROOT%\asl_pipeline\backend\.env.example" "%ROOT%\asl_pipeline\backend\.env" >nul
    ) else (
        echo GROQ_API_KEY=> "%ROOT%\asl_pipeline\backend\.env"
    )
    echo.
    echo  +---------------------------------------------------------+
    echo  ^|  OPTIONAL: Add your GROQ API key for AI suggestions:   ^|
    echo  ^|    Edit file: asl_pipeline\backend\.env                ^|
    echo  ^|    Set:  GROQ_API_KEY=gsk_xxxxxxxxxxxxxxxxxxxx         ^|
    echo  ^|    Free key: https://console.groq.com                  ^|
    echo  ^|    (App works offline without it)                      ^|
    echo  +---------------------------------------------------------+
) else (
    echo [OK] .env exists.
)

echo.
echo  =====================================================
echo   Setup complete!  Ready to run.
echo.
echo   HOW TO RUN:
echo     Signer machine  ->  Double-click START_DEVICE_A.bat
echo     Cashier machine ->  Double-click START_DEVICE_B.bat
echo  =====================================================
echo.
pause
