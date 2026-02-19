#!/bin/bash
set -e

echo "Installing Grafana Agent..."

sudo apt update -y
sudo apt install -y unzip wget prometheus-node-exporter

# Download agent
wget https://github.com/grafana/agent/releases/download/v0.41.0/grafana-agent-linux-amd64.zip

unzip grafana-agent-linux-amd64.zip
sudo mv grafana-agent-linux-amd64 /usr/local/bin/grafana-agent
sudo chmod +x /usr/local/bin/grafana-agent

# Config
sudo mkdir -p /etc/grafana-agent

cat <<EOF | sudo tee /etc/grafana-agent/agent.yaml
server:
  log_level: info

metrics:
  global:
    scrape_interval: 15s

  configs:
    - name: default
      scrape_configs:
        - job_name: azure-vm
          static_configs:
            - targets: ["localhost:9100"]
EOF

# Service
cat <<EOF | sudo tee /etc/systemd/system/grafana-agent.service
[Unit]
Description=Grafana Agent
After=network.target

[Service]
ExecStart=/usr/local/bin/grafana-agent --config.file=/etc/grafana-agent/agent.yaml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable grafana-agent
sudo systemctl start grafana-agent

echo "Grafana Agent Installed Successfully!"
