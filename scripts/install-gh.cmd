@echo off
rem Install GitHub CLI (gh) - double-click launcher for install-gh.sh
rem On this machine bash lives at H:\Git and is NOT on the PATH, so call it directly.

setlocal
set "BASH=H:\Git\bin\bash.exe"
if not exist "%BASH%" set "BASH=C:\Program Files\Git\bin\bash.exe"
if not exist "%BASH%" (
  echo [x] bash.exe not found.
  echo     Run it from Git Bash instead:  bash "%~dp0install-gh.sh"
  pause
  exit /b 1
)

rem UTF-8 console so the Chinese prompts render instead of mojibake.
chcp 65001 >nul
"%BASH%" "%~dp0install-gh.sh"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" echo [x] wizard exited with code %RC%
echo.
pause
