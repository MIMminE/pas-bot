$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$PasBin = Join-Path $ProjectRoot "bin\pas.exe"

Set-Location $ProjectRoot

if (Test-Path $PasBin) {
    & $PasBin --template-dir "$ProjectRoot" @args
    exit $LASTEXITCODE
}

$env:PYTHONPATH = Join-Path $ProjectRoot "src"
$PythonBin = if ($env:PYTHON_BIN) { $env:PYTHON_BIN } else { "python" }
& $PythonBin -m pas_automation.cli --template-dir "$ProjectRoot" @args
exit $LASTEXITCODE
