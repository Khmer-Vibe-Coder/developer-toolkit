# ==============================================================================
# Script: uninstall.ps1
# Purpose: One-command uninstaller for Developer Toolkit on Windows (PowerShell).
# ==============================================================================

$ToolkitRoot = $PSScriptRoot
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "🗑️  Uninstalling Developer Toolkit from Windows..." -ForegroundColor Cyan
Write-Host "======================================================`n" -ForegroundColor Cyan

$Tools = Get-ChildItem -Path "$ToolkitRoot\tools" -Directory
$RemovedCount = 0

foreach ($Tool in $Tools) {
    $Scripts = Get-ChildItem -Path $Tool.FullName -Filter "*.sh"
    foreach ($Script in $Scripts) {
        $CmdName = [System.IO.Path]::GetFileNameWithoutExtension($Script.Name)
        Write-Host "🧹 Removing: $CmdName" -ForegroundColor Yellow

        if ($CmdName -match "^git-") {
            $GitAlias = $CmdName -replace "^git-", ""
            git config --global --unset alias.$GitAlias 2>$null
            Write-Host "   ✔ Removed Git alias: git $GitAlias" -ForegroundColor Green
            $RemovedCount++
        }
    }
}

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host "✅ Successfully uninstalled $RemovedCount tool(s) on Windows." -ForegroundColor Green
Write-Host "======================================================`n" -ForegroundColor Green
