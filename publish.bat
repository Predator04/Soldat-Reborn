@echo off
REM Push all local commits, file the tracked-offline issues, and publish the
REM release with the Windows + Android builds. Safe to run again.
cd /d "%~dp0"
git push origin HEAD:main || goto :fail
python tools\github\sync.py all || goto :fail
echo.
echo Done: code pushed, issues filed and closed, release uploaded.
pause
exit /b 0
:fail
echo.
echo Something failed - see the message above.
pause
exit /b 1
