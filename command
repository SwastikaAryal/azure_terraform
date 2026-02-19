# Create the destination folder first
New-Item -ItemType Directory -Path "C:\GrafanaAgent" -Force

# Set the download URL explicitly
$downloadUrl = "https://github.com/grafana/alloy/releases/latest/download/alloy-installer-windows-amd64.exe"

# Fix TLS and download
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $downloadUrl -OutFile "C:\GrafanaAgent\grafana-agent.zip" -Verbose
