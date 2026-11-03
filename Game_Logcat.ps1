$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$script:ToolDirectory = if ($env:GAME_LOGCAT_SELF) { Split-Path -Parent $env:GAME_LOGCAT_SELF } else { $PSScriptRoot }
$script:InstallRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'GameLogcat'
$script:LogFile = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'game_logcat.txt'

function Test-Adb([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $version = & $Path version 2>$null
        return ($LASTEXITCODE -eq 0 -and ($version -join "`n") -match 'Android Debug Bridge version')
    } catch { return $false }
}

function Find-Adb {
    $candidates = @()
    $candidates += @(Get-Command adb.exe -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object { $_.Source })
    foreach ($scope in @('Process', 'User', 'Machine')) {
        foreach ($entry in ([Environment]::GetEnvironmentVariable('Path', $scope) -split ';')) {
            if ($entry.Trim()) {
                $directory = [Environment]::ExpandEnvironmentVariables($entry.Trim().Trim('"'))
                $candidates += Join-Path $directory 'adb.exe'
            }
        }
        foreach ($variable in @('ANDROID_HOME', 'ANDROID_SDK_ROOT')) {
            $sdk = [Environment]::GetEnvironmentVariable($variable, $scope)
            if ($sdk) { $candidates += Join-Path $sdk 'platform-tools\adb.exe' }
        }
    }
    $candidates += @(
        (Join-Path $script:InstallRoot 'platform-tools\adb.exe'),
        (Join-Path $script:ToolDirectory 'adb.exe'),
        (Join-Path $script:ToolDirectory 'platform-tools\adb.exe'),
        (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Android\Sdk\platform-tools\adb.exe'),
        'G:\AllDownload\platform-tools\adb.exe',
        'C:\Android\Sdk\platform-tools\adb.exe',
        'C:\Android\platform-tools\adb.exe',
        'C:\Tools\platform-tools\adb.exe',
        'C:\NVPACK\android-sdk-windows\platform-tools\adb.exe'
    )
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Adb $candidate) { return $candidate }
    }
    return $null
}

function Confirm-Install {
    $officialPage = 'https://developer.android.com/tools/releases/platform-tools'
    Write-Host "未找到可用的 adb。官方下载及许可条款：$officialPage"
    Add-Type -AssemblyName System.Windows.Forms
    $message = "未在 PATH、SDK 配置及常见目录中找到可用的 adb。`r`n`r`n是否下载并安装 Google 官方 Android SDK Platform-Tools？`r`n安装位置：$script:InstallRoot`r`n`r`n许可条款：$officialPage`r`n选择 Yes/是，表示同意上述许可条款并开始下载安装；选择 No/否退出。"
    $answer = [System.Windows.Forms.MessageBox]::Show($message, '游戏日志抓取 - 安装 adb', 'YesNo', 'Question', 'Button2')
    return $answer -eq [System.Windows.Forms.DialogResult]::Yes
}

function Install-Adb {
    $downloadUrl = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'
    $archive = Join-Path ([IO.Path]::GetTempPath()) ('GameLogcat-' + [Guid]::NewGuid().ToString('N') + '.zip')
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Write-Host '正在下载官方 Platform-Tools，请稍候……'
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $downloadUrl -OutFile $archive -UseBasicParsing -TimeoutSec 300
        New-Item -ItemType Directory -Path $script:InstallRoot -Force | Out-Null
        Expand-Archive -LiteralPath $archive -DestinationPath $script:InstallRoot -Force
        $adb = Join-Path $script:InstallRoot 'platform-tools\adb.exe'
        if (-not (Test-Adb $adb)) { throw '解压后的 adb 无法运行。' }
        Write-Host "安装完成：$adb"
        return $adb
    } catch {
        throw "adb 安装失败：$($_.Exception.Message)`n请检查网络能否访问 dl.google.com；也可从官方下载页手动下载，将 platform-tools 文件夹放在本工具旁边后重试。"
    } finally {
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue }
    }
}

