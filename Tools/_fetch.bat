@echo off
rem Download a helper file once: call "Tools\_fetch.bat" <url> <target>
if exist "%~2" exit /b 0
echo   downloading %~nx2 ...
where curl >nul 2>&1
if not errorlevel 1 (
  curl -sL -o "%~2" "%~1"
  if exist "%~2" exit /b 0
)
powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing -Uri '%~1' -OutFile '%~2' } catch { exit 1 }" >nul 2>&1
if exist "%~2" exit /b 0
echo   ... download failed. Get it manually: %~1
exit /b 1
