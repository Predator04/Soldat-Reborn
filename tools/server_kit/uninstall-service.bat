@echo off
rem Stop the Tracerfall server task and remove it (undoes install-service.bat).
rem Right-click > "Run as administrator".
schtasks /End /TN "Tracerfall Server" >nul 2>&1
schtasks /Delete /F /TN "Tracerfall Server"
if errorlevel 1 (
  echo Could not remove the task - run this file as administrator, or it was not installed.
)
rem The task's restart loop is gone; stop a server it left running.
taskkill /F /T /IM TracerfallServer.console.exe >nul 2>&1
taskkill /F /T /IM TracerfallServer.exe >nul 2>&1
echo Done.
pause
