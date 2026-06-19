@echo off
clang++ -std=c++17 -O2 glld.cpp -o ..\bin\glld.exe
if errorlevel 1 exit /b %errorlevel%
clang++ -std=c++17 -O2 gstdo.cpp -o ..\bin\gstdo.exe
if errorlevel 1 exit /b %errorlevel%
clang++ -std=c++17 -O2 timer.cpp -o ..\bin\timer.exe
if errorlevel 1 exit /b %errorlevel%
clang++ -std=c++17 -O2 gfree.cpp -o ..\bin\gfree.exe
if errorlevel 1 exit /b %errorlevel%
echo Built Windows executables in %~dp0
