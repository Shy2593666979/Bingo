param(
    [string]$DeviceId,
    [string]$ApiBaseUrl = "http://192.168.18.133:8000",
    [string]$ApiPrefix = "/api/v1",
    [string]$JavaHome
)

$ErrorActionPreference = "Stop"
$mobileRoot = Join-Path $PSScriptRoot "../apps/mobile"

$flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
$flutterCandidates = @(
    if ($flutterCommand) { $flutterCommand.Source }
    "D:\DevTools\flutter\bin\flutter.bat"
    "$env:LOCALAPPDATA\flutter\bin\flutter.bat"
    "$env:USERPROFILE\flutter\bin\flutter.bat"
    "C:\src\flutter\bin\flutter.bat"
)
$flutter = $flutterCandidates |
    Where-Object { $_ -and (Test-Path -LiteralPath $_) } |
    Select-Object -First 1

if (-not $flutter) {
    throw "Flutter SDK was not found. Add flutter to PATH or update the candidates in this script."
}

if (-not $JavaHome) {
    $javaCandidates = @(
        "D:\DevTools\jdk-17.0.20+8"
        "$env:ProgramFiles\Android\Android Studio\jbr"
        "$env:USERPROFILE\.jdks\ms-25.0.3"
    )
    $JavaHome = $javaCandidates |
        Where-Object { Test-Path -LiteralPath (Join-Path $_ "bin\java.exe") } |
        Select-Object -First 1
}

if (-not $JavaHome -or -not (Test-Path -LiteralPath (Join-Path $JavaHome "bin\java.exe"))) {
    throw "JDK 17 or later was not found. Pass its directory with -JavaHome."
}

$env:JAVA_HOME = $JavaHome
$env:Path = "$(Join-Path $JavaHome 'bin');$env:Path"

if (-not $DeviceId) {
    $devices = & $flutter devices --machine | ConvertFrom-Json
    $androidDevice = $devices |
        Where-Object { $_.targetPlatform -like "android-*" -and $_.isSupported } |
        Select-Object -First 1

    if (-not $androidDevice) {
        throw "No supported Android device found. Enable USB debugging and authorize this computer."
    }

    $DeviceId = $androidDevice.id
}

Write-Host "Flutter: $flutter"
Write-Host "Java:   $JavaHome"
Write-Host "Device:  $DeviceId"
Write-Host "API:     $ApiBaseUrl"
Write-Host "Prefix:  $ApiPrefix"
Write-Host "While running: r = hot reload, R = hot restart, q = quit"

Push-Location $mobileRoot
try {
    & $flutter run `
        --device-id $DeviceId `
        --dart-define="API_BASE_URL=$ApiBaseUrl" `
        --dart-define="API_PREFIX=$ApiPrefix"
}
finally {
    Pop-Location
}
