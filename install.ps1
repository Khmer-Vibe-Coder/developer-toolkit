# ==============================================================================
# Script: install.ps1
# Purpose: Interactive installer for Developer Toolkit on Windows (PowerShell).
#          Allows selecting which tools to install via Up/Down arrows, Space,
#          and 'a' (Toggle All), and prevents duplicate installations.
# ==============================================================================

param(
    [switch]$All,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$ToolkitRoot = $PSScriptRoot
$BinDir = Join-Path $HOME ".local\bin"
if (-not (Test-Path $BinDir)) {
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
}

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "🛠️  Developer Toolkit Installer (Windows)" -ForegroundColor Cyan
Write-Host "   Path: $ToolkitRoot" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

# Discover all available tools
$ToolItems = @()
$ToolDirs = Get-ChildItem -Path "$ToolkitRoot\tools" -Directory

foreach ($Tool in $ToolDirs) {
    $Scripts = Get-ChildItem -Path $Tool.FullName -Filter "*.sh"
    foreach ($Script in $Scripts) {
        $CmdName = [System.IO.Path]::GetFileNameWithoutExtension($Script.Name)
        $UnixPath = $Script.FullName -replace '\\', '/'
        $ShimPath = Join-Path $BinDir "$CmdName.cmd"

        $HasShim = Test-Path $ShimPath
        $HasAlias = $true
        if ($CmdName -match "^git-") {
            $GitAlias = $CmdName -replace "^git-", ""
            $ExpectedAlias = "!bash `"$UnixPath`""
            $CurrentAlias = git config --global --get "alias.$GitAlias" 2>$null
            $HasAlias = ($CurrentAlias -eq $ExpectedAlias)
        }

        $IsInstalled = ($HasShim -and $HasAlias)
        $ToolItems += [PSCustomObject]@{
            CmdName     = $CmdName
            ScriptPath  = $Script.FullName
            UnixPath    = $UnixPath
            ShimPath    = $ShimPath
            IsInstalled = $IsInstalled
            Checked     = (-not $IsInstalled)
        }
    }
}

if ($ToolItems.Count -eq 0) {
    Write-Host "`n⚠️  No tools found in $ToolkitRoot\tools" -ForegroundColor Yellow
    exit 0
}

if (-not $All -and [Environment]::UserInteractive) {
    Write-Host "`nSelect tools to install ($($ToolItems.Count) available):" -ForegroundColor Cyan
    Write-Host "Controls: [↑/↓ or j/k] Move  [Space] Toggle  [a] Toggle All  [Enter] Confirm" -ForegroundColor DarkGray

    $Cursor = 0
    $StartTop = [Console]::CursorTop

    while ($true) {
        [Console]::SetCursorPosition(0, $StartTop)
        for ($i = 0; $i -lt $ToolItems.Count; $i++) {
            $Item = $ToolItems[$i]
            $Pointer = if ($i -eq $Cursor) { "❯ " } else { "  " }
            $Mark = if ($Item.Checked) { "✔" } else { " " }
            $Status = if ($Item.IsInstalled) { "[already installed]" } else { "[not installed]" }
            $Line = "$Pointer[$Mark] $($i + 1)) $($Item.CmdName) $Status"
            $Pad = " " * [Math]::Max(0, ([Console]::WindowWidth - $Line.Length - 1))
            if ($i -eq $Cursor) {
                Write-Host "$Line$Pad" -ForegroundColor Cyan
            } elseif ($Item.IsInstalled) {
                Write-Host "$Line$Pad" -ForegroundColor DarkGreen
            } else {
                Write-Host "$Line$Pad"
            }
        }

        $Key = [Console]::ReadKey($true)
        if ($Key.Key -eq [ConsoleKey]::UpArrow -or $Key.KeyChar -eq 'k' -or $Key.KeyChar -eq 'K') {
            $Cursor = ($Cursor - 1 + $ToolItems.Count) % $ToolItems.Count
        } elseif ($Key.Key -eq [ConsoleKey]::DownArrow -or $Key.KeyChar -eq 'j' -or $Key.KeyChar -eq 'J') {
            $Cursor = ($Cursor + 1) % $ToolItems.Count
        } elseif ($Key.Key -eq [ConsoleKey]::Spacebar) {
            $ToolItems[$Cursor].Checked = -not $ToolItems[$Cursor].Checked
        } elseif ($Key.KeyChar -eq 'a' -or $Key.KeyChar -eq 'A') {
            $AllChecked = ($ToolItems | Where-Object { -not $_.Checked }).Count -eq 0
            foreach ($Item in $ToolItems) { $Item.Checked = -not $AllChecked }
        } elseif ($Key.Key -eq [ConsoleKey]::Enter) {
            break
        }
    }
} else {
    foreach ($Item in $ToolItems) { $Item.Checked = $true }
}

$SelectedTools = $ToolItems | Where-Object { $_.Checked }
if ($SelectedTools.Count -eq 0) {
    Write-Host "`nℹ️  No tools selected for installation. Exiting.`n" -ForegroundColor Yellow
    exit 0
}

Write-Host ""
$InstalledCount = 0
$SkippedCount = 0

foreach ($Item in $SelectedTools) {
    if ($Item.IsInstalled -and -not $Force) {
        Write-Host "⏭️  Skipping $($Item.CmdName): Already installed (use -Force to reinstall)" -ForegroundColor Blue
        $SkippedCount++
        continue
    }

    Write-Host "📦 Installing: $($Item.CmdName)" -ForegroundColor Yellow

    if ($Item.CmdName -match "^git-") {
        $GitAlias = $Item.CmdName -replace "^git-", ""
        git config --global --replace-all "alias.$GitAlias" "!bash `"$($Item.UnixPath)`""
        Write-Host "   ✔ Git Alias registered: git $GitAlias" -ForegroundColor Green
    }

    $ShimContent = "@echo off`r`nbash `"$($Item.ScriptPath)`" %*`r`n"
    Set-Content -Path $Item.ShimPath -Value $ShimContent -Encoding ASCII
    Write-Host "   ✔ CLI Wrapper created: $($Item.ShimPath)" -ForegroundColor Green

    if ($Item.CmdName -eq "git-toolkit") {
        git config --global --replace-all "alias.dtk" "!bash `"$($Item.UnixPath)`""
        $DtkShim = Join-Path $BinDir "dtk.cmd"
        Set-Content -Path $DtkShim -Value $ShimContent -Encoding ASCII
        Write-Host "   ✔ Unified Hub registered: dtk / git dtk / git toolkit" -ForegroundColor Green
    }

    $InstalledCount++
}

$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($UserPath -notlike "*$BinDir*") {
    $NewPath = if ([string]::IsNullOrEmpty($UserPath)) { $BinDir } else { "$UserPath;$BinDir" }
    [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
    $env:Path += ";$BinDir"
    Write-Host "`n💡 Added $BinDir to your Windows User PATH." -ForegroundColor Yellow
}

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host "✅ Installed: $InstalledCount tool(s) | Skipped (already installed): $SkippedCount" -ForegroundColor Green
Write-Host "======================================================`n" -ForegroundColor Green
