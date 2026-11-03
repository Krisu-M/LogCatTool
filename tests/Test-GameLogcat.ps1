$ErrorActionPreference = 'Stop'
$source = [IO.File]::ReadAllText((Join-Path (Split-Path -Parent $PSScriptRoot) 'Game_Logcat.ps1'), [Text.Encoding]::UTF8)
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Source parse failed' }
$functions = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $false)
foreach ($definition in $functions) { . ([scriptblock]::Create($definition.Extent.Text)) }
$original = @{}
foreach ($definition in $functions) { $original[$definition.Name] = (Get-Item ('Function:' + $definition.Name)).ScriptBlock }
function Assert($Condition, $Message) { if (-not $Condition) { throw "FAILED: $Message" }; Write-Host "PASS: $Message" }

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('GameLogcat-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$script:ToolDirectory = $PSScriptRoot
$script:InstallRoot = Join-Path $testRoot 'install'
$script:LogFile = Join-Path $testRoot 'game_logcat.txt'
Assert (-not (Test-Adb (Join-Path $testRoot 'missing-adb.exe'))) 'Missing adb executable is rejected'
$script:ExpectedAdb = Join-Path $script:InstallRoot 'platform-tools\adb.exe'
function Test-Adb { param($Path) return $Path -eq $script:ExpectedAdb }
Assert ((Find-Adb) -eq $script:ExpectedAdb) 'Previously installed adb is discovered'
Set-Item Function:Test-Adb $original['Test-Adb']

function Invoke-FakeAdb {
    $script:Calls += ,($args -join ' ')
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'start-server') { return }
    if ($args[0] -eq 'devices') { return $script:DeviceLines }
    if ($args -contains '-c') { $global:LASTEXITCODE = $script:ClearExit; return }
    'fresh log: 中文测试'
    'fresh log: second line'
}
function Read-Host { param($Prompt) return $script:Answers.Dequeue() }
$script:Calls = @()
$script:DeviceLines = @('List of devices attached', 'PHONE_A device product:test model:test')
Assert ((Select-Device 'Invoke-FakeAdb') -eq 'PHONE_A') 'Single authorized device selected'
$script:Answers = New-Object 'System.Collections.Generic.Queue[string]'
$script:Answers.Enqueue('2')
$script:DeviceLines += 'PHONE_B device product:test model:test'
Assert ((Select-Device 'Invoke-FakeAdb') -eq 'PHONE_B') 'Multiple devices use selected serial'
$script:Answers.Enqueue('q')
$script:DeviceLines = @('List of devices attached', 'PHONE_A unauthorized')
Assert ($null -eq (Select-Device 'Invoke-FakeAdb')) 'Unauthorized device does not start capture'

[IO.File]::WriteAllText($script:LogFile, 'OLD LOG MUST DISAPPEAR')
$script:ClearExit = 0
$script:Calls = @()
Start-Capture 'Invoke-FakeAdb' 'PHONE_A'
$result = [IO.File]::ReadAllText($script:LogFile, [Text.Encoding]::UTF8)
Assert ($result -notmatch 'OLD LOG' -and $result.Contains('中文测试')) 'Old file replaced and UTF-8 logs retained'
Assert ($script:Calls[0] -eq '-s PHONE_A logcat -b all -c' -and $script:Calls[1] -eq '-s PHONE_A logcat -b all -v threadtime *:V') 'Selected device buffer cleared before streaming'

[IO.File]::WriteAllText($script:LogFile, 'PRESERVE ON CLEAR FAILURE')
$script:ClearExit = 1
$script:Calls = @()
$failed = $false
try { Start-Capture 'Invoke-FakeAdb' 'PHONE_A' } catch { $failed = $true }
Assert ($failed -and $script:Calls.Count -eq 1 -and [IO.File]::ReadAllText($script:LogFile) -eq 'PRESERVE ON CLEAR FAILURE') 'Clear failure aborts capture and preserves previous file'

function Find-Adb { return $script:DetectedAdb }
function Confirm-Install { $script:Flow += 'confirm'; return $script:Consent }
function Install-Adb { $script:Flow += 'install'; return 'installed-adb' }
function Select-Device { param($Adb) $script:Flow += "device:$Adb"; return 'PHONE_A' }
function Start-Capture { param($Adb, $Serial) $script:Flow += "capture:$Adb/$Serial" }
function Read-Host { param($Prompt) return '' }
$script:DetectedAdb = $null
$script:Consent = $false
$script:Flow = @()
Invoke-GameLogcat
Assert (($script:Flow -join ',') -eq 'confirm') 'No choice exits without install or capture'
$script:Consent = $true
$script:Flow = @()
Invoke-GameLogcat
Assert (($script:Flow -join ',') -eq 'confirm,install,device:installed-adb,capture:installed-adb/PHONE_A') 'Yes choice installs then captures'
$script:DetectedAdb = 'existing-adb'
$script:Flow = @()
Invoke-GameLogcat
Assert (($script:Flow -join ',') -eq 'device:existing-adb,capture:existing-adb/PHONE_A') 'Existing adb skips installation question'

Set-Item Function:Install-Adb $original['Install-Adb']
function Invoke-WebRequest {
    param($Uri, $OutFile, [switch]$UseBasicParsing, $TimeoutSec)
    $script:DownloadUrl = $Uri
    $script:DownloadedArchive = $OutFile
    if ($script:DownloadFails) { throw 'simulated network failure' }
    [IO.File]::WriteAllText($OutFile, 'mock archive')
}
function Expand-Archive {
    param($LiteralPath, $DestinationPath, [switch]$Force)
    New-Item -ItemType Directory -Path (Join-Path $DestinationPath 'platform-tools') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $DestinationPath 'platform-tools\adb.exe'), 'mock executable')
}
function Test-Adb { param($Path) return Test-Path -LiteralPath $Path }
$script:DownloadFails = $false
$installed = Install-Adb
Assert ($installed -eq (Join-Path $script:InstallRoot 'platform-tools\adb.exe') -and $script:DownloadUrl -eq 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip') 'Install uses official HTTPS URL and expected folder'
Assert (-not (Test-Path -LiteralPath $script:DownloadedArchive)) 'Temporary archive removed after install'
$script:DownloadFails = $true
$failed = $false
try { Install-Adb } catch { $failed = $_.Exception.Message -match 'simulated network failure' }
Assert $failed 'Download failure is surfaced'
Write-Host 'ALL TESTS PASSED; no device logs cleared and no real installation performed.'
