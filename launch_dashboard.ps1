<#
.SYNOPSIS
    Launcher for the TinyQV RV2A03 NES APU Web Serial Dashboard.
.DESCRIPTION
    Starts a local HTTP server at http://localhost:8080 and opens the dashboard in the default browser.
#>

[CmdletBinding()]
param(
    [int]$Port = 8080
)

$ErrorActionPreference = "Stop"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  TinyQV RV2A03 NES APU Web Serial Dashboard Launcher" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan

$url = "http://localhost:$Port/web/"

# Check if Python is installed
$hasPython = (Get-Command python -ErrorAction SilentlyContinue) -ne $null

if ($hasPython) {
    Write-Host "`n[OK] Found Python. Starting HTTP server on port $Port..." -ForegroundColor Green
    Write-Host "[URL] Opening $url in your default browser..." -ForegroundColor Yellow
    Write-Host "[TIP] Press Ctrl+C to stop the dashboard server.`n" -ForegroundColor Gray

    Start-Process $url
    python -m http.server $Port
} else {
    Write-Host "`n[INFO] Python not found. Starting native PowerShell HTTP listener on port $Port..." -ForegroundColor Yellow
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://localhost:$Port/")
    $listener.Start()

    Write-Host "[OK] Server listening at http://localhost:$Port/" -ForegroundColor Green
    Write-Host "[URL] Opening $url in your default browser..." -ForegroundColor Yellow
    Write-Host "[TIP] Press Ctrl+C to stop.`n" -ForegroundColor Gray

    Start-Process $url

    $baseDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

    try {
        while ($listener.IsListening) {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response

            $relPath = $request.Url.LocalPath.TrimStart('/')
            if ([string]::IsNullOrWhiteSpace($relPath)) { $relPath = "web/index.html" }
            if ($relPath -eq "web") { $relPath = "web/index.html" }
            if ($relPath -eq "web/") { $relPath = "web/index.html" }

            $filePath = Join-Path $baseDir $relPath

            if (Test-Path $filePath -PathType Leaf) {
                $bytes = [System.IO.File]::ReadAllBytes($filePath)
                $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
                switch ($ext) {
                    ".html" { $response.ContentType = "text/html" }
                    ".css"  { $response.ContentType = "text/css" }
                    ".js"   { $response.ContentType = "application/javascript" }
                    ".json" { $response.ContentType = "application/json" }
                    ".svg"  { $response.ContentType = "image/svg+xml" }
                    default { $response.ContentType = "application/octet-stream" }
                }
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $response.StatusCode = 404
                $errBytes = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found")
                $response.OutputStream.Write($errBytes, 0, $errBytes.Length)
            }
            $response.OutputStream.Close()
        }
    } finally {
        $listener.Stop()
        $listener.Close()
    }
}
