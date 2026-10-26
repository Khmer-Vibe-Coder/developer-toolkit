@echo off
rem Wrapper for Windows CMD / PowerShell environments
rem Runs git-template.sh using bash/sh from Git for Windows

where bash >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    bash "%~dp0git-template.sh" %*
) else (
    sh "%~dp0git-template.sh" %*
)
