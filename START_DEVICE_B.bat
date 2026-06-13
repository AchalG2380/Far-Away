@echo off
setlocal EnableDelayedExpansion
title ASL Retail — Device B (Cashier)
color 0E

set "ROOT=%~dp0"
set "ROOT=%ROOT:~0,-1%"
set "CONSTANTS=%ROOT%\frontend\lib\core\constants.dart"

echo.
echo  =====================================================
echo   ASL Retail Assistant  ^|  DEVICE B  (Cashier)
echo   Display only — no camera or Python needed here
echo  =====================================================
echo.

REM ── Flutter check ─────────────────────────────────────────────────────────
flutter --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Flutter not found in PATH.
    echo.
    echo   Install Flutter from:
    echo   https://flutter.dev/docs/get-started/install/windows
    echo.
    pause & exit /b 1
)
echo [OK] Flutter found.

REM ── Flutter pub get if needed ─────────────────────────────────────────────
if not exist "%ROOT%\frontend\.dart_tool\package_config.json" (
    echo [INFO] Running flutter pub get...
    cd /d "%ROOT%\frontend"
    flutter pub get 2>nul
    cd /d "%ROOT%"
    echo [OK] Flutter packages ready.
)

REM ── Ask for Device A's IP ─────────────────────────────────────────────────
echo.
echo  +---------------------------------------------------------+
echo  ^|  Device A shows its IP address when it starts.          ^|
echo  ^|  Example: 10.229.200.34                                 ^|
echo  ^|  Both devices must be on the SAME WiFi network.         ^|
echo  +---------------------------------------------------------+
echo.
set /p "DEVICE_A_IP=  Enter Device A IP address: "

if "!DEVICE_A_IP!"=="" (
    echo [ERROR] IP cannot be empty!
    pause & exit /b 1
)

echo.
echo [INFO] Configuring Flutter to connect to http://!DEVICE_A_IP!:8000 ...

REM ── Patch constants.dart with Device A IP ─────────────────────────────────
powershell -NoProfile -Command ^
 "$f='%CONSTANTS%';" ^
 "$c=Get-Content $f -Raw;" ^
 "$c=$c -replace 'static const String localApiBaseUrl = .+?;','static const String localApiBaseUrl = ''http://!DEVICE_A_IP!:8000'';';" ^
 "$c=$c -replace 'static const String aslEngineHost = .+?;','static const String aslEngineHost = ''!DEVICE_A_IP!'';';" ^
 "Set-Content $f $c -NoNewline;" ^
 "Write-Host '[OK] constants.dart updated'"

echo.
echo  +---------------------------------------------------------+
echo  ^|  IMPORTANT: Start Device A BEFORE connecting!           ^|
echo  +---------------------------------------------------------+
echo.
echo [INFO] Launching Flutter (Cashier / Display view)...
echo        Choose: 1 = Windows   or   2 = Chrome
echo.

cd /d "%ROOT%\frontend"
flutter run

echo.
pause
