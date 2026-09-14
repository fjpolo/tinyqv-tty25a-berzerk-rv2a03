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
    [ValidateSet("all", "fpga", "asic")]
    [string]$Target = "all",
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
$FpgaFirmwareDir = Join-Path $RepoRoot "tinyQV-projects\rv2a03_fpga"
$AsicFirmwareDir = Join-Path $RepoRoot "tinyQV-projects\rv2a03_asic"
$LegacyDir       = Join-Path $RepoRoot "tinyQV-projects\rv2a03_test"
$Console60kHex   = Join-Path $RepoRoot "FPGA\GOWIN\console60k\src\rv2a03_test.hex"
$Nano20kHex      = Join-Path $RepoRoot "FPGA\GOWIN\nano20k\src\rv2a03_test.hex"

Write-Header "============================================================"
Write-Host   "   TinyQV RV2A03 Dual-Target Firmware Build System         " -ForegroundColor Cyan
Write-Host   "   Targets: FPGA (Tang 60K/20K) & ASIC (TTSKY25a EVK)      " -ForegroundColor DarkCyan
Write-Host   "   Selected: $Target                                       " -ForegroundColor Yellow
Write-Header "============================================================"

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

function Invoke-BuildProject($ProjectDir, $ProjectName) {
    if (-not (Test-Path $ProjectDir)) {
        Write-Err "Project directory not found: $ProjectDir"
        exit 1
    }

    Write-Header "Building $ProjectName..."
    $WslDir = ($ProjectDir -replace '\\', '/').Replace('C:', '/mnt/c').Replace('c:', '/mnt/c')

    if ($Clean) {
        Write-Info "Cleaning $ProjectName..."
        if ($UseWsl) {
            wsl bash -c "make -C '$WslDir' clean"
        } else {
            Push-Location $ProjectDir
            try { & make clean } finally { Pop-Location }
        }
    }

    if ($UseWsl) {
        $cmd = "make -C '$WslDir' all"
        if ($Sim) { $cmd += " CFLAGS='-DSIM'" }
        wsl bash -c "$cmd"
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Compilation of $ProjectName failed!"
            exit $LASTEXITCODE
        }
    } else {
        Push-Location $ProjectDir
        try {
            $MakeArgs = @()
            if ($Sim) { $MakeArgs += 'CFLAGS=-DSIM' }
            & make all @MakeArgs
            if ($LASTEXITCODE -ne 0) {
                Write-Err "Compilation of $ProjectName failed!"
                exit $LASTEXITCODE
            }
        } finally {
            Pop-Location
        }
    }

    $BinPath = Join-Path $ProjectDir "$ProjectName.bin"
    $HexPath = Join-Path $ProjectDir "$ProjectName.hex"

    if (-not (Test-Path $BinPath) -or -not (Test-Path $HexPath)) {
        Write-Err "Expected outputs for $ProjectName were not created!"
        exit 1
    }

    $BinSize = (Get-Item $BinPath).Length
    Write-Success ("{0} built successfully! ({1:N0} bytes)" -f $ProjectName, $BinSize)
    Write-Host "  Binary : $BinPath"
    Write-Host "  Hex    : $HexPath"

    return @{ Bin = $BinPath; Hex = $HexPath; Size = $BinSize }
}

# 1. Build FPGA Target
if ($Target -in @("all", "fpga")) {
    $FpgaOut = Invoke-BuildProject $FpgaFirmwareDir "rv2a03_fpga"
    
    # Also sync legacy rv2a03_test for backward compatibility
    if (Test-Path $LegacyDir) {
        Invoke-BuildProject $LegacyDir "rv2a03_test" | Out-Null
    }

    # Copy Hex to FPGA source folders
    if (-not $NoCopyHex) {
        Write-Header "Updating FPGA bitstream hex files..."
        if (Test-Path (Split-Path $Console60kHex)) {
            Copy-Item -Path $FpgaOut.Hex -Destination $Console60kHex -Force
            Write-Success "Updated: FPGA/GOWIN/console60k/src/rv2a03_test.hex"
        }
        if (Test-Path (Split-Path $Nano20kHex)) {
            Copy-Item -Path $FpgaOut.Hex -Destination $Nano20kHex -Force
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
}

# 2. Build ASIC Target
if ($Target -in @("all", "asic")) {
    $AsicOut = Invoke-BuildProject $AsicFirmwareDir "rv2a03_asic"
    
    Write-Header "------------------------------------------------------------"
    Write-Host   "  TTSKY25a EVK Flashing Instructions                        " -ForegroundColor Yellow
    Write-Header "------------------------------------------------------------"
    Write-Host   "  Target Chip   : TinyQV Sky25a Berzerk (Slot 14)"
    Write-Host   ("  Binary File   : {0}" -f $AsicOut.Bin)
    Write-Host   ("  Binary Size   : {0:N0} bytes" -f $AsicOut.Size)
    Write-Host   "  Web Programmer: https://program.tinyqv.com"
    Write-Host   "  CLI Command   : python -m tt_commander program flash rv2a03_asic.bin"
}

Write-Header "============================================================"
Write-Host   "   Firmware Build Complete!                                 " -ForegroundColor Green
Write-Header "============================================================"
