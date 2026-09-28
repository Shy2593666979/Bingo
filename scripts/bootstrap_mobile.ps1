$ErrorActionPreference = "Stop"
$mobileRoot = Join-Path $PSScriptRoot "../apps/mobile"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "Flutter is not installed or is not available on PATH."
}

Push-Location $mobileRoot
try {
    flutter pub get
    flutter analyze
    flutter test
}
finally {
    Pop-Location
}
