@echo off
rem Shared pipeline behind the "Unpack to ..." bats.
rem   call "%~dp0Tools\_run.bat" <format: ogg|mp3|wav> <default output folder> ["<input folder>"]
rem Mode 1 (Classic) = wavescan carving, Mode 2 (Names) = keep IDs + restore names.
setlocal EnableExtensions
cd /d "%~dp0.."

set "FMT=%~1"
set "DEFOUT=%~2"
if "%FMT%"=="" set "FMT=ogg"
if "%DEFOUT%"=="" set "DEFOUT=OGG"
if not exist "Tools\Decoding" mkdir "Tools\Decoding" >nul 2>&1

call "Tools\_wuprompt.bat" "%FMT%" "%DEFOUT%" "%~3"
if errorlevel 1 exit /b 1

for %%o in ("%WU_OUTPUT%") do set "WU_OUT_ABS=%%~fo"
echo.
echo   Mode   : %WU_MODE%
echo   Input  : %WU_INPUT%
echo   Output : %WU_OUT_ABS%  (format: %FMT%)
echo.

rem --- locate Python (needed by the names mode and the bulk decoder)
set "PY="
for %%c in (python py python3) do (
  if not defined PY (
    where %%c >nul 2>&1
    if not errorlevel 1 set "PY=%%c"
  )
)
if /I "%WU_MODE%"=="names" if not defined PY (
  echo   ERROR: the names mode needs Python 3 on PATH.
  pause
  exit /b 1
)

if /I "%WU_MODE%"=="classic" goto classic
goto names

rem ---------------------------------------------------------------- classic
:classic
echo   [1/3] quickbms + wavescan - carving audio from PCK/BNK ...
"Tools\quickbms.exe" -Y "Tools\wavescan.bms" "%WU_INPUT%" "Tools\Decoding"
echo   [2/3] bnkextr: extracting *.BNK ...
for %%b in ("%WU_INPUT%\*.bnk") do if exist "%%~fb" (
  pushd "Tools\Decoding"
  "..\bnkextr.exe" "%%~fb"
  popd
)
goto decode

rem ------------------------------------------------------------------ names
:names
echo   [1/4] extracting with IDs preserved ...
set "HAVE_PCK="
for %%p in ("%WU_INPUT%\*.pck") do if exist "%%~fp" set "HAVE_PCK=1"
set "HAVE_BNK="
for %%b in ("%WU_INPUT%\*.bnk") do if exist "%%~fb" set "HAVE_BNK=1"
if defined HAVE_PCK (
  call "Tools\_fetch.bat" "https://raw.githubusercontent.com/bnnm/wwiser-utils/master/scripts/wwise_pck_extractor.bms" "Tools\wwise_pck_extractor.bms"
  if exist "Tools\wwise_pck_extractor.bms" (
    for %%p in ("%WU_INPUT%\*.pck") do if exist "%%~fp" (
      "Tools\quickbms.exe" -Y -o "Tools\wwise_pck_extractor.bms" "%%~fp" "Tools\Decoding"
    )
  )
)
if defined HAVE_BNK (
  "%PY%" "Tools\wwise_bnk_extract.py" --banks "%WU_INPUT%\*.bnk" --out "Tools\Decoding"
)
for %%m in ("%WU_INPUT%\*.wem") do if exist "%%~fm" copy /Y "%%~fm" "Tools\Decoding\" >nul
for %%m in ("%WU_INPUT%\*.wav") do if exist "%%~fm" copy /Y "%%~fm" "Tools\Decoding\" >nul
set "HAVE_DEC_BNK="
for /r "Tools\Decoding" %%b in (*.bnk) do set "HAVE_DEC_BNK=1"
if defined HAVE_DEC_BNK (
  echo   extracting media from the banks ...
  "%PY%" "Tools\wwise_bnk_extract.py" --banks "Tools\Decoding" --out "Tools\Decoding"
)

echo   [2/4] collecting name sources ...
set "SRCS="
call :addsrc "wwnames.txt"
call :addsrc "SoundbanksInfo.xml"
call :addsrc "SoundbankInfo.xml"
call :addsrc "SoundbanksInfo.json"
call :addsrc "Wwise_IDs.h"
call :addsrc "Tools\wwnames.txt"
call :addsrc "Tools\SoundbanksInfo.xml"
call :addsrc "Tools\SoundbankInfo.xml"
call :addsrc "Tools\SoundbanksInfo.json"
call :addsrc "Tools\Wwise_IDs.h"
call :addsrc "%WU_INPUT%\wwnames.txt"
call :addsrc "%WU_INPUT%\SoundbanksInfo.xml"
call :addsrc "%WU_INPUT%\SoundbankInfo.xml"
call :addsrc "%WU_INPUT%\SoundbanksInfo.json"
call :addsrc "%WU_INPUT%\Wwise_IDs.h"

if defined WU_TITLE (
  echo   fetching name list for "%WU_TITLE%" ...
  "%PY%" "Tools\wwise_names.py" --fetch-wwnames "%WU_TITLE%"
  call :addsrc "wwnames.txt"
)

