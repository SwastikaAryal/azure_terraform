Write-Host "Installing Grafana Alloy..."

$downloadUrl = "https://github.com/grafana/alloy/releases/latest/download/alloy-installer-windows-amd64.exe"
$installerPath = "$env:TEMP\alloy-installer.exe"

# Force TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Download installer
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath

# Silent install
Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait

Write-Host "Grafana Alloy installed successfully."
