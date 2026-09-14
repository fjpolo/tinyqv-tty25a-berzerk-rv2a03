<#
.SYNOPSIS
    Builds the RV2A03 firmware testsuite for TinyQV SoC.

.DESCRIPTION
    Compiles the C firmware in tinyQV-projects/rv2a03_test using the RISC-V 32-bit
    toolchain (via WSL or native Windows toolchain if available), checks memory usage
    against the 32 KB BRAM ceiling, and syncs the updated hex file to the Gowin FPGA projects.

.PARAMETER Clean
    Performs a 'make clean' before compiling.

.PARAMETER Sim
    Builds with CFLAGS="-DSIM" for fast verilog / cocotb simulation.

.PARAMETER NoCopyHex
    Skips copying the generated rv2a03_test.hex to the Gowin FPGA source directories.

.PARAMETER RebuildFpga
    Optionally triggers Gowin bitstream rebuild for the specified board ("console60k" or "nano20k").

.PARAMETER Flash
    Optionally flashes the board after FPGA build ("sram" or "flash").

.EXAMPLE
    .\build_firmware.bat
    Compiles firmware, prints memory stats, and updates FPGA hex files.

.EXAMPLE
    .\build_firmware.bat -Clean
    Cleans previous build artifacts and compiles from scratch.

.EXAMPLE
    .\build_firmware.bat -RebuildFpga console60k -Flash sram
    Full pipeline: compiles firmware, updates hex, rebuilds bitstream, and flashes Tang Console 60K SRAM!
#>

[CmdletBinding()]
param (
    [switch]$Clean,
    [switch]$Sim,
    [switch]$NoCopyHex,
    [ValidateSet("none", "console60k", "nano20k")]
    [string]$RebuildFpga = "none",
    [ValidateSet("", "sram", "flash")]
    [string]$Flash = ""
)

$ErrorActionPreference = "Stop"

# Colors
function Write-Header($msg) { Write-Host "`n$msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Info($msg)    { Write-Host "[INFO] $msg" -ForegroundColor Yellow }
function Write-Err($msg)     { Write-Host "[ERROR] $msg" -ForegroundColor Red }

$RepoRoot = $PSScriptRoot
$FirmwareDir = Join-Path $RepoRoot "tinyQV-projects\rv2a03_test"
$Console60kHex = Join-Path $RepoRoot "FPGA\GOWIN\console60k\src\rv2a03_test.hex"
$Nano20kHex    = Join-Path $RepoRoot "FPGA\GOWIN\nano20k\src\rv2a03_test.hex"

Write-Header "============================================================"
Write-Host   "   TinyQV RV2A03 Firmware Build System                     " -ForegroundColor Cyan
Write-Host   "   Source: tinyQV-projects/rv2a03_test                     " -ForegroundColor DarkCyan
Write-Header "============================================================"

if (-not (Test-Path $FirmwareDir)) {
    Write-Err "Firmware directory not found: $FirmwareDir"
    exit 1
}

# Determine build toolchain environment
$UseWsl = $false
$RiscvGcc = Get-Command "riscv32-unknown-elf-gcc" -ErrorAction SilentlyContinue

if ($RiscvGcc) {
    Write-Info "Found native RISC-V GCC: $($RiscvGcc.Source)"
} else {
    $WslCmd = Get-Command "wsl" -ErrorAction SilentlyContinue
    if ($WslCmd) {
        $UseWsl = $true
        Write-Info "Using RISC-V toolchain via WSL (/opt/tinyQV/bin/riscv32-unknown-elf-gcc)..."
    } else {
        Write-Err "Neither native riscv32-unknown-elf-gcc nor WSL found!"
        Write-Err "Please install the TinyQV RISC-V toolchain in WSL at /opt/tinyQV"
        exit 1
    }
}

# Assemble make commands
$MakeArgs = @()
if ($Sim) {
    $MakeArgs += 'CFLAGS=-DSIM'
}

# Clean if requested
if ($Clean) {
    Write-Info "Cleaning previous build artifacts..."
    if ($UseWsl) {
        $WslDir = ($FirmwareDir -replace '\\', '/').Replace('C:', '/mnt/c').Replace('c:', '/mnt/c')
        wsl make -C "$WslDir" clean
    } else {
        Push-Location $FirmwareDir
        try { & make clean } finally { Pop-Location }
    }
}

# Build firmware
Write-Header "Building RV2A03 firmware..."
if ($UseWsl) {
    $WslDir = ($FirmwareDir -replace '\\', '/').Replace('C:', '/mnt/c').Replace('c:', '/mnt/c')
    $cmd = "make -C '$WslDir' all"
    if ($Sim) { $cmd += " CFLAGS='-DSIM'" }
    wsl bash -c "$cmd"
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Firmware compilation failed!"
        exit $LASTEXITCODE
    }
} else {
    Push-Location $FirmwareDir
    try {
        & make all @MakeArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Firmware compilation failed!"
            exit $LASTEXITCODE
        }
    } finally {
        Pop-Location
    }
}

