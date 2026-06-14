@echo off
title ASL Backend
cd /d "e:\Acro\Git\Real-Time-ASL-to-Text-Far-Away\Far-Away\asl_pipeline\backend"
"e:\Acro\Git\Real-Time-ASL-to-Text-Far-Away\Far-Away\.venv\Scripts\python.exe" -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload
