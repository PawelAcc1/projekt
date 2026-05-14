@echo off

set PATH=%PATH%;C:\AMDDesignTools\2025.2\Vivado\data\..\lib\win64.o;C:\AMDDesignTools\2025.2\Vivado\data\..\lib\win64.o\Default;C:\AMDDesignTools\2025.2\Vivado\data\..\tps\mingw\6.2.0\win64.o\nt\x86_64-w64-mingw32\lib

.\xsim.dir\top_fpga_tb\axsim.exe %*

if %errorlevel% neq 0 (
  echo FATAL ERROR: Simulation exited unexpectantly
)
