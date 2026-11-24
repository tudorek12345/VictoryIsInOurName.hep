@echo off
setlocal
rem Run from any working directory; all arguments are forwarded unchanged.
where py.exe >nul 2>nul
if errorlevel 1 goto use_python
py.exe -3 -I "%~dp0runtime_backend.py" %*
exit /b %ERRORLEVEL%
:use_python
python.exe -I "%~dp0runtime_backend.py" %*
exit /b %ERRORLEVEL%
