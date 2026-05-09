$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$PasBin = Join-Path $ProjectRoot "bin\pas.exe"

Set-Location $ProjectRoot

if (Test-Path $PasBin) {
    & $PasBin --config "$ProjectRoot\config.toml" --env "$ProjectRoot\.env" @args
    exit $LASTEXITCODE
}

$env:PYTHONPATH = Join-Path $ProjectRoot "src"
$PythonBin = if ($env:PYTHON_BIN) { $env:PYTHON_BIN } else { "python" }
& $PythonBin -m pas_automation.cli --config "$ProjectRoot\config.toml" --env "$ProjectRoot\.env" @args
exit $LASTEXITCODE
