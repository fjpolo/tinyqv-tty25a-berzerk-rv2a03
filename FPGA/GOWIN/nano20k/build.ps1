<#
.SYNOPSIS
    Build and flash script for Gowin FPGA (Sipeed Tang Nano 20K).

.DESCRIPTION
    Automates logic synthesis, place & route, bitstream (.fs) generation,
    and board programming for the TinyQV RV2A03 APU SoC on the Sipeed Tang Nano 20K.

.PARAMETER Target
    Build target: 'all' (default: synthesis + PnR + bitstream), 'syn' (synthesis only), or 'pnr' (PnR only).

.PARAMETER Clean
    Cleans the 'impl/' build directory and temporary project files before building.

.PARAMETER Flash
    Programs the board after building (or standalone if bitstream exists):
    'sram' (fast volatile RAM load) or 'flash' (persistent onboard embFlash programming).

.PARAMETER Scan
    Scans for connected Gowin USB cables and FPGA JTAG devices.

.PARAMETER GowinPath
    Custom path to Gowin EDA installation directory.

.EXAMPLE
    .\build.ps1
    # Full build: synthesis, placement, routing, bitstream generation

.EXAMPLE
    .\build.ps1 -Clean
    # Clean build directory and rebuild everything

.EXAMPLE
    .\build.ps1 -Target syn
    # Run logic synthesis only

.EXAMPLE
    .\build.ps1 -Flash sram
    # Build and load bitstream directly into Tang Nano 20K SRAM

.EXAMPLE
    .\build.ps1 -Flash flash
    # Build and write bitstream to Tang Nano 20K persistent flash memory

.EXAMPLE
    .\build.ps1 -Scan
    # Detect connected Tang Nano 20K board
#>

