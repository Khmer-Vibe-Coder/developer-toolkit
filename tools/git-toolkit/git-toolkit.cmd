@echo off
rem Wrapper for Windows CMD / PowerShell environments
rem Runs git-toolkit.sh using bash/sh from Git for Windows

where bash >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    bash "%~dp0git-toolkit.sh" %*
) else (
    sh "%~dp0git-toolkit.sh" %*
)
