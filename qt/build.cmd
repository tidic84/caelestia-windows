@echo off
rem Compile le prototype : MSVC (Build Tools 2022), Ninja, Qt 6 (QTDIR).
if "%QTDIR%"=="" set QTDIR=C:\Qt\6.9.3\msvc2022_64
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul || exit /b 1
cmake -S "%~dp0." -B "%~dp0build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=%QTDIR% || exit /b 1
cmake --build "%~dp0build" || exit /b 1
"%QTDIR%\bin\windeployqt.exe" --release --qmldir "%~dp0qml" --no-translations --no-system-d3d-compiler --no-opengl-sw "%~dp0build\ilot-qt.exe" >nul
