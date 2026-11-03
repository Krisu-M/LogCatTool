param(
    [ValidatePattern('^\d+\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$')]
    [string]$Version = '1.0.0'
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$payload = [IO.File]::ReadAllText((Join-Path $repoRoot 'Game_Logcat.ps1'), [Text.Encoding]::UTF8)
$tokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseInput($payload, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors -join "`n") }
$launcher = @'
@echo off
setlocal
chcp 65001 >nul
title Game Logcat
set "GAME_LOGCAT_SELF=%~f0"
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -Command "$text=[IO.File]::ReadAllText($env:GAME_LOGCAT_SELF,[Text.Encoding]::UTF8); & ([scriptblock]::Create(($text -split '(?m)^# POWERSHELL_PAYLOAD\r?$',2)[1]))"
exit /b %ERRORLEVEL%
# POWERSHELL_PAYLOAD
'@
$batPath = Join-Path $repoRoot 'Game_Logcat.bat'
$bat = ($launcher + "`n" + $payload) -replace '\r?\n', "`r`n"
[IO.File]::WriteAllText($batPath, $bat, (New-Object Text.UTF8Encoding($false)))
$dist = Join-Path $repoRoot 'dist'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$zip = Join-Path $dist "Game_Logcat_Tool-v$Version.zip"
Compress-Archive -LiteralPath @($batPath, (Join-Path $repoRoot '使用说明.txt')) -DestinationPath $zip -Force
$checksums = foreach ($file in @($zip, $batPath)) {
    $hash = Get-FileHash -LiteralPath $file -Algorithm SHA256
    '{0}  {1}' -f $hash.Hash.ToLowerInvariant(), [IO.Path]::GetFileName($file)
}
[IO.File]::WriteAllLines((Join-Path $dist 'SHA256SUMS.txt'), $checksums, (New-Object Text.UTF8Encoding($false)))
Write-Host "Built: $zip"