Write-Success "Firmware compiled successfully!"

# Verify outputs
$BinPath = Join-Path $FirmwareDir "rv2a03_test.bin"
$HexPath = Join-Path $FirmwareDir "rv2a03_test.hex"
$ElfPath = Join-Path $FirmwareDir "rv2a03_test.elf"

if (-not (Test-Path $BinPath) -or -not (Test-Path $HexPath)) {
    Write-Err "Expected build outputs (.bin / .hex) were not created!"
    exit 1
}

$BinSize = (Get-Item $BinPath).Length
$BramCap = 32768  # 32 KB Block RAM capacity
$Pct = [math]::Round(($BinSize / $BramCap) * 100, 1)

Write-Header "------------------------------------------------------------"
Write-Host   "  Memory Utilization Report                                 " -ForegroundColor Green
Write-Header "------------------------------------------------------------"
Write-Host   ("  Binary File : {0}" -f $BinPath)
Write-Host   ("  Binary Size : {0:N0} bytes / {1:N0} bytes ({2}% of 32KB BRAM)" -f $BinSize, $BramCap, $Pct) -ForegroundColor $(if ($Pct -gt 90) { "Red" } elseif ($Pct -gt 75) { "Yellow" } else { "Green" })
Write-Host   ("  Hex File    : {0}" -f $HexPath)

# Copy Hex to FPGA source folders
if (-not $NoCopyHex) {
    Write-Header "Updating FPGA project hex files..."
    if (Test-Path (Split-Path $Console60kHex)) {
        Copy-Item -Path $HexPath -Destination $Console60kHex -Force
        Write-Success "Updated: FPGA/GOWIN/console60k/src/rv2a03_test.hex"
    }
    if (Test-Path (Split-Path $Nano20kHex)) {
        Copy-Item -Path $HexPath -Destination $Nano20kHex -Force
        Write-Success "Updated: FPGA/GOWIN/nano20k/src/rv2a03_test.hex"
    }
} else {
    Write-Info "Skipping FPGA hex copy (-NoCopyHex specified)."
}

# Optional FPGA rebuild / flash
if ($RebuildFpga -ne "none") {
    Write-Header "Triggering FPGA bitstream rebuild for $RebuildFpga..."
    $FpgaScript = Join-Path $RepoRoot "FPGA\GOWIN\$RebuildFpga\build.ps1"
    if (-not (Test-Path $FpgaScript)) {
        Write-Err "FPGA build script not found: $FpgaScript"
        exit 1
    }
    
    $FpgaParams = @{ Target = "all" }
    if ($Flash -ne "") {
        $FpgaParams["Flash"] = $Flash
    }
    
    & $FpgaScript @FpgaParams
}

Write-Header "============================================================"
Write-Host   "   Firmware Build Complete!                                 " -ForegroundColor Green
Write-Header "============================================================"
