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
echo   Camera + Models + Backend runs on this machine
echo  =====================================================
echo.

REM ── Check Python ──────────────────────────────────────────────────────────
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found. Install Python 3.10:
    echo         https://www.python.org/downloads/release/python-31011/
    echo         Tick "Add Python to PATH" during install!
    pause & exit /b 1
)

REM ── Auto-setup if .venv missing ───────────────────────────────────────────
if not exist "%VPYTHON%" (
    echo [SETUP] .venv not found — running first-time setup...
    echo         This takes 5-10 minutes. Please wait.
    echo.

    python -m venv "%VENV%"
    if errorlevel 1 (
        echo [ERROR] Could not create virtual environment!
        pause & exit /b 1
    )

    "%VPYTHON%" -m pip install --upgrade pip --quiet

    echo [SETUP] Step 1/5: Core packages...
    "%VPYTHON%" -m pip install --timeout 300 ^
        "numpy==1.26.4" "protobuf==4.25.9" "ml_dtypes==0.5.4" ^
        "websockets==12.0" "python-dotenv==1.0.1" "python-multipart==0.0.9" ^
        "fastapi==0.110.0" "uvicorn[standard]==0.27.1" "groq==0.11.0" ^
        "deep-translator==1.11.4" "gtts==2.5.1" "scikit-learn==1.4.0" ^
        "pandas==2.2.0" "scipy==1.13.1"

    echo [SETUP] Step 2/5: OpenCV (pinned — newer breaks numpy!)...
    "%VPYTHON%" -m pip install --timeout 300 ^
        "opencv-contrib-python==4.10.0.84" "opencv-python==4.10.0.84"

    echo [SETUP] Step 3/5: TensorFlow (~500MB download)...
    "%VPYTHON%" -m pip install --timeout 600 "tensorflow-cpu==2.15.1"

    echo [SETUP] Step 4/5: TFLite runtime...
    "%VPYTHON%" -m pip install --timeout 300 "ai_edge_litert"

    echo [SETUP] Step 5/5: MediaPipe + JAX...
    "%VPYTHON%" -m pip install --timeout 600 ^
        "jax==0.5.3" "jaxlib==0.5.3" "mediapipe==0.10.14"

    echo [SETUP] Enforcing numpy 1.26.4 (mediapipe can upgrade it)...
    "%VPYTHON%" -m pip install "numpy==1.26.4" --quiet

    echo.
    echo [SETUP] Done!
    echo.
)

REM ── Create .env if missing ────────────────────────────────────────────────
if not exist "%BACKEND%\.env" (
    if exist "%BACKEND%\.env.example" (
        copy "%BACKEND%\.env.example" "%BACKEND%\.env" >nul
    ) else (
        (echo GROQ_API_KEY=) > "%BACKEND%\.env"
    )
    echo [INFO] .env created. Add GROQ_API_KEY for AI features (optional).
)

REM ── Flutter pub get if needed ─────────────────────────────────────────────
flutter --version >nul 2>&1
if not errorlevel 1 (
    if not exist "%ROOT%\frontend\.dart_tool\package_config.json" (
        echo [INFO] Running flutter pub get...
        cd /d "%ROOT%\frontend"
        flutter pub get --quiet 2>nul
        cd /d "%ROOT%"
    )
)

REM ── Show this machine's IP address ────────────────────────────────────────
echo.
echo  +---------------------------------------------------------+
echo  ^|  YOUR NETWORK IP  ^(share this with Device B^):          ^|
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /C:"IPv4 Address"') do (
    for /f "tokens=1" %%b in ("%%a") do (
        echo  ^|    IP:   %%b                                         ^|
        echo  ^|    URL:  http://%%b:8000                             ^|
    )
)
echo  +---------------------------------------------------------+
echo.

REM ── 1. Start FastAPI backend ──────────────────────────────────────────────
echo [1/3] Starting backend (port 8000)...
start "ASL Backend" cmd /k "cd /d "%BACKEND%" && "%VPYTHON%" -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload"
timeout /t 4 /nobreak >nul

REM ── 2. Start ASL camera engine ────────────────────────────────────────────
echo [2/3] Starting ASL camera engine (port 8765)...
start "ASL Camera" cmd /k ""%VPYTHON%" "%ROOT%\combined_asl_live.py""
timeout /t 4 /nobreak >nul

REM ── 3. Start Flutter app ──────────────────────────────────────────────────
echo [3/3] Launching Flutter app...
echo.
echo   Choose device:
echo     1 = Windows (recommended)
echo     2 = Chrome
echo.
cd /d "%ROOT%\frontend"
flutter run

echo.
pause
