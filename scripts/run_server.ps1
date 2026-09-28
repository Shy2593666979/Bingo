$ErrorActionPreference = "Stop"
$serverRoot = Join-Path $PSScriptRoot "../apps/server"

Push-Location $serverRoot
try {
    uv sync --extra dev
    uv run python -m bingo
}
finally {
    Pop-Location
}