[CmdletBinding()]
param (
    [ValidateSet("all", "syn", "pnr")]
    [string]$Target = "all",

    [switch]$Clean,

    [ValidateSet("sram", "flash", "")]
    [string]$Flash = "",

    [switch]$Scan,

    [string]$GowinPath = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "   Sipeed Tang Nano 20K - Gowin EDA Build Flow" -ForegroundColor Cyan
Write-Host "   Project: TinyQV RISC-V SoC + RV2A03 APU" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. Locate Gowin Installation
# -----------------------------------------------------------------------------
$SearchPaths = @()
if ($GowinPath) { $SearchPaths += $GowinPath }
if ($env:GOWIN_HOME) { $SearchPaths += $env:GOWIN_HOME }

# Common installation locations on Windows
$SearchPaths += @(
    "C:\Gowin\Gowin_V1.9.12_x64",
    "C:\Gowin\Gowin_V1.9.11_x64",
    "C:\Gowin\Gowin_V1.9.10_x64",
    "C:\Gowin\Gowin_V1.9.9_x64",
    "C:\Gowin\*"
)

$GwSh = $null
$ProgCli = $null

# Check PATH first
$PathGwSh = Get-Command "gw_sh.exe" -ErrorAction SilentlyContinue
if ($PathGwSh) {
    $GwSh = $PathGwSh.Source
}

if (-not $GwSh) {
    foreach ($path in $SearchPaths) {
        $resolved = Resolve-Path $path -ErrorAction SilentlyContinue
        foreach ($r in $resolved) {
            $candidateGwSh = Join-Path $r.Path "IDE\bin\gw_sh.exe"
            if (Test-Path $candidateGwSh) {
                $GwSh = $candidateGwSh
                $candidateProg = Join-Path $r.Path "Programmer\bin\programmer_cli.exe"
                if (Test-Path $candidateProg) {
                    $ProgCli = $candidateProg
                }
                break
            }
        }
        if ($GwSh) { break }
    }
}

if (-not $ProgCli -and $GwSh) {
    $GowinRoot = Split-Path (Split-Path (Split-Path $GwSh))
    $candidateProg = Join-Path $GowinRoot "Programmer\bin\programmer_cli.exe"
    if (Test-Path $candidateProg) {
        $ProgCli = $candidateProg
    }
}

if (-not $GwSh) {
    Write-Host "[ERROR] Could not find Gowin EDA installation (gw_sh.exe)!" -ForegroundColor Red
    Write-Host "Please install Gowin EDA or specify -GowinPath <path_to_gowin>" -ForegroundColor Yellow
    exit 1
}

Write-Host "[OK] Gowin Shell : $GwSh" -ForegroundColor Green
if ($ProgCli) {
    Write-Host "[OK] Programmer  : $ProgCli" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 2. Handle Scan Option
# -----------------------------------------------------------------------------
if ($Scan) {
    if (-not $ProgCli) {
        Write-Host "[ERROR] programmer_cli.exe not found!" -ForegroundColor Red
        exit 1
    }
    Write-Host "`nScanning for connected Gowin USB cables and devices..." -ForegroundColor Yellow
    & $ProgCli --scan-cables
    & $ProgCli --scan
    exit 0
}

# -----------------------------------------------------------------------------
# 3. Clean Build Artifacts
# -----------------------------------------------------------------------------
if ($Clean) {
    Write-Host "`nCleaning build artifacts..." -ForegroundColor Yellow
    $ImplDir = Join-Path $ScriptDir "impl"
    if (Test-Path $ImplDir) {
        Remove-Item -Recurse -Force $ImplDir
        Write-Host "[OK] Removed $ImplDir" -ForegroundColor Green
    }
    $UserFile = Join-Path $ScriptDir "nano20k.gprj.user"
    if (Test-Path $UserFile) {
        Remove-Item -Force $UserFile
    }
}

# -----------------------------------------------------------------------------
# 4. Run Build Process
# -----------------------------------------------------------------------------
$TclScript = Join-Path $ScriptDir "build.tcl"
if (-not (Test-Path $TclScript)) {
    Write-Host "[ERROR] build.tcl not found at $TclScript" -ForegroundColor Red
    exit 1
}

$Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "`n===> Starting Gowin Build Target: [$Target]..." -ForegroundColor Magenta
& $GwSh $TclScript $Target

if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[ERROR] Gowin build failed with exit code $LASTEXITCODE!" -ForegroundColor Red
    exit $LASTEXITCODE
}

$Stopwatch.Stop()
$Duration = [math]::Round($Stopwatch.Elapsed.TotalSeconds, 1)

# -----------------------------------------------------------------------------
# 5. Check Output Bitstream
# -----------------------------------------------------------------------------
$BitstreamPath = Join-Path $ScriptDir "impl\pnr\nano20k.fs"

if ($Target -eq "all") {
    if (Test-Path $BitstreamPath) {
        $FileSize = (Get-Item $BitstreamPath).Length
        $FileSizeKb = [math]::Round($FileSize / 1024, 1)
        Write-Host "`n============================================================" -ForegroundColor Green
        Write-Host "  BUILD SUCCESSFUL ($Duration s)" -ForegroundColor Green
        Write-Host "  Bitstream: $BitstreamPath ($FileSizeKb KB)" -ForegroundColor Green
        Write-Host "============================================================" -ForegroundColor Green
    } else {
        Write-Host "`n[WARNING] Build finished but bitstream was not found at $BitstreamPath" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n[OK] Target '$Target' completed successfully ($Duration s)." -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 6. Flash Board (if requested)
# -----------------------------------------------------------------------------
if ($Flash) {
    if (-not $ProgCli) {
        Write-Host "`n[ERROR] programmer_cli.exe not found for programming!" -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path $BitstreamPath)) {
        Write-Host "`n[ERROR] Bitstream not found at $BitstreamPath! Run full build first." -ForegroundColor Red
        exit 1
    }

    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "  Flashing Tang Nano 20K (Mode: $Flash)..." -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    if ($Flash -eq "sram") {
        # Mode 2: SRAM Program (volatile, instant test)
        Write-Host "Programming directly into SRAM (volatile)..." -ForegroundColor Yellow
        & $ProgCli --device "GW2AR-18C" --run 2 --fsFile "$BitstreamPath"
    } elseif ($Flash -eq "flash") {
        # Mode 1: embFlash Erase and Program (non-volatile, persistent)
        Write-Host "Programming onboard embFlash (persistent)..." -ForegroundColor Yellow
        & $ProgCli --device "GW2AR-18C" --run 1 --fsFile "$BitstreamPath"
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n[SUCCESS] FPGA successfully programmed!" -ForegroundColor Green
    } else {
        Write-Host "`n[ERROR] Programming failed with code $LASTEXITCODE." -ForegroundColor Red
        exit $LASTEXITCODE
    }
}
