@echo off
title ASL Backend
cd /d "%~dp0asl_pipeline\backend"
"..\..\.venv\Scripts\python.exe" -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
