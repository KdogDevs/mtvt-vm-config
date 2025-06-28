#!/bin/bash
#
# MTVT VM Config - One-Command Setup Script
# Installs: OpenVSCode Server, Android SDK, scrcpy, and scrcpy-web
# Author: KdogDevs & Copilot
# Date: 2025-06-28
#
set -euo pipefail

# --- Configuration ---
OVSC_PASS=$(openssl rand -base64 18)
OVSC_PORT=8080
SCRCPY_WEB_PORT=5000
ANDROID_SDK_ROOT="/opt/android-sdk"
CUSER=$(whoami) # Gets the user running the script

echo "--- Starting MTVT VM Setup for user: $CUSER ---"

# --- 1. Cleanup: Ensure a clean slate by removing previous installations ---
echo "[1/8] Cleaning up previous installations..."
sudo systemctl stop openvscode-server.service || true
sudo systemctl stop scrcpy-web.service || true
sudo rm -f /etc/systemd/system/openvscode-server.service
sudo rm -f /etc/systemd/system/scrcpy-web.service
sudo systemctl daemon-reload

sudo rm -rf /opt/openvscode-server
sudo rm -rf /opt/scrcpy
sudo rm -rf /opt/scrcpy-web
sudo rm -rf "$ANDROID_SDK_ROOT"

# --- 2. Install System Dependencies ---
echo "[2/8] Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y wget curl unzip tar git \
  openjdk-17-jdk \
  ffmpeg \
  usbutils \
  build-essential \
  pkg-config \
  meson \
  ninja-build \
  libavcodec-dev \
  libavdevice-dev \
  libavformat-dev \
  libavutil-dev \
  libusb-1.0-0-dev \
  libssl-dev \
  libwebsockets-dev \
  python3

# Install Node.js (required for scrcpy-web)
if ! command -v node > /dev/null; then
    echo "Node.js not found, installing..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
else
    echo "Node.js is already installed."
fi

# --- 3. Install OpenVSCode Server ---
echo "[3/8] Installing OpenVSCode Server..."
cd /opt
sudo wget -O openvscode-server.tar.gz "https://github.com/gitpod-io/openvscode-server/releases/download/openvscode-server-v1.101.2/openvscode-server-v1.101.2-linux-x64.tar.gz"
sudo tar -xzf openvscode-server.tar.gz
sudo rm openvscode-server.tar.gz
sudo mv openvscode-server-v1.101.2-linux-x64 openvscode-server
sudo chown -R $CUSER:$CUSER openvscode-server

# --- 4. Install Android SDK (Robust Method) ---
echo "[4/8] Installing Android SDK..."
sudo mkdir -p "$ANDROID_SDK_ROOT"
cd "$ANDROID_SDK_ROOT"
sudo wget -O commandlinetools.zip "https://dl.google.com/android/repository/commandlinetools-linux-10406996_latest.zip"
sudo unzip -o commandlinetools.zip -d "$ANDROID_SDK_ROOT/cmdline-tools-temp"
sudo rm commandlinetools.zip
sudo mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
sudo mv "$ANDROID_SDK_ROOT/cmdline-tools-temp/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
sudo rm -rf "$ANDROID_SDK_ROOT/cmdline-tools-temp"

# Set environment for system-wide access
echo "export ANDROID_HOME=$ANDROID_SDK_ROOT" | sudo tee /etc/profile.d/android_sdk.sh
echo 'export PATH=$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools' | sudo tee -a /etc/profile.d/android_sdk.sh
# Source the new profile script to make variables available now
source /etc/profile.d/android_sdk.sh

# Check for sdkmanager before proceeding
if [ ! -f "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]; then
    echo "FATAL: sdkmanager not found. Android SDK installation failed."
    exit 1
fi

# **FIX:** Define the environment explicitly for the sudo command
SDKMANAGER_CMD="env PATH=$PATH $ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

echo "Accepting Android SDK licenses..."
yes | sudo $SDKMANAGER_CMD --licenses > /dev/null
echo "Installing Android platform-tools, platforms, and build-tools..."
sudo $SDKMANAGER_CMD "platform-tools" "platforms;android-34" "build-tools;34.0.0" > /dev/null

# --- 5. Install scrcpy (from source) ---
echo "[5/8] Installing scrcpy (native backend)..."
cd /opt
sudo git clone https://github.com/Genymobile/scrcpy.git
cd scrcpy
sudo meson setup x --buildtype release --strip -Db_lto=true
sudo ninja -Cx
sudo ninja -Cx install

# --- 6. Install scrcpy-web (for browser streaming) ---
echo "[6/8] Installing scrcpy-web..."
cd /opt
sudo git clone https://github.com/NetrisTV/scrcpy-web.git
sudo chown -R $CUSER:$CUSER scrcpy-web
cd scrcpy-web
npm install

# --- 7. Create and Enable Systemd Services ---
echo "[7/8] Creating and enabling systemd services..."

# OpenVSCode Server Service
sudo tee /etc/systemd/system/openvscode-server.service > /dev/null <<EOF
[Unit]
Description=OpenVSCode Server
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=$CUSER
WorkingDirectory=/opt/openvscode-server
Environment="PASSWORD=$OVSC_PASS"
ExecStart=/opt/openvscode-server/bin/openvscode-server --host 0.0.0.0 --port $OVSC_PORT --without-connection-token --auth password
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# scrcpy-web Service
sudo tee /etc/systemd/system/scrcpy-web.service > /dev/null <<EOF
[Unit]
Description=scrcpy-web - Android in the Browser
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=$CUSER
WorkingDirectory=/opt/scrcpy-web
Environment="PORT=$SCRCPY_WEB_PORT"
Environment="PATH=/usr/bin:/usr/local/bin:$ANDROID_SDK_ROOT/platform-tools"
ExecStart=/usr/bin/npm run start
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now openvscode-server.service
sudo systemctl enable --now scrcpy-web.service

# --- 8. Final Output ---
echo "[8/8] Setup Complete!"
IP=$(hostname -I | awk '{print $1}')
echo "=================================================================="
echo "          MTVT Development Environment is Ready!"
echo "=================================================================="
echo
echo "  OpenVSCode Server (Browser-based IDE):"
echo "  URL:      http://$IP:$OVSC_PORT"
echo "  Password: $OVSC_PASS"
echo
echo "  scrcpy-web (Android Device in Browser):"
echo "  URL:      http://$IP:$SCRCPY_WEB_PORT"
echo
echo "  A file named '.env' has been created with these details."
echo "=================================================================="

# Create .env file with credentials
cat <<EOF > .env
# Auto-generated by mtvt-vm-config setup script
# Date: $(date)

# OpenVSCode Server Credentials
OPENVSCODE_SERVER_URL=http://$IP:$OVSC_PORT
OPENVSCODE_SERVER_PASSWORD=$OVSC_PASS

# scrcpy-web (Android Streaming)
SCRCPY_WEB_URL=http://$IP:$SCRCPY_WEB_PORT
EOF
