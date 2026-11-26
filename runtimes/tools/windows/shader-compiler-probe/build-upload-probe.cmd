@echo off
setlocal
cd /d "%~dp0"
set "PROBE_VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq tokens=*" %%i in (`"%PROBE_VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "PROBE_VS=%%i"
if not defined PROBE_VS exit /b 1
call "%PROBE_VS%\Common7\Tools\VsDevCmd.bat" -no_logo -arch=x64 -host_arch=x64
if errorlevel 1 exit /b %errorlevel%
cl /nologo /std:c++20 /W4 /WX /O2 /MT /EHsc gpu_upload_probe.cpp /link d3d12.lib dxgi.lib
exit /b %errorlevel%
