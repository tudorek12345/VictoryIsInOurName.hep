@echo off
setlocal
cd /d "%~dp0"
set "VSPROBE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq tokens=*" %%i in (`"%VSPROBE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VICTORY_VS=%%i"
if not defined VICTORY_VS exit /b 1
call "%VICTORY_VS%\Common7\Tools\VsDevCmd.bat" -no_logo -arch=x64 -host_arch=x64
if errorlevel 1 exit /b %errorlevel%
cl /nologo /std:c++20 /W4 /WX /O2 /MT /EHsc /Fe:profile-cleanup-tests.exe profile-cleanup-tests.cpp
if errorlevel 1 exit /b %errorlevel%
profile-cleanup-tests.exe
exit /b %errorlevel%
