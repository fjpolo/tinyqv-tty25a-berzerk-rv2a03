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

.PARAMETER FlashMode
    Flash mode: 'sram' (fast volatile SRAM load) or 'flash' (persistent external SPI Flash programming).

.PARAMETER Flash
    Switch flag to enable board programming after building (or standalone if -NoBuild specified).
    Also accepts: -Flash sram or -Flash flash directly.

.PARAMETER NoBuild
    Skips synthesis and PnR, flashing the existing bitstream directly.

.PARAMETER Cable
    JTAG programmer cable name (default: 'USB Debugger A' for Tang Nano 20K).

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
    .\build.ps1 -FlashMode flash -Flash
    # Build and write bitstream to Tang Nano 20K persistent external SPI Flash

.EXAMPLE
    .\build.ps1 -Flash sram
    # Build and load bitstream directly into Tang Nano 20K SRAM

.EXAMPLE
    .\build.ps1 -NoBuild -FlashMode flash
    # Flash existing bitstream to persistent SPI Flash without rebuilding

.EXAMPLE
    .\build.ps1 -Scan
    # Detect connected Tang Nano 20K board
#>

[CmdletBinding()]
param (
    [ValidateSet("all", "syn", "pnr")]
    [string]$Target = "all",

    [switch]$Clean,

    [ValidateSet("sram", "flash")]
    [string]$FlashMode = "sram",

    [switch]$Flash,

    [string]$Cable = "USB Debugger A",

    [switch]$NoBuild,

    [switch]$Scan,

    [string]$GowinPath = "",

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

# Flexible handling of -Flash and -FlashMode
if ($RemainingArgs) {
    foreach ($arg in $RemainingArgs) {
        if ($arg -in @("sram", "flash")) {
            $FlashMode = $arg
            $Flash = $true
        }
    }
}
if ($PSBoundParameters.ContainsKey('FlashMode')) {
    $Flash = $true
}

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
    $CableArgs = @()
    if ($Cable) { $CableArgs = @("--cable", $Cable) }
    & $ProgCli @CableArgs --scan
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
$BitstreamPath = Join-Path $ScriptDir "impl\pnr\nano20k.fs"

if (-not $NoBuild) {
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
} else {
    Write-Host "`n[INFO] Skipping build step (-NoBuild specified). Using existing bitstream." -ForegroundColor Cyan
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

    $CableArgs = @()
    if ($Cable) {
        $CableArgs = @("--cable", $Cable)
    }

    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "  Flashing Tang Nano 20K (Mode: $FlashMode)..." -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    if ($FlashMode -eq "sram") {
        # Mode 2: SRAM Program (volatile, instant test)
        Write-Host "Programming directly into SRAM (volatile)..." -ForegroundColor Yellow
        & $ProgCli @CableArgs --device "GW2AR-18C" --run 2 --fsFile "$BitstreamPath"
    } elseif ($FlashMode -eq "flash") {
        # Mode 8: exFlash Erase and Program (non-volatile, persistent onboard Winbond SPI Flash)
        Write-Host "Programming onboard external SPI Flash (exFlash, persistent)..." -ForegroundColor Yellow
        & $ProgCli @CableArgs --device "GW2AR-18C" --run 8 --fsFile "$BitstreamPath"
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n[SUCCESS] FPGA successfully programmed!" -ForegroundColor Green
    } else {
        Write-Host "`n[ERROR] Programming failed with code $LASTEXITCODE." -ForegroundColor Red
        exit $LASTEXITCODE
    }
}
