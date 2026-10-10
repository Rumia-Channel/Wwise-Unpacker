@echo off
rem Shared start-up prompt for the Unpack bats.
rem   call "Tools\_wuprompt.bat" <format> <default-output-folder> ["<input folder>"]
rem Returns: WU_MODE (classic|names), WU_INPUT, WU_OUTPUT, WU_TITLE
rem This file must NOT use setlocal: values are handed back to the caller.

set "WU_FMT=%~1"
set "WU_DEFOUT=%~2"
if "%WU_DEFOUT%"=="" set "WU_DEFOUT=OUT"
if not "%~3"=="" set "WU_INPUT=%~3"

:mode
echo.
echo   == Mode selection ============================================
echo     [1] Classic : carve audio from PCK/BNK (wavescan), no original names
echo     [2] Names   : keep IDs, restore in-game names, then decode
echo.
set "M="
set /P "M=  Mode [1/2] (default 1): "
if not defined M set "M=1"
if "%M%"=="1" set "WU_MODE=classic"
if "%M%"=="2" set "WU_MODE=names"
if defined WU_MODE goto input
echo   please type 1 or 2
goto mode

:input
if defined WU_INPUT goto input_done
set "INP="
set /P "INP=  Input folder with PCK/BNK/WEM files [Game Files]: "
if not defined INP set "INP=Game Files"
set WU_INPUT=%INP:"=%
:input_done
if exist "%WU_INPUT%" goto output
echo   creating "%WU_INPUT%" ...
mkdir "%WU_INPUT%" 2>nul

:output
set "OUTP="
set /P "OUTP=  Output folder [%WU_DEFOUT%]: "
if not defined OUTP set "OUTP=%WU_DEFOUT%"
set WU_OUTPUT=%OUTP:"=%
if not exist "%WU_OUTPUT%" mkdir "%WU_OUTPUT%" 2>nul

set "WU_TITLE="
if /I "%WU_MODE%"=="classic" goto end
set /P "WU_TITLE=  Game title for wwnames auto-download (optional, Enter to skip): "

:end
echo   ===============================================================
exit /b 0
