# PowerShell Script to Package Windows Portable Release Archive
# Usage: powershell -ExecutionPolicy Bypass -File .\tool\package_windows_zip.ps1 [-Version "1.1.0"]

param(
    [string]$Version = "1.1.0"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$BuildOutput = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
$DistDir = Join-Path $ProjectRoot "dist"
$ZipName = "signal-chain-windows-x64-$Version.zip"
$ZipPath = Join-Path $DistDir $ZipName

Write-Host "=== Packaging Signal Chain for Windows (x64) - Version: $Version ==="

if (-not (Test-Path $BuildOutput)) {
    Write-Host "Release build not found at $BuildOutput."
    Write-Host "Building release bundle with flutter build windows --release..."
    Push-Location $ProjectRoot
    try {
        flutter build windows --release
    } finally {
        Pop-Location
    }
}

if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir | Out-Null
}

if (Test-Path $ZipPath) {
    Remove-Item -Force $ZipPath
}

Write-Host "Creating portable ZIP archive from $BuildOutput..."
Compress-Archive -Path "$BuildOutput\*" -DestinationPath $ZipPath

Write-Host "=== Successfully created Windows portable release: $ZipPath ==="

