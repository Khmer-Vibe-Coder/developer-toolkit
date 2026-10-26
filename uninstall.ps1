# ==============================================================================
# Script: uninstall.ps1
# Purpose: Interactive uninstaller for Developer Toolkit on Windows (PowerShell).
#          Detects currently installed tools and allows selecting which ones
#          to uninstall via Up/Down arrows, Space, and 'a' (Toggle All).
# ==============================================================================

param(
    [switch]$All
)

$ToolkitRoot = $PSScriptRoot
$BinDir = Join-Path $HOME ".local\bin"
Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "🗑️  Developer Toolkit Uninstaller (Windows)" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

$InstalledTools = @()
$ToolDirs = Get-ChildItem -Path "$ToolkitRoot\tools" -Directory

foreach ($Tool in $ToolDirs) {
    $Scripts = Get-ChildItem -Path $Tool.FullName -Filter "*.sh"
    foreach ($Script in $Scripts) {
        $CmdName = [System.IO.Path]::GetFileNameWithoutExtension($Script.Name)
        $ShimPath = Join-Path $BinDir "$CmdName.cmd"
        $HasShim = Test-Path $ShimPath

        $HasAlias = $false
        $GitAlias = ""
        if ($CmdName -match "^git-") {
            $GitAlias = $CmdName -replace "^git-", ""
            $CurrentAlias = git config --global --get "alias.$GitAlias" 2>$null
            if (-not [string]::IsNullOrEmpty($CurrentAlias)) {
                $HasAlias = $true
            }
        }

        if ($HasShim -or $HasAlias) {
            $InstalledTools += [PSCustomObject]@{
                CmdName  = $CmdName
                GitAlias = $GitAlias
                ShimPath = $ShimPath
                Checked  = $false
            }
        }
    }
}

if ($InstalledTools.Count -eq 0) {
    Write-Host "`nℹ️  No Developer Toolkit tools are currently installed on this system.`n" -ForegroundColor Yellow
    exit 0
}

if (-not $All -and [Environment]::UserInteractive) {
    Write-Host "`nSelect installed tools to uninstall ($($InstalledTools.Count) detected):" -ForegroundColor Cyan
    Write-Host "Controls: [↑/↓ or j/k] Move  [Space] Toggle  [a] Toggle All  [Enter] Confirm" -ForegroundColor DarkGray

    $Cursor = 0
    $StartTop = [Console]::CursorTop

    while ($true) {
        [Console]::SetCursorPosition(0, $StartTop)
        for ($i = 0; $i -lt $InstalledTools.Count; $i++) {
            $Item = $InstalledTools[$i]
            $Pointer = if ($i -eq $Cursor) { "❯ " } else { "  " }
            $Mark = if ($Item.Checked) { "✖" } else { " " }
            $Line = "$Pointer[$Mark] $($i + 1)) $($Item.CmdName) (installed)"
            $Pad = " " * [Math]::Max(0, ([Console]::WindowWidth - $Line.Length - 1))
            if ($i -eq $Cursor) {
                Write-Host "$Line$Pad" -ForegroundColor Cyan
            } else {
                Write-Host "$Line$Pad"
            }
        }

        $Key = [Console]::ReadKey($true)
        if ($Key.Key -eq [ConsoleKey]::UpArrow -or $Key.KeyChar -eq 'k' -or $Key.KeyChar -eq 'K') {
            $Cursor = ($Cursor - 1 + $InstalledTools.Count) % $InstalledTools.Count
        } elseif ($Key.Key -eq [ConsoleKey]::DownArrow -or $Key.KeyChar -eq 'j' -or $Key.KeyChar -eq 'J') {
            $Cursor = ($Cursor + 1) % $InstalledTools.Count
        } elseif ($Key.Key -eq [ConsoleKey]::Spacebar) {
            $InstalledTools[$Cursor].Checked = -not $InstalledTools[$Cursor].Checked
        } elseif ($Key.KeyChar -eq 'a' -or $Key.KeyChar -eq 'A') {
            $AllChecked = ($InstalledTools | Where-Object { -not $_.Checked }).Count -eq 0
            foreach ($Item in $InstalledTools) { $Item.Checked = -not $AllChecked }
        } elseif ($Key.Key -eq [ConsoleKey]::Enter) {
            break
        }
    }
} else {
    foreach ($Item in $InstalledTools) { $Item.Checked = $true }
}

$SelectedToRemove = $InstalledTools | Where-Object { $_.Checked }
if ($SelectedToRemove.Count -eq 0) {
    Write-Host "`nℹ️  No tools selected for removal. Nothing changed.`n" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
$RemovedCount = 0

foreach ($Item in $SelectedToRemove) {
    Write-Host "🧹 Removing: $($Item.CmdName)" -ForegroundColor Yellow

    if (-not [string]::IsNullOrEmpty($Item.GitAlias)) {
        git config --global --unset-all "alias.$($Item.GitAlias)" 2>$null
        Write-Host "   ✔ Removed Git alias: git $($Item.GitAlias)" -ForegroundColor Green
    }

    if (Test-Path $Item.ShimPath) {
        Remove-Item -Path $Item.ShimPath -Force
        Write-Host "   ✔ Removed CLI wrapper: $($Item.ShimPath)" -ForegroundColor Green
    }

    if ($Item.CmdName -eq "git-toolkit") {
        git config --global --unset-all "alias.dtk" 2>$null
        $DtkShim = Join-Path $BinDir "dtk.cmd"
        if (Test-Path $DtkShim) { Remove-Item -Path $DtkShim -Force }
        Write-Host "   ✔ Removed Unified Hub: dtk / git dtk" -ForegroundColor Green
    }

    $RemovedCount++
}

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host "✅ Successfully uninstalled $RemovedCount tool(s) on Windows." -ForegroundColor Green
Write-Host "======================================================`n" -ForegroundColor Green
