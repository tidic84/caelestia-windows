@echo off
rem Compile Ilot : coeur Rust (cargo), puis l'interface Qt (MSVC, Ninja, Qt 6 dans QTDIR).
setlocal
if "%QTDIR%"=="" set QTDIR=C:\Qt\6.9.3\msvc2022_64
rem Visual Studio 2022 ou plus recent, quelle que soit l'edition (Build Tools, Community...)
set VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe
set VSDIR=
for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -version 17 -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set VSDIR=%%i
if "%VSDIR%"=="" (echo Visual Studio avec les outils C++ introuvable & exit /b 1)
call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
pushd "%~dp0.."
cargo build --release || (popd & exit /b 1)
popd
cmake -S "%~dp0." -B "%~dp0build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=%QTDIR% || exit /b 1
cmake --build "%~dp0build" || exit /b 1
rem packs de compagnon livres avec l'appli (pets\ du depot, a cote de ilot.exe)
if exist "%~dp0..\pets" robocopy "%~dp0..\pets" "%~dp0build\pets" /MIR /NFL /NDL /NJH /NJS /NP >nul
rem robocopy : 8 ou plus = echec (1 a 7 = fichiers copies)
if errorlevel 8 exit /b 1
"%QTDIR%\bin\windeployqt.exe" --release --qmldir "%~dp0qml" --no-translations --no-system-d3d-compiler --no-opengl-sw "%~dp0build\ilot.exe" >nul
