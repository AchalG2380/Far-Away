@echo off
setlocal EnableDelayedExpansion
title ASL Retail -- Device A
color 0B

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "VPYTHON=%ROOT%\.venv\Scripts\python.exe"
set "BACKEND=%ROOT%\asl_pipeline\backend"

echo.
echo  =====================================================
echo   ASL Retail Assistant  -  DEVICE A  (Signer)
echo  =====================================================
echo.

python --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found. Install Python 3.10:
    echo   https://www.python.org/downloads/release/python-31011/
    pause & exit /b 1
)

if not exist "%VPYTHON%" (
    echo [SETUP] First-time install - takes 5-10 min...
    python -m venv "%ROOT%\.venv"
    if errorlevel 1 ( echo [ERROR] Failed to create .venv & pause & exit /b 1 )
    "%VPYTHON%" -m pip install --upgrade pip --quiet
    echo [SETUP] 1/5 Core...
    "%VPYTHON%" -m pip install --timeout 300 "numpy==1.26.4" "protobuf==4.25.9" "ml_dtypes==0.5.4" "websockets==12.0" "python-dotenv==1.0.1" "python-multipart==0.0.9" "fastapi==0.110.0" "uvicorn[standard]==0.27.1" "groq==0.11.0" "deep-translator==1.11.4" "gtts==2.5.1" "scikit-learn==1.4.0" "pandas==2.2.0" "scipy==1.13.1"
    echo [SETUP] 2/5 OpenCV...
    "%VPYTHON%" -m pip install --timeout 300 "opencv-contrib-python==4.10.0.84" "opencv-python==4.10.0.84"
    echo [SETUP] 3/5 TensorFlow...
    "%VPYTHON%" -m pip install --timeout 600 "tensorflow-cpu==2.15.1"
    echo [SETUP] 4/5 TFLite...
    "%VPYTHON%" -m pip install --timeout 300 "ai_edge_litert"
    echo [SETUP] 5/5 MediaPipe...
    "%VPYTHON%" -m pip install --timeout 600 "jax==0.5.3" "jaxlib==0.5.3" "mediapipe==0.10.14"
    "%VPYTHON%" -m pip install "numpy==1.26.4" --quiet
    echo [SETUP] Done!
    echo.
)

if not exist "%BACKEND%\.env" (
    echo GROQ_API_KEY=>> "%BACKEND%\.env"
)

flutter --version >nul 2>&1
if not errorlevel 1 (
    if not exist "%ROOT%\frontend\.dart_tool\package_config.json" (
        cd /d "%ROOT%\frontend"
        flutter pub get --quiet 2>nul
        cd /d "%ROOT%"
    )
)

powershell -NoProfile -Command "Get-NetIPAddress -AddressFamily IPv4 | Where-Object PrefixOrigin -eq Dhcp | Select-Object -First 1 -ExpandProperty IPAddress" > "%TEMP%\asl_ip.txt" 2>nul
set /p MYIP=<"%TEMP%\asl_ip.txt"
del "%TEMP%\asl_ip.txt" 2>nul
if "!MYIP!"=="" set "MYIP=check-your-ipconfig"

echo.
echo  +----------------------------------------------+
echo  ^| Device A IP: !MYIP!
echo  ^| Device B enters: http://!MYIP!:8000
echo  +----------------------------------------------+
echo.

echo [1/3] Starting backend...
start "ASL Backend" cmd /k "%ROOT%\_backend_run.bat"
timeout /t 4 /nobreak >nul

echo [2/3] Starting camera engine...
start "ASL Camera" cmd /k "%ROOT%\_camera_run.bat"
timeout /t 4 /nobreak >nul

echo [3/3] Launching Flutter...
echo   1=Windows  2=Chrome
echo.
cd /d "%ROOT%\frontend"
flutter run

echo.
pause