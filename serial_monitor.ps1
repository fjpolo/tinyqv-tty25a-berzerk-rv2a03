<#
.SYNOPSIS
    Real-Time Serial Monitor for TinyQV RV2A03 on Tang Nano 20K in VS Code.

.DESCRIPTION
    Connects to the Tang Nano 20K onboard USB-UART bridge (BL616 / FTDI) at 115200 baud (or custom).
    Auto-detects the FPGA COM port if not specified.
    Displays incoming text with live streaming, optional logging, and clean exit.

.PARAMETER Port
    The COM port (e.g. "COM17"). If omitted, the script auto-detects connected USB serial devices.

.PARAMETER BaudRate
    Baud rate (default: 115200).

.PARAMETER List
    List all available COM ports and exit.

.PARAMETER LogFile
    Optional file path to log all received serial data.

.EXAMPLE
    .\serial_monitor.ps1
    .\serial_monitor.ps1 -Port COM17
    .\serial_monitor.ps1 -Port COM17 -BaudRate 115200 -LogFile uart_output.log
    .\serial_monitor.ps1 -List
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
        $pnpDevices = Get-PnpDevice -Class Ports -ErrorAction SilentlyContinue | Where-Object { $_.Present -eq $true }
    } catch { }

    $allNames = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object -Unique

    foreach ($name in $allNames) {
        $desc = "Serial Port"
        $isUsb = $false
        $match = $pnpDevices | Where-Object { $_.FriendlyName -match "\($name\)" }
        if ($match) {
            $desc = $match.FriendlyName
            if ($match.InstanceId -match "USB|FTDI|VID_") {
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
    $available = Get-AvailablePorts
    if ($available.Count -eq 0) {
        Write-Host "No COM ports detected." -ForegroundColor Yellow
    } else {
        $available | Format-Table -AutoSize
    }
    exit 0
}

# 2. Auto-detect Port if not supplied
if (-not $Port) {
    Write-Host "Auto-detecting Tang Nano 20K USB-UART port..." -ForegroundColor Cyan
    $available = Get-AvailablePorts
    
    # Priority 1: USB Serial ports (excluding bluetooth)
    $usbPorts = $available | Where-Object { $_.IsUsb -and $_.Description -notmatch "Bluetooth" }
    
    if ($usbPorts.Count -eq 1) {
        $Port = $usbPorts[0].Port
        Write-Host "[OK] Detected $($usbPorts[0].Description)" -ForegroundColor Green
    } elseif ($usbPorts.Count -gt 1) {
        Write-Host "Multiple USB serial devices found:" -ForegroundColor Yellow
        $usbPorts | Format-Table -AutoSize
        # Pick FTDI or highest COM port
        $ftdi = $usbPorts | Where-Object { $_.Description -match "FTDI|USB Serial Port" } | Select-Object -Last 1
        if ($ftdi) {
            $Port = $ftdi.Port
            Write-Host "Selecting likely FPGA port: $Port ($($ftdi.Description))" -ForegroundColor Cyan
        } else {
            $Port = $usbPorts[0].Port
            Write-Host "Selecting first USB port: $Port" -ForegroundColor Cyan
        }
    } else {
        # Fallback to any non-bluetooth port
        $nonBt = $available | Where-Object { $_.Description -notmatch "Bluetooth" -and $_.Port -ne "COM3" }
        if ($nonBt.Count -gt 0) {
            $Port = $nonBt[0].Port
            Write-Host "Selected port: $Port ($($nonBt[0].Description))" -ForegroundColor Yellow
        } else {
            Write-Host "[ERROR] No suitable serial ports found. Please connect your Tang Nano 20K." -ForegroundColor Red
            exit 1
        }
    }
}

# Ensure Port name has "COM" prefix
if ($Port -match "^\d+$") {
    $Port = "COM$Port"
}

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host "  VS Code Serial Monitor: TinyQV RV2A03 (Tang Nano 20K)" -ForegroundColor White
Write-Host "  Port      : $Port" -ForegroundColor Yellow
Write-Host "  Baud Rate : $BaudRate 8N1" -ForegroundColor Yellow
if ($LogFile) {
    Write-Host "  Logging to: $LogFile" -ForegroundColor Yellow
}
Write-Host "  Exit      : Press Ctrl+C to disconnect" -ForegroundColor Gray
Write-Host "============================================================`n" -ForegroundColor Green

# 3. Open Serial Port
$serial = [System.IO.Ports.SerialPort]::new($Port, $BaudRate, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$serial.ReadTimeout = 500
$serial.WriteTimeout = 500
$serial.Encoding = [System.Text.Encoding]::UTF8
$serial.DtrEnable = $true
$serial.RtsEnable = $true

try {
    $serial.Open()
} catch {
    Write-Host "[ERROR] Failed to open $Port : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Make sure no other program (Gowin GUI, PuTTY, Arduino IDE) is using $Port." -ForegroundColor Yellow
    exit 1
}

Write-Host "Connected to $Port @ $BaudRate baud. Waiting for data (press S1 on board to reset SoC)...`n" -ForegroundColor DarkGray

# 4. Stream Loop
$buffer = New-Object byte[] 4096
$logWriter = $null
if ($LogFile) {
    $logWriter = [System.IO.StreamWriter]::new($LogFile, $true, [System.Text.Encoding]::UTF8)
}

try {
    while ($serial.IsOpen) {
        try {
            $bytesToRead = $serial.BytesToRead
            if ($bytesToRead -gt 0) {
                $count = [Math]::Min($bytesToRead, $buffer.Length)
                $read = $serial.Read($buffer, 0, $count)
                if ($read -gt 0) {
                    $text = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $read)
                    [Console]::Write($text)
                    if ($logWriter) {
                        $logWriter.Write($text)
                        $logWriter.Flush()
                    }
                }
            } else {
                Start-Sleep -Milliseconds 10
            }
        } catch [System.TimeoutException] {
            # Normal timeout when idle
        }
    }
} finally {
    if ($logWriter) {
        $logWriter.Close()
        $logWriter.Dispose()
    }
    if ($serial.IsOpen) {
        $serial.Close()
    }
    $serial.Dispose()
    Write-Host "`n`n[DISCONNECTED] Closed $Port." -ForegroundColor Yellow
}
