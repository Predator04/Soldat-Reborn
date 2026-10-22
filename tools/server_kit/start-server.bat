@echo off
rem Tracerfall dedicated server (Windows). Double-click this file, or run
rem   start-server.bat --port 7800      (flags win over server.cfg)
rem First run: copies server.cfg.example to server.cfg. Close the window to stop.
rem The server restarts by itself if it ever stops. Run it at Windows startup
rem instead: install-service.bat (see HOSTING.md).
title Tracerfall Server
cd /d "%~dp0"
if not exist server.cfg (
  copy /y server.cfg.example server.cfg >nul
  echo Created server.cfg from server.cfg.example - edit it to name your server.
)
:run
"%~dp0TracerfallServer.console.exe" -- --config "%~dp0server.cfg" %*
echo.
echo Server stopped (exit code %errorlevel%). Restarting in 5 seconds - close this window to stop.
ping -n 6 127.0.0.1 >nul
goto run
