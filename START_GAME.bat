@echo off
title Ball Alchemy WebGL
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Serve-WebGL.ps1"
if errorlevel 1 (
  echo.
  echo The game server could not start.
  pause
)
