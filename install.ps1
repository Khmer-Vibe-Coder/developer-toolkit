# ==============================================================================
# Script: install.ps1
# Purpose: One-command installer for Developer Toolkit on Windows (PowerShell).
#          Configures Git aliases and optionally adds tools to User PATH.
# ==============================================================================

$ErrorActionPreference = "Stop"

$ToolkitRoot = $PSScriptRoot
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "🛠️  Installing Developer Toolkit for Windows..." -ForegroundColor Cyan
Write-Host "   Path: $ToolkitRoot" -ForegroundColor Cyan
Write-Host "======================================================`n" -ForegroundColor Cyan

$Tools = Get-ChildItem -Path "$ToolkitRoot\tools" -Directory
$InstalledCount = 0

foreach ($Tool in $Tools) {
    $Scripts = Get-ChildItem -Path $Tool.FullName -Filter "*.sh"
    foreach ($Script in $Scripts) {
        $CmdName = [System.IO.Path]::GetFileNameWithoutExtension($Script.Name)
        Write-Host "📦 Setting up: $CmdName" -ForegroundColor Yellow

        # Format unix-style path with forward slashes for Git
        $UnixPath = $Script.FullName -replace '\\', '/'

        if ($CmdName -match "^git-") {
            $GitAlias = $CmdName -replace "^git-", ""
            git config --global alias.$GitAlias "!bash `"$UnixPath`""
            Write-Host "   ✔ Git Alias registered: git $GitAlias" -ForegroundColor Green
            $InstalledCount++
        }
    }
}

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host "✅ Successfully installed $InstalledCount tool(s) on Windows!" -ForegroundColor Green
Write-Host "======================================================`n" -ForegroundColor Green
