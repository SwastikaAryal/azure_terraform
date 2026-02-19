Write-Host "======================================="
Write-Host " Installing Grafana Agent on Windows VM"
Write-Host "======================================="

# Variables
$version = "0.41.0"
$downloadUrl = "https://github.com/grafana/agent/releases/download/v$version/grafana-agent-windows-amd64.zip"
$installDir = "C:\GrafanaAgent"

# Step 1: Create install directory
Write-Host "Step 1: Creating install directory..."
New-Item -ItemType Directory -Force -Path $installDir

# Step 2: Download Grafana Agent zip
Write-Host "Step 2: Downloading Grafana Agent..."
Invoke-WebRequest -Uri $downloadUrl -OutFile "$installDir\grafana-agent.zip"

# Step 3: Extract zip
Write-Host "Step 3: Extracting..."
Expand-Archive -Path "$installDir\grafana-agent.zip" -DestinationPath $installDir -Force

# Step 4: Create config file
Write-Host "Step 4: Creating config file..."

$config = @"
server:
  log_level: info

metrics:
  global:
    scrape_interval: 15s

  configs:
    - name: default
      scrape_configs:
        - job_name: windows
          static_configs:
            - targets: ["localhost:12345"]
"@

$config | Out-File -Encoding utf8 "$installDir\agent.yaml"

# Step 5: Run Grafana Agent
Write-Host "Step 5: Starting Grafana Agent..."
Start-Process -NoNewWindow -FilePath "$installDir\grafana-agent.exe" `
  -ArgumentList "--config.file=$installDir\agent.yaml"

Write-Host "======================================="
Write-Host " Grafana Agent Started Successfully!"
Write-Host "======================================="
