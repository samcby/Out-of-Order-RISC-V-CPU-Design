param(
    [string]$Vivado = "D:\Vivado\Vivado\2019.1\bin\vivado.bat"
)

$ErrorActionPreference = "Stop"
$asicDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $asicDir
$script = Join-Path $asicDir "scripts\vivado_baseline.tcl"
$summarizer = Join-Path $repoRoot "scripts\summarize_asic_baseline.py"

if (-not (Test-Path -LiteralPath $Vivado)) {
    throw "Vivado executable not found: $Vivado"
}

Push-Location $repoRoot
try {
    & $Vivado -mode batch -source $script
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado synthesis proxy failed with exit code $LASTEXITCODE"
    }

    python $summarizer
    if ($LASTEXITCODE -ne 0) {
        throw "ASIC baseline report summarizer failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

Write-Host "Baseline summary: asic/reports/vivado_proxy/baseline_summary.txt"
