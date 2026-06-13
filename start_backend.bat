@echo off
echo =========================================================
echo  CosmicSigns ASL Backend  ^|  Local Server
echo =========================================================
echo.

set BACKEND=%~dp0asl_pipeline\backend
set PYTHON=%~dp0.venv\Scripts\python.exe

REM -- Check for .env file --
if not exist "%BACKEND%\.env" (
    echo [WARNING] No .env file found in asl_pipeline\backend\
    echo           Copy .env.example to .env and fill in your GROQ_API_KEY
    echo           Suggestions/paraphrase/speech will use offline fallback only.
    echo.
)

echo [INFO] Starting FastAPI backend on http://localhost:8000
echo [INFO] Swagger docs at  http://localhost:8000/docs
echo [INFO] Press Ctrl+C to stop.
echo.

cd /d "%BACKEND%"

REM -- Try project venv first, then system python --
if exist "%PYTHON%" (
    "%PYTHON%" -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
) else (
    uvicorn main:app --host 0.0.0.0 --port 8000 --reload
)

pause
