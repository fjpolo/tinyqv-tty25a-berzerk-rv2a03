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

$ScriptPath = Join-Path $PSScriptRoot "FPGA\GOWIN\nano20k\build.ps1"
& $ScriptPath @PSBoundParameters