function Select-Device([string]$Adb) {
    & $Adb start-server
    if ($LASTEXITCODE -ne 0) { throw '无法启动 adb 服务。' }
    while ($true) {
        $lines = @(& $Adb devices -l)
        if ($LASTEXITCODE -ne 0) { throw '无法获取设备列表。' }
        $ready = @()
        foreach ($line in $lines) {
            if ($line -match '^\s*(\S+)\s+device(?:\s|$)') {
                $ready += [PSCustomObject]@{ Serial = $Matches[1]; Description = $line.Trim() }
            }
        }
        if ($ready.Count -eq 1) { return $ready[0].Serial }
        if ($ready.Count -gt 1) {
            Write-Host '检测到多台设备，请选择要抓取的设备：'
            for ($i = 0; $i -lt $ready.Count; $i++) { Write-Host ("{0}. {1}" -f ($i + 1), $ready[$i].Description) }
            $choice = Read-Host '输入设备序号，或输入 Q 退出'
            if ($choice -eq 'q') { return $null }
            $number = 0
            if ([int]::TryParse($choice, [ref]$number) -and $number -ge 1 -and $number -le $ready.Count) {
                return $ready[$number - 1].Serial
            }
            Write-Host '序号无效，请重试。'
        } else {
            Write-Host ($lines -join "`n")
            Write-Host '未检测到可用设备。请连接手机、开启 USB 调试，并在手机上允许本电脑调试。'
            Write-Host '若列表为空，请检查数据线和设备驱动；若显示 offline，请重新连接。'
            if ((Read-Host '处理后按 Enter 重试，或输入 Q 退出') -eq 'q') { return $null }
        }
    }
}

function Start-Capture([string]$Adb, [string]$Serial) {
    # 先锁定输出文件，清空设备日志成功后再覆盖旧文件。
    $stream = [IO.File]::Open($script:LogFile, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    $writer = $null
    try {
        Write-Host '正在清空手机历史日志……'
        & $Adb -s $Serial logcat -b all -c
        if ($LASTEXITCODE -ne 0) { throw '清空手机日志失败，已停止抓取，旧日志文件未覆盖。' }
        $stream.SetLength(0)
        $writer = New-Object IO.StreamWriter($stream, (New-Object Text.UTF8Encoding($false)))
        $writer.AutoFlush = $true
        Write-Host "正在抓取设备：$Serial" -ForegroundColor Green
        Write-Host "日志文件：$script:LogFile"
        Write-Host '旧日志已清空。现在可以打开游戏并复现问题。'
        Write-Host '关闭此窗口即可停止抓取，已写入的日志会保留。'
        & $Adb -s $Serial logcat -b all -v threadtime '*:V' | ForEach-Object { $writer.WriteLine($_) }
        if ($LASTEXITCODE -ne 0) { throw '抓取已中断，请检查设备连接；已抓取的日志已保留。' }
        Write-Host '抓取已结束。'
    } finally {
        if ($null -ne $writer) { $writer.Dispose() } else { $stream.Dispose() }
    }
}

function Invoke-GameLogcat {
    $adb = Find-Adb
    if (-not $adb) {
        if (-not (Confirm-Install)) { return }
        $adb = Install-Adb
    }
    Write-Host "使用 adb：$adb"
    $serial = Select-Device $adb
    if (-not $serial) { return }
    Start-Capture $adb $serial
    [void](Read-Host '按 Enter 退出')
}

$mutex = New-Object Threading.Mutex($false, 'Local\GameLogcatCapture')
$locked = $false
try {
    try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
    if (-not $locked) { throw '已有一个抓取工具正在运行，请先关闭原窗口。' }
    Invoke-GameLogcat
} catch {
    Write-Host "`n错误：$($_.Exception.Message)" -ForegroundColor Red
    [void](Read-Host '按 Enter 退出')
    exit 1
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
