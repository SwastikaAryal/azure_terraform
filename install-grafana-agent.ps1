Write-Host "Installing Grafana Agent..."

$ErrorActionPreference = "Stop"

$tempDir = "$env:TEMP\GrafanaAgent"
$zipName = "grafana-agent-flow-installer.exe.zip"
$zipPath = "$tempDir\$zipName"
$extractDir = "$tempDir\extract"
$downloadUrl = "https://github.com/grafana/agent/releases/latest/download/$zipName"

# Create folders
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
New-Item -ItemType Directory -Force -Path $extractDir | Out-Null

# Download
Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath

if (!(Test-Path $zipPath)) {
    Write-Host "Download failed!"
    exit 1
}

# Extract
Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force

# Find installer
$installer = Get-ChildItem -Path $extractDir -Filter "*.exe" | Select-Object -First 1

if (!$installer) {
    Write-Host "Installer not found!"
    exit 1
}

# Install silently
Start-Process -FilePath $installer.FullName -ArgumentList "/S" -Wait

Write-Host "Grafana Agent Installed Successfully!"
