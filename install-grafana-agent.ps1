[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$downloadUrl = "https://github.com/grafana/alloy/releases/latest/download/grafana-alloy-installer.exe"
$installerPath = "$env:TEMP\grafana-alloy-installer.exe"

Write-Host "Downloading Grafana Alloy..."
Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

Start-Process -FilePath $installerPath -ArgumentList "/S" -Wait
Write-Host "Grafana Alloy installed successfully!"

[Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}; .\install-grafana-agent.ps1
