Write-Host "======================================="
Write-Host " Installing Grafana Alloy (Windows VM)"
Write-Host "======================================="

$ErrorActionPreference = "Stop"

# Variables
$downloadUrl = "https://github.com/grafana/alloy/releases/latest/download/grafana-alloy-installer.exe"
$installerPath = "$env:TEMP\grafana-alloy-installer.exe"

# Step 1: Download installer
Write-Host "Step 1: Downloading Grafana Alloy..."
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

if (!(Test-Path $installerPath)) {
    Write-Host "ERROR: Download failed!"
    exit 1
}

# Step 2: Run installer silently
Write-Host "Step 2: Installing Alloy..."
Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait

# Step 3: Verify service
Write-Host "Step 3: Verifying Grafana Alloy service..."
Get-Service grafana-alloy

Write-Host "======================================="
Write-Host " Grafana Alloy installation completed!"
Write-Host "======================================="
