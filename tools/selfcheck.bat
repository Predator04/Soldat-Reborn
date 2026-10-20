@echo off
setlocal
rem ==========================================================================
rem  Tracerfall self-check (Windows): pull main, import, start a dedicated
rem  server, join it with two smoke clients, and keep the ONE GitHub issue
rem  "[selfcheck] failing" up to date. Meant for a scheduled task / agent
rem  every 6 hours:   game\tools\selfcheck.bat
rem  Extra arguments go to tools\selfcheck.py (e.g. --godot PATH, --mode dm).
rem  Exit code: 0 pass, 1 fail, 2 checker problem. Last line printed:
rem    SELFCHECK PASS|FAIL|ERROR <kind> <sha>
rem ==========================================================================
cd /d "%~dp0.." || exit /b 2

rem Find a Python that actually starts (same order as the release scripts).
set "PY="
py -3 -c "print(1)" >nul 2>&1 && set "PY=py -3"
if not defined PY if exist "%USERPROFILE%\miniconda3\python.exe" "%USERPROFILE%\miniconda3\python.exe" -c "print(1)" >nul 2>&1 && set PY="%USERPROFILE%\miniconda3\python.exe"
if not defined PY python -c "print(1)" >nul 2>&1 && set "PY=python"
if not defined PY (echo SELFCHECK ERROR no-python unknown & exit /b 2)

%PY% tools\selfcheck.py --pull --report-github %*
exit /b %ERRORLEVEL%
