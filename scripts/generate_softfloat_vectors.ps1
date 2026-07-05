param(
    [string]$SoftFloatRoot = "",
    [int]$RandomVectorsPerCase = 128,
    [uint32]$Seed = 0x18932F5A
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$WorkspaceRoot = Split-Path -Parent $RepoRoot
$DependencyRoot = Join-Path $WorkspaceRoot ".deps"

if ([string]::IsNullOrWhiteSpace($SoftFloatRoot)) {
    $SoftFloatRoot = Join-Path $DependencyRoot "berkeley-softfloat-3"
}

if (-not (Test-Path -LiteralPath $SoftFloatRoot)) {
    New-Item -ItemType Directory -Force -Path $DependencyRoot | Out-Null
    git clone --depth 1 `
        https://github.com/ucb-bar/berkeley-softfloat-3.git `
        $SoftFloatRoot
}

$BuildDirectory = Join-Path $SoftFloatRoot "build\Win32-MinGW"
$SoftFloatLibrary = Join-Path $BuildDirectory "softfloat.a"
$GeneratorSource = Join-Path $PSScriptRoot "softfloat\gen_rv32f_vectors.c"
$GeneratorBinary = Join-Path $PSScriptRoot "softfloat\gen_rv32f_vectors.exe"
$VectorFile = Join-Path $RepoRoot `
    "OoO_RISC_V_CPU_DESIGN.srcs\sim_1\new\fp_softfloat_vectors.txt"

Push-Location $BuildDirectory
try {
    mingw32-make SPECIALIZE_TYPE=RISCV
}
finally {
    Pop-Location
}

$IncludeDirectory = Join-Path $SoftFloatRoot "source\include"
& gcc -std=c99 -O2 `
    "-I$IncludeDirectory" `
    $GeneratorSource `
    $SoftFloatLibrary `
    -o $GeneratorBinary

if ($LASTEXITCODE -ne 0) {
    throw "Failed to compile the SoftFloat vector generator."
}

& $GeneratorBinary `
    $VectorFile `
    $RandomVectorsPerCase `
    ("0x{0:x8}" -f $Seed)

if ($LASTEXITCODE -ne 0) {
    throw "SoftFloat vector generation failed."
}

Write-Host "SoftFloat vectors are ready at:"
Write-Host "  $VectorFile"
