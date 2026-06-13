@echo off
title ASL Retail — Device B (Cashier / Output Screen)
color 0E
echo.
echo  ================================================
echo   ASL Retail Assistant — DEVICE B (Cashier)
echo   This machine: NO camera — receives signs from Device A
echo  ================================================
echo.

REM ── Ask for Device A's IP ─────────────────────────────────────────────────
echo  Enter Device A's IP address (shown when Device A starts):
echo  Example: 10.229.200.34
echo.
set /p DEVICE_A_IP="  Device A IP: "

if "%DEVICE_A_IP%"=="" (
    echo [ERROR] IP cannot be empty!
    pause
    exit /b 1
)

echo.
echo [INFO] Setting Device A IP to: %DEVICE_A_IP%

REM ── Update constants.dart with Device A's IP ──────────────────────────────
set ROOT=%~dp0
set ROOT=%ROOT:~0,-1%
set CONSTANTS=%ROOT%\frontend\lib\core\constants.dart

echo [INFO] Updating frontend constants...

REM Use PowerShell to do the string replacement safely
powershell -Command ^
    "$f = '%CONSTANTS%';" ^
    "$c = Get-Content $f -Raw;" ^
    "$c = $c -replace 'static const String localApiBaseUrl = .+?;', 'static const String localApiBaseUrl = ''http://%DEVICE_A_IP%:8000'';';" ^
    "$c = $c -replace 'static const String aslEngineHost = .+?;', 'static const String aslEngineHost = ''%DEVICE_A_IP%'';';" ^
    "Set-Content $f $c -NoNewline;"

echo [OK] constants.dart updated to point to %DEVICE_A_IP%

echo.
echo [INFO] Launching Flutter app (Device B - Cashier view)...
echo.
echo  ┌────────────────────────────────────────────────────────────────────┐
echo  │  Make sure Device A is already running before this connects!       │
echo  │  Both devices must be on the SAME WiFi network.                    │
echo  └────────────────────────────────────────────────────────────────────┘
echo.

cd /d "%ROOT%\frontend"
flutter run

echo.
echo  Done. Press any key to close.
pause
