@echo off
rem Run the Tracerfall server whenever Windows starts, even before anyone logs
rem in: a Windows scheduled task (built into Windows, nothing to install).
rem Right-click this file > "Run as administrator". Undo: uninstall-service.bat.
rem The server runs hidden; its output goes to logs\server.log in this folder.
cd /d "%~dp0"
if not exist server.cfg copy /y server.cfg.example server.cfg >nul
if not exist logs mkdir logs
schtasks /Create /F /TN "Tracerfall Server" /SC ONSTART /RU SYSTEM /RL HIGHEST /TR "\"%~dp0run-service.bat\""
if errorlevel 1 (
  echo.
  echo Could not create the task. Right-click install-service.bat and choose "Run as administrator".
  pause
  exit /b 1
)
rem Scheduled tasks stop after 3 days by default; a server must keep running.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-ScheduledTask -TaskName 'Tracerfall Server' -Settings (New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)) | Out-Null"
schtasks /Run /TN "Tracerfall Server"
echo.
echo Installed: the server starts with Windows (task "Tracerfall Server") and is running now.
echo Log: %~dp0logs\server.log
echo Remember to allow UDP ports 7777 and 7778 (or your port and port+1) in Windows Firewall.
pause
