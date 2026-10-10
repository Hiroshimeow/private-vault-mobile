param(
  [string]$DeviceId = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Checked {
  param(
    [string]$Name,
    [scriptblock]$Command
  )

  Write-Host "=== $Name ==="
  & $Command
  if ($LASTEXITCODE -ne 0) {
    throw "$Name failed with exit code $LASTEXITCODE"
  }
}

$repository = (Get-Location).Path
$tooling = Join-Path $repository ".tooling"
$flutter = Join-Path $tooling "flutter\bin\flutter.bat"
$androidSdk = Join-Path $tooling "android-sdk"
$javaHome = Join-Path $tooling "jdk17"
$gradle = Join-Path $repository "android\gradlew.bat"

foreach ($required in @($flutter, $gradle, $androidSdk, $javaHome)) {
  if (-not (Test-Path $required)) {
    throw "Required g6 tooling path is unavailable: $required"
  }
}

Set-Item -Path 'Env:ProgramFiles(x86)' -Value 'C:\Program Files (x86)'
$env:JAVA_HOME = $javaHome
$env:ANDROID_HOME = $androidSdk
$env:ANDROID_SDK_ROOT = $androidSdk

Invoke-Checked "Flutter tests" {
  & $flutter test --no-pub
}

Invoke-Checked "Flutter analyzer" {
  & $flutter analyze --no-pub
}

Push-Location (Join-Path $repository "android")
try {
  Invoke-Checked "Android app unit tests" {
    & $gradle ":app:testDebugUnitTest" "--no-daemon" "-Pkotlin.incremental=false" "-Dkotlin.compiler.execution.strategy=in-process"
  }

  Invoke-Checked "Plugin host unit tests" {
    & $gradle ":pluginhost:testSlot0DebugUnitTest" "--no-daemon" "-Pkotlin.incremental=false" "-Dkotlin.compiler.execution.strategy=in-process"
  }

  Invoke-Checked "Android debug assemble" {
    & $gradle ":app:assembleDebug" ":pluginhost:assembleSlot0Debug" ":pluginhost:assembleSlot1Debug" ":pluginfixture:assembleDebug" "--no-daemon" "-Pkotlin.incremental=false" "-Dkotlin.compiler.execution.strategy=in-process"
  }
} finally {
  Pop-Location
}

if ($DeviceId) {
  Invoke-Checked "RC integration test on $DeviceId" {
    & $flutter test integration_test\private_vault_rc_test.dart -d $DeviceId
  }
} else {
  $adb = Join-Path $androidSdk "platform-tools\adb.exe"
  Write-Host "=== Android target probe ==="
  & $adb devices -l
  Write-Host "No -DeviceId supplied; Android device integration test skipped."
}

Write-Host "g6 verification completed."
