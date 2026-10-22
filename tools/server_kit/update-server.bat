@echo off
rem Update this Tracerfall server to the latest GitHub release (only if newer;
rem the download must carry the game's release signature). Close the server
rem window (or run uninstall-service.bat / stop the task) first.
rem   update-server.bat            update-server.bat --check
cd /d "%~dp0"
set PY=
py -3 -c "print(1)" >nul 2>&1 && set "PY=py -3"
if not defined PY python -c "import sys; sys.exit(sys.version_info[0] < 3)" >nul 2>&1 && set "PY=python"
if not defined PY (
  echo update-server needs Python 3: install it from https://www.python.org/downloads/
  echo or download TracerfallServer-windows.zip from the GitHub releases page yourself
  echo and copy its files over this folder ^(your server.cfg is not in the zip^).
  pause
  exit /b 1
)
%PY% update_server.py %*
set RC=%errorlevel%
if "%~1"=="" pause
exit /b %RC%
