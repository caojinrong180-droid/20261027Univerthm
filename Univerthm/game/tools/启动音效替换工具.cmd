@echo off
cd /d "%~dp0"
pwsh -NoProfile -Sta -ExecutionPolicy Bypass -File "%~dp0sound_swapper.ps1"
if errorlevel 1 pause
