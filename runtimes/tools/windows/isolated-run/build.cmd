@echo off
setlocal
cd /d "%~dp0"
set "VSPROBE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq tokens=*" %%i in (`"%VSPROBE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VICTORY_VS=%%i"
if not defined VICTORY_VS exit /b 1
call "%VICTORY_VS%\Common7\Tools\VsDevCmd.bat" -no_logo -arch=x64 -host_arch=x64
if errorlevel 1 exit /b %errorlevel%
set "VICTORY_RUNNER_NAME=isolated-run"
if /I "%~1"=="guard" set "VICTORY_RUNNER_NAME=isolated-run-guard"
cl /nologo /std:c++20 /W4 /WX /O2 /MT /EHsc /Fo:%VICTORY_RUNNER_NAME%.obj /Fe:%VICTORY_RUNNER_NAME%.exe isolated-run.cpp /link Advapi32.lib Userenv.lib Ole32.lib
if errorlevel 1 exit /b %errorlevel%
if /I "%~1"=="guard" exit /b 0
cl /nologo /std:c++20 /W4 /WX /O2 /MT /EHsc probe.cpp /link Ws2_32.lib
if errorlevel 1 exit /b %errorlevel%
if /I "%~1"=="test-external" cl /nologo /std:c++20 /W4 /WX /O2 /MT /EHsc /DVICTORY_TEST_EXTERNAL_PACKAGE /Fo:isolated-run-external-test.obj /Fe:isolated-run-external-test.exe isolated-run.cpp /link Advapi32.lib Userenv.lib Ole32.lib
