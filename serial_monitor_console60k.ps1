<#
.SYNOPSIS
    Real-Time Serial Monitor for TinyQV RV2A03 on Tang Console 60K.

.DESCRIPTION
    Connects to the Tang Console 60K onboard BL616 USB-UART bridge at 115200 baud.
    Auto-detects the FPGA UART COM port (COM19 / Channel B) if not specified.
    Displays incoming text with live streaming and clean exit.

.PARAMETER Port
    The COM port (e.g. "COM19"). If omitted, auto-detects the Tang Console 60K UART port.

.PARAMETER BaudRate
    Baud rate (default: 115200).

.PARAMETER List
    List all available COM ports and exit.
#>

[CmdletBinding()]
param(
    [Parameter(Position=0)]
    [string]$Port,

    [Parameter(Position=1)]
    [int]$BaudRate = 115200,

    [switch]$List,

    [string]$LogFile
)

$ErrorActionPreference = "Stop"

function Get-AvailablePorts {
    $ports = [System.Collections.Generic.List[PSCustomObject]]::new()
    $pnpDevices = @()
    try {
        $pnpDevices = @(Get-CimInstance Win32_PnPEntity | Where-Object Caption -match "COM\d+")
    } catch { }

    $allNames = @([System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object -Unique)

    foreach ($name in $allNames) {
        $desc = "Serial Port"
        $isUsb = $false
        $match = $pnpDevices | Where-Object { $_.Caption -like "*($name)*" }
        if ($match) {
            $desc = $match.Caption
            if ($match.DeviceID -match "USB|FTDI|VID_" -or $match.Manufacturer -match "FTDI") {
                $isUsb = $true
            }
        }
        $ports.Add([PSCustomObject]@{
            Port        = $name
            Description = $desc
            IsUsb       = $isUsb
        })
    }
    return $ports
}

# 1. Handle -List
if ($List) {
    Write-Host "`n=== Available Serial COM Ports ===" -ForegroundColor Cyan
    $available = @(Get-AvailablePorts)
    if ($available.Count -eq 0) {
        Write-Host "No COM ports detected." -ForegroundColor Yellow
    } else {
        $available | Format-Table -AutoSize
    }
    exit 0
}

# 2. Auto-detect Tang Console 60K Port if not supplied
if (-not $Port) {
    Write-Host "Auto-detecting Tang Console 60K USB-UART port..." -ForegroundColor Cyan
    $available = @(Get-AvailablePorts)

    # Tang Console 60K BL616 exposes Channel B as the FPGA UART (typically COM19)
    $consolePort = $available | Where-Object { $_.Port -eq "COM19" }
    if ($consolePort) {
        $Port = $consolePort.Port
        Write-Host "[OK] Detected Tang Console 60K FPGA UART: $Port ($($consolePort.Description))" -ForegroundColor Green
    } else {
        # Fallback: check other USB serial ports
        $usbPorts = @($available | Where-Object { $_.IsUsb -and $_.Description -notmatch "Bluetooth" })
        if ($usbPorts.Count -ge 1) {
            # Pick highest COM port for Channel B
            $selected = $usbPorts | Sort-Object Port -Descending | Select-Object -First 1
            $Port = $selected.Port
            Write-Host "[OK] Selected FPGA USB Serial Port: $Port ($($selected.Description))" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] No USB serial ports found! Please ensure Tang Console 60K is plugged into the MCU USB-C port." -ForegroundColor Red
            exit 1
        }
    }
}

if ($Port -match "^\d+$") {
    $Port = "COM$Port"
}

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host "  VS Code Serial Monitor: TinyQV RV2A03 (Tang Console 60K)" -ForegroundColor White
Write-Host "  Port      : $Port" -ForegroundColor Yellow
Write-Host "  Baud Rate : $BaudRate 8N1" -ForegroundColor Yellow
Write-Host "  Reset Tip : Press button S0 on the console to reset SoC & replay audio" -ForegroundColor Cyan
Write-Host "  Exit      : Press Ctrl+C to disconnect" -ForegroundColor Gray
Write-Host "============================================================`n" -ForegroundColor Green

# Open serial port
$sp = New-Object System.IO.Ports.SerialPort $Port, $BaudRate, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One
$sp.Handshake = [System.IO.Ports.Handshake]::None
$sp.ReadTimeout = 500
$sp.WriteTimeout = 500
$sp.Encoding = [System.Text.Encoding]::ASCII

$logWriter = $null
if ($LogFile) {
    $logWriter = [System.IO.StreamWriter]::new($LogFile, $true, [System.Text.Encoding]::UTF8)
    Write-Host "[LOG] Logging to file: $LogFile" -ForegroundColor Magenta
}

try {
    $sp.Open()
    $sp.DiscardInBuffer()
    Write-Host "Connected to $Port @ $BaudRate baud. Waiting for data...`n" -ForegroundColor Green

    # Register Ctrl+C handler
    [Console]::TreatControlCAsInput = $false

    while ($true) {
        try {
            $line = $sp.ReadLine()
            if ($line) {
                Write-Host $line
                if ($logWriter) {
                    $logWriter.WriteLine($line)
                    $logWriter.Flush()
                }
            }
        } catch [System.TimeoutException] {
            # Check for partial data in buffer
            if ($sp.BytesToRead -gt 0) {
                $raw = $sp.ReadExisting()
                Write-Host -NoNewline $raw
                if ($logWriter) {
                    $logWriter.Write($raw)
                    $logWriter.Flush()
                }
            }
        }
    }
} catch [System.Management.Automation.PipelineStoppedException] {
    # Normal exit on Ctrl+C
} catch {
    Write-Host "`n[ERROR] Serial error: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    if ($sp -and $sp.IsOpen) {
        $sp.Close()
        $sp.Dispose()
        Write-Host "`n[DISCONNECTED] Closed $Port." -ForegroundColor Yellow
    }
    if ($logWriter) {
        $logWriter.Close()
        $logWriter.Dispose()
    }
}
