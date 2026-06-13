@echo off
title ASL Retail Assistant — SETUP (Run Once)
color 0A
echo.
echo  ================================================
echo   ASL Retail Assistant — First-Time Setup
echo  ================================================
echo.

REM ── Check Python ──────────────────────────────────────────────────────────
python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found!
    echo         Download Python 3.10 from https://www.python.org/downloads/
    echo         IMPORTANT: Check "Add Python to PATH" during install.
    pause
    exit /b 1
)
for /f "tokens=2" %%v in ('python --version 2^>^&1') do set PYVER=%%v
echo [OK] Python %PYVER% found.

REM ── Check Flutter ─────────────────────────────────────────────────────────
flutter --version >nul 2>&1
if errorlevel 1 (
    echo.
    echo [WARNING] Flutter not found in PATH.
    echo           Download Flutter from https://flutter.dev/docs/get-started/install/windows
    echo           Then re-run this setup.
    echo           (You can still use the backend without Flutter for now.)
    echo.
) else (
    echo [OK] Flutter found.
)

REM ── Check Git ─────────────────────────────────────────────────────────────
git --version >nul 2>&1
if errorlevel 1 (
    echo [INFO] Git not found — that's okay for a copied folder.
) else (
    echo [OK] Git found.
)

echo.
echo  ── Step 1: Creating Python virtual environment ───────────────────────
if exist ".venv\Scripts\activate.bat" (
    echo [SKIP] .venv already exists.
) else (
    python -m venv .venv
    echo [OK] .venv created.
)

echo.
echo  ── Step 2: Installing Python dependencies ────────────────────────────
call .venv\Scripts\activate.bat
echo [INFO] Upgrading pip...
python -m pip install --upgrade pip --quiet
echo [INFO] Installing requirements (this may take 3-5 minutes)...
pip install -r requirements.txt
if errorlevel 1 (
    echo.
    echo [ERROR] Some packages failed. Trying with --no-deps fallback...
    pip install -r requirements.txt --no-deps
)
echo [OK] Python dependencies installed.

echo.
echo  ── Step 3: Flutter dependencies ─────────────────────────────────────
flutter --version >nul 2>&1
if not errorlevel 1 (
    cd frontend
    echo [INFO] Running flutter pub get...
    flutter pub get
    cd ..
    echo [OK] Flutter packages ready.
) else (
    echo [SKIP] Flutter not found — skipping flutter pub get.
)

echo.
echo  ── Step 4: Check .env file ───────────────────────────────────────────
if not exist "asl_pipeline\backend\.env" (
    if exist "asl_pipeline\backend\.env.example" (
        copy "asl_pipeline\backend\.env.example" "asl_pipeline\backend\.env" >nul
        echo [OK] .env created from .env.example
        echo.
        echo  ┌─────────────────────────────────────────────────────────┐
        echo  │  ACTION REQUIRED: Add your GROQ API key                 │
        echo  │  Edit:  asl_pipeline\backend\.env                       │
        echo  │  Set:   GROQ_API_KEY=gsk_xxxxxxxxxxxxxxxxxxxx           │
        echo  │  Free key at: https://console.groq.com                  │
        echo  └─────────────────────────────────────────────────────────┘
    )
) else (
    echo [OK] .env file already exists.
)

echo.
echo  ================================================
echo   Setup Complete!
echo.
echo   Next steps:
echo   1. Add GROQ API key to asl_pipeline\backend\.env
echo   2. Run:  START_DEVICE_A.bat   (if you are the signer)
echo      OR:   START_DEVICE_B.bat   (if you are the cashier)
echo  ================================================
echo.
pause
