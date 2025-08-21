#!/bin/bash

# Script to manage Zabbix Agent installation with dialog menu

# ===== CONFIGURATION =====
ZABBIX_SERVER_IP="192.168.2.245"  # Change this IP to your Zabbix server
CONFIG_FILE="/etc/zabbix/zabbix_agentd.conf"
BACKUP_DIR="/tmp/zabbix_backup"
NEW_CONFIG="/tmp/zabbix_agentd.conf"
ZABBIX_TARBALL="/tmp/zabbix_agent-7.0.10-linux-3.0-amd64-static.tar.gz"
INSTALL_DIR="/usr/sbin"
LOG_DIR="/var/log/zabbix"
RUN_DIR="/var/run/zabbix"

# Ensure dialog is installed
if ! command -v dialog >/dev/null 2>&1; then
  echo "Installing 'dialog' package..."
  if command -v apt >/dev/null 2>&1; then
    sudo apt update && sudo apt install -y dialog
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y dialog
  fi
fi

HEIGHT=16
WIDTH=70
CHOICE_HEIGHT=7
TITLE="Zabbix Agent Installer"
MENU="Choose an option:"

OPTIONS=(1 "Check if Zabbix Agent is installed"
         2 "Backup current configuration"
         3 "Remove existing Zabbix Agent"
         4 "Install Zabbix Agent 7.0.10"
         5 "Deploy new configuration"
         6 "Check if Zabbix Agent service is running"
         7 "Exit")

while true; do
  CHOICE=$(dialog --clear \
                  --backtitle "Zabbix Agent Setup" \
                  --title "$TITLE" \
                  --menu "$MENU" \
                  $HEIGHT $WIDTH $CHOICE_HEIGHT \
                  "${OPTIONS[@]}" \
                  2>&1 >/dev/tty)

  clear
  case $CHOICE in
    1)
      # Check if Zabbix Agent is installed
      if command -v zabbix_agentd >/dev/null 2>&1; then
        echo "✅ Zabbix Agent is installed."
      else
        echo "❌ Zabbix Agent is NOT installed."
      fi
      ;;
    2)
      # Backup configuration
      echo "Backing up configuration..."
      sudo mkdir -p $BACKUP_DIR
      if [ -f "$CONFIG_FILE" ]; then
        sudo cp "$CONFIG_FILE" "$BACKUP_DIR/zabbix_agentd.conf.$(date +%F_%T)"
        echo "✅ Backup saved in $BACKUP_DIR"
      else
        echo "⚠️ No configuration file found."
      fi
      ;;
    3)
      # Remove existing Zabbix Agent and service
      echo "Removing existing Zabbix Agent..."
      if systemctl list-unit-files | grep -q zabbix-agent.service; then
        sudo systemctl stop zabbix-agent
        sudo systemctl disable zabbix-agent
        sudo systemctl reset-failed zabbix-agent
      fi
      sudo rm -f /etc/systemd/system/zabbix-agent.service
      sudo systemctl daemon-reload
      sudo rm -f /usr/sbin/zabbix_agentd
      sudo rm -rf /etc/zabbix
      sudo rm -rf $LOG_DIR
      sudo rm -rf $RUN_DIR
      echo "✅ Removed old installation and service."
      ;;
    4)
      # Install Zabbix Agent binary
      echo "Installing Zabbix Agent 7.0.10..."
      if [ ! -f "$ZABBIX_TARBALL" ]; then
        echo "❌ File $ZABBIX_TARBALL not found. Please upload it first."
        exit 1
      fi
      cd /tmp
      tar -xzf "$ZABBIX_TARBALL"
      DIRNAME=$(tar -tzf "$ZABBIX_TARBALL" | head -1 | cut -f1 -d"/")
      sudo cp "$DIRNAME/sbin/zabbix_agentd" $INSTALL_DIR/
      sudo useradd -r -s /sbin/nologin zabbix 2>/dev/null
      echo "✅ Installed Zabbix Agent binary."
      ;;
    5)
      # Deploy configuration and create all required directories
      echo "Deploying new configuration..."
      HOSTNAME=$(hostname)

      sudo mkdir -p /etc/zabbix
      sudo mkdir -p /etc/zabbix/zabbix_agent.d
      sudo mkdir -p $LOG_DIR
      sudo mkdir -p $RUN_DIR

      # Ensure ownership for zabbix user
      sudo chown -R zabbix:zabbix /etc/zabbix
      sudo chown -R zabbix:zabbix $LOG_DIR
      sudo chown -R zabbix:zabbix $RUN_DIR

      # Remove old PID/log files to prevent start-limit-hit
      sudo rm -f $LOG_DIR/zabbix_agentd.log
      sudo rm -f $RUN_DIR/zabbix_agentd.pid

      sudo touch $LOG_DIR/zabbix_agentd.log
      sudo touch $RUN_DIR/zabbix_agentd.pid
      sudo chown zabbix:zabbix $LOG_DIR/zabbix_agentd.log
      sudo chown zabbix:zabbix $RUN_DIR/zabbix_agentd.pid

      # Create configuration file
      cat <<EOF | sudo tee $NEW_CONFIG
LogFile=$LOG_DIR/zabbix_agentd.log
LogFileSize=0
Server=$ZABBIX_SERVER_IP
ServerActive=$ZABBIX_SERVER_IP
Hostname=$HOSTNAME
ListenPort=10050
ListenIP=0.0.0.0
Include=/etc/zabbix/zabbix_agent.d/*.conf
PidFile=$RUN_DIR/zabbix_agentd.pid
EOF

      sudo cp $NEW_CONFIG $CONFIG_FILE

      # Create systemd service if missing
      if [ ! -f /etc/systemd/system/zabbix-agent.service ]; then
        cat <<EOF | sudo tee /etc/systemd/system/zabbix-agent.service
[Unit]
Description=Zabbix Agent
After=network.target

[Service]
User=zabbix
Group=zabbix
ExecStart=/usr/sbin/zabbix_agentd -c /etc/zabbix/zabbix_agentd.conf
Restart=always
PIDFile=$RUN_DIR/zabbix_agentd.pid

[Install]
WantedBy=multi-user.target
EOF
      fi

      # Reload systemd and start service safely
      sudo systemctl daemon-reload
      sudo systemctl enable zabbix-agent
      sudo systemctl reset-failed zabbix-agent
      sudo systemctl start zabbix-agent
      sleep 3  # Wait a few seconds to prevent start-limit-hit
      echo "✅ New configuration applied and service started."
      ;;
    6)
      # Check if Zabbix Agent service is running
      echo "Checking Zabbix Agent service status..."
      if systemctl is-active --quiet zabbix-agent; then
        echo "✅ Zabbix Agent service is running."
        echo "Last 20 log lines:"
        sudo tail -n 20 $LOG_DIR/zabbix_agentd.log 2>/dev/null || echo "⚠️ Log file not found."
      else
        echo "❌ Zabbix Agent service is NOT running."
      fi
      ;;
    7)
      echo "Exiting..."
      break
      ;;
  esac
  read -p "Press Enter to continue..."
done
