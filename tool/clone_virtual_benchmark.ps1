param([string]$Serial = "")

$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) { $adb = 'F:\Data\platform-tools\adb.exe' }

function Write-NotMeasured([string]$reason) {
    Write-Output "registration_create_latency=NOT_MEASURED ($reason)"
    Write-Output "cold_launch_latency=NOT_MEASURED ($reason)"
    Write-Output "warm_launch_latency=NOT_MEASURED ($reason)"
    Write-Output "pss=NOT_MEASURED ($reason)"
    Write-Output "process_count=NOT_MEASURED ($reason)"
    Write-Output "cpu_launch=NOT_MEASURED ($reason)"
    Write-Output "per_slot_storage=NOT_MEASURED ($reason)"
}

if (-not (Test-Path $adb)) {
    Write-Output 'device=NOT_MEASURED (adb unavailable)'
    Write-NotMeasured 'adb unavailable'
    exit 0
}

$adbArgs = @()
if ($Serial) { $adbArgs += @('-s', $Serial) }
$deviceLines = & $adb @adbArgs devices 2>$null | Select-String "\tdevice$"
if (-not $deviceLines) {
    Write-Output 'device=NOT_MEASURED (no authorized device)'
    Write-NotMeasured 'no authorized device'
    exit 0
}

$slotPackages = @(
    'io.hiroshimeow.private_vault.clonehost.slot0',
    'io.hiroshimeow.private_vault.clonehost.slot1'
)
Write-Output 'authorized_device=YES'
Write-Output "device_sdk=$(& $adb @adbArgs shell getprop ro.build.version.sdk 2>$null)"

$missing = @($slotPackages | Where-Object { -not (& $adb @adbArgs shell pm path $_ 2>$null) })
if ($missing.Count -gt 0) {
    Write-Output "acceptance=NOT_TESTED (missing packages: $($missing -join ','))"
    Write-NotMeasured 'clonehost debug packages not installed'
    exit 0
}

# The source acceptance test owns registration/removal and is intentionally separate from metric collection.
# This script never bypasses the signature-protected provider from the adb shell.
$processes = @($slotPackages | ForEach-Object { (& $adb @adbArgs shell pidof $_ 2>$null).Trim() } | Where-Object { $_ })
Write-Output "process_count=$($processes.Count)"

foreach ($package in $slotPackages) {
    $pid = (& $adb @adbArgs shell pidof $package 2>$null).Trim()
    if ($pid) {
        $mem = & $adb @adbArgs shell dumpsys meminfo $package 2>$null
        $total = $mem | Select-String '^\s*TOTAL\s+(\d+)' | Select-Object -First 1
        if ($total -and $total.Matches.Count -gt 0) {
            Write-Output "$package.pss_kb=$($total.Matches[0].Groups[1].Value)"
        } else {
            Write-Output "$package.pss_kb=NOT_MEASURED (dumpsys format unsupported)"
        }
        $cpu = & $adb @adbArgs shell top -b -n 1 -p $pid 2>$null | Select-String "\s$pid\s" | Select-Object -First 1
        Write-Output "$package.cpu_snapshot=$([string]$cpu)"
    } else {
        Write-Output "$package.pss_kb=NOT_MEASURED (process not running)"
        Write-Output "$package.cpu_snapshot=NOT_MEASURED (process not running)"
    }
    $storage = & $adb @adbArgs shell run-as $package du -sk . 2>$null
    if ($LASTEXITCODE -eq 0 -and $storage) {
        Write-Output "$package.storage_kb=$(([string]$storage).Split()[0])"
    } else {
        Write-Output "$package.storage_kb=NOT_MEASURED (run-as unavailable)"
    }
}

Write-Output 'registration_create_latency=NOT_MEASURED (acceptance test does not yet emit operation timing)'
Write-Output 'cold_launch_latency=NOT_MEASURED (launch completion timing requires on-device instrumentation signal)'
Write-Output 'warm_launch_latency=NOT_MEASURED (launch completion timing requires on-device instrumentation signal)'
Write-Output 'cpu_launch=NOT_MEASURED (only post-run cpu snapshots are collected)'
Write-Output 'per_slot_storage=SEE slot package storage_kb fields above'