if defined HAVE_DEC_BNK (
  call "Tools\_fetch.bat" "https://github.com/bnnm/wwiser/releases/download/v20260808/wwiser.pyz" "Tools\wwiser.pyz"
  if exist "Tools\wwiser.pyz" (
    echo   wwiser: resolving event names from the banks - this may take a while ...
    "%PY%" "Tools\wwiser.pyz" -r "Tools\Decoding\**/*.bnk" -g -gu -gw "Tools\Decoding" -go "Tools\Decoding\txtp"
    call :addsrc "Tools\Decoding\txtp"
  )
)

echo   [3/4] planning renames ...
if not defined SRCS goto no_metadata
"%PY%" "Tools\wwise_names.py" %SRCS% --audio-dir "Tools\Decoding" --recursive --ext wem,wav --csv "Tools\name-map.csv"
set "GO="
set /P "GO=  Apply these names now? [Y/N]: "
if /I "%GO%"=="Y" (
  "%PY%" "Tools\wwise_names.py" %SRCS% --audio-dir "Tools\Decoding" --recursive --ext wem,wav --apply --csv "Tools\name-map.csv"
)
goto decode

:no_metadata
echo   no name metadata found - skipping the rename step.
echo   put SoundbanksInfo.xml / Wwise_IDs.h / wwnames.txt next to the input,
echo   or run again and enter a game title for the automatic name list.

rem ---------------------------------------------------------------- decode
:decode
echo   decoding to %FMT% ...
if defined PY (
  "%PY%" "Tools\decode_wem.py" --dir "Tools\Decoding" --out "%WU_OUT_ABS%" --format "%FMT%" --ext wem,wav --recursive
) else (
  echo   no Python found - using the bundled tools directly
  pushd "Tools\Decoding"
  for %%d in ("*.wem" "*.wav") do if exist "%%~fd" (
    if not exist "%%~nd.ogg" (
      "..\ww2ogg.exe" "%%d" --pcb "..\packed_codebooks_aoTuV_603.bin" -o "%%~nd.ogg"
    )
  )
  for %%e in ("*.ogg") do if exist "%%~fe" (
    "..\revorb.exe" "%%e"
    move /Y "%%e" "%WU_OUT_ABS%" >nul
  )
  popd
  if /I "%FMT%"=="mp3" for %%f in ("%WU_OUT_ABS%\*.ogg") do if exist "%%~ff" (
    "Tools\ffmpeg.exe" -hide_banner -loglevel error -y -i "%%~ff" -acodec libmp3lame -q:a 0 "%WU_OUT_ABS%\%%~nf.mp3"
    if exist "%WU_OUT_ABS%\%%~nf.mp3" del "%%~ff" >nul 2>&1
  )
  if /I "%FMT%"=="wav" for %%f in ("%WU_OUT_ABS%\*.ogg") do if exist "%%~ff" (
    "Tools\ffmpeg.exe" -hide_banner -loglevel error -y -i "%%~ff" -c:a pcm_s16le "%WU_OUT_ABS%\%%~nf.wav"
    if exist "%WU_OUT_ABS%\%%~nf.wav" del "%%~ff" >nul 2>&1
  )
)

echo.
echo    ((  '####@@!!$$    ))
echo        `#####@@!$$`  ))
echo     ((  '####@!!$:
echo    ((  ,####@!!$:   ))
echo        .###@!!$:
echo        `##@@!$:
echo         `#@!!$
echo   !@#    `#@!$:       @#$
echo    #$     `#@!$:       !@!
echo             '@!$:
echo         '`\   '!$: /`'
echo            '\  '!: /'
echo              '\ : /'
echo   -.'-/\\\-.'//.-'/:'\.'-.JrS'.'-=_\\
echo ' -.'-.\\'-.'//.-'.`-.'_\\-.'.-\'.-//
echo      Watch out, it's the tornado!

echo.
echo -------------------------------------------------------------
echo Unpack finished! Files should be in the '%WU_OUTPUT%' folder
echo -------------------------------------------------------------
echo.

:choice
rem Only sources staged inside this unpacker folder may be deleted. The check
rem requires the input folder to be the unpacker root or below it, so a
rem sibling like "Wwise-Unpacker 2" next door never counts as inside.
for %%i in ("%WU_INPUT%") do set "WU_IN_ABS=%%~fi"
set "WU_REPO=%CD%"
call set "WU_REST=%%WU_IN_ABS:%WU_REPO%=%%"
if /I "%WU_REST%"=="%WU_IN_ABS%" goto :outside
set "WU_INSIDE="
if "%WU_REST%"=="" set "WU_INSIDE=1"
if "%WU_REST:~0,1%"=="\" set "WU_INSIDE=1"
if not defined WU_INSIDE goto :outside
set "c="
set /P "c=Should I delete PCK/BNK files from '%WU_INPUT%' [Y/N]?"
if /I "%c%"=="Y" goto :yes
if /I "%c%"=="N" goto :hella_no
goto choice

:outside
echo.
echo Input folder is outside this unpacker folder: '%WU_INPUT%'
echo Sources are left untouched (only folders inside the unpacker can be cleaned).
goto :hella_no

:yes
del /Q "%WU_INPUT%\*.pck" >nul 2>&1
del /Q "%WU_INPUT%\*.bnk" >nul 2>&1
echo Sources deleted, enjoy your unpacked audio!
pause
exit /b 0

:hella_no
echo Sources kept, enjoy your unpacked audio!
pause
exit /b 0

rem ------------------------------------------------------------- utilities
:addsrc
if exist "%~1" set SRCS=%SRCS% "%~1"
exit /b 0
