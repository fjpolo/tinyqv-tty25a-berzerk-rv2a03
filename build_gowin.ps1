[CmdletBinding()]
param (
    [ValidateSet("nano20k", "console60k")]
    [string]$Board = "nano20k",

    [ValidateSet("all", "syn", "pnr")]
    [string]$Target = "all",

    [switch]$Clean,

    [ValidateSet("sram", "flash", "")]
    [string]$Flash = "",

    [switch]$Scan,

    [string]$GowinPath = "",

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$BoardDir = if ($Board -eq "console60k") { "FPGA\GOWIN\console60k" } else { "FPGA\GOWIN\nano20k" }
$ScriptPath = Join-Path $PSScriptRoot "$BoardDir\build.ps1"

$ForwardParams = @{}
foreach ($k in $PSBoundParameters.Keys) {
    if ($k -ne "Board") {
        $ForwardParams[$k] = $PSBoundParameters[$k]
    }
}
& $ScriptPath @ForwardParams @RemainingArgs

