@echo off
echo ---------------------------------------------------------
echo  SignBridge ASL Live Engine
echo ---------------------------------------------------------

set PROJECT=e:\Acro\Git\Real-Time-ASL-to-Text
set PYTHON=%PROJECT%\.venv\Scripts\python.exe

echo [INFO] Using Python: %PYTHON%
echo [INFO] Starting ASL engine with camera...
echo.

cd /d "%PROJECT%"
"%PYTHON%" combined_asl_live.py

pause
