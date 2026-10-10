param(
    [string]$AdbPath = 'F:\Data\platform-tools\adb.exe',
    [string]$FlutterPath = 'E:\git-project\private-vault-mobile\.tooling\flutter\bin\flutter.bat',
    [string]$JavaHome = 'E:\git-project\private-vault-mobile-v12-workprofile\.tooling\jdk17'
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $repo
try {
    Write-Output "probe_repo=$repo"
    Write-Output "probe_head=$(git rev-parse HEAD)"
    Write-Output "probe_branch=$(git branch --show-current)"
    Write-Output 'probe_status_begin'
    git status --short
    Write-Output 'probe_status_end'

    Write-Output "flutter_path=$FlutterPath"
    Write-Output "flutter_exists=$(Test-Path $FlutterPath)"
    Write-Output "java_home=$JavaHome"
    Write-Output "java_exists=$(Test-Path (Join-Path $JavaHome 'bin\java.exe'))"
    Write-Output "adb_path=$AdbPath"
    Write-Output "adb_exists=$(Test-Path $AdbPath)"

    $deviceLines = @()
    if (Test-Path $AdbPath) {
        $deviceLines = @(& $AdbPath devices -l | Select-Object -Skip 1 | Where-Object { $_.Trim() })
    }
    Write-Output "adb_device_count=$($deviceLines.Count)"
    foreach ($line in $deviceLines) {
        Write-Output "adb_device=$line"
    }

    if ($deviceLines.Count -eq 0) {
        Write-Output 'clone_generation_latency=NOT_MEASURED'
        Write-Output 'clone_apk_size_delta=NOT_MEASURED'
        Write-Output 'install_interaction=NOT_MEASURED'
        Write-Output 'cold_launch_latency=NOT_MEASURED'
        Write-Output 'warm_launch_latency=NOT_MEASURED'
        Write-Output 'memory_pss_overhead=NOT_MEASURED'
        Write-Output 'storage_overhead=NOT_MEASURED'
    } else {
        Write-Output 'runtime_metrics=DEVICE_AVAILABLE_REQUIRES_AUTHORIZED_MANUAL_CLONE_PROBE'
    }
} finally {
    Pop-Location
}
