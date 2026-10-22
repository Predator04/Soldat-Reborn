@echo off
rem Started by the "Tracerfall Server" scheduled task (install-service.bat):
rem runs the server with no window, appends its output to logs\server.log and
rem restarts it if it stops. Run start-server.bat instead to watch it live.
cd /d "%~dp0"
if not exist logs mkdir logs
if not exist server.cfg copy /y server.cfg.example server.cfg >nul
:run
echo ---- %date% %time% starting >> "%~dp0logs\server.log"
"%~dp0TracerfallServer.console.exe" -- --config "%~dp0server.cfg" >> "%~dp0logs\server.log" 2>&1
ping -n 6 127.0.0.1 >nul
goto run
