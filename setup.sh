#!/bin/bash
#
# MTVT VM Config - One-Command Setup Script (v7 - Better error handling)
# Installs: OpenVSCode Server, Android SDK, scrcpy, and scrcpy-web
# Author: KdogDevs & Copilot
# Date: 2025-06-29
#
set -euo pipefail

# --- Configuration ---
OVSC_PASS=$(openssl rand -base64 18)
OVSC_PORT=8080
SCRCPY_WEB_PORT=5000
ANDROID_SDK_ROOT="/opt/android-sdk"
CUSER=$(whoami)

echo "--- Starting MTVT VM Setup for user: $CUSER ---"

# --- 1. Cleanup: Ensure a clean slate ---
echo "[1/8] Cleaning up previous installations..."
sudo systemctl stop openvscode-server.service 2>/dev/null || true
sudo systemctl stop scrcpy-web.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/openvscode-server.service
sudo rm -f /etc/systemd/system/scrcpy-web.service
sudo systemctl daemon-reload
sudo rm -rf /opt/openvscode-server /opt/scrcpy /opt/scrcpy-web "$ANDROID_SDK_ROOT"

# --- 2. Install System Dependencies ---
echo "[2/8] Installing system dependencies..."
sudo apt-get update
sudo apt-get install -y wget curl unzip tar git openjdk-17-jdk ffmpeg usbutils build-essential pkg-config meson ninja-build libavcodec-dev libavdevice-dev libavformat-dev libavutil-dev libusb-1.0-0-dev libssl-dev libwebsockets-dev python3 cmake libsdl2-dev

# Install Node.js
if ! command -v node > /dev/null; then
    echo "Node.js not found, installing..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi

# --- 3. Install OpenVSCode Server ---
echo "[3/8] Installing OpenVSCode Server..."
cd /opt
sudo wget -q --show-progress -O openvscode-server.tar.gz "https://github.com/gitpod-io/openvscode-server/releases/download/openvscode-server-v1.101.2/openvscode-server-v1.101.2-linux-x64.tar.gz"
sudo tar -xzf openvscode-server.tar.gz
sudo rm openvscode-server.tar.gz
sudo mv openvscode-server-v1.101.2-linux-x64 openvscode-server
sudo chown -R $CUSER:$CUSER openvscode-server

# --- 4. Install Android SDK ---
echo "[4/8] Installing Android SDK..."
sudo mkdir -p "$ANDROID_SDK_ROOT"
cd "$ANDROID_SDK_ROOT"
sudo wget -q --show-progress -O commandlinetools.zip "https://dl.google.com/android/repository/commandlinetools-linux-10406996_latest.zip"
sudo unzip -q -o commandlinetools.zip -d "$ANDROID_SDK_ROOT/cmdline-tools-temp"
sudo rm commandlinetools.zip
sudo mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
sudo mv "$ANDROID_SDK_ROOT/cmdline-tools-temp/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
sudo rm -rf "$ANDROID_SDK_ROOT/cmdline-tools-temp"

# Find Java
JAVA_HOME_PATH=$(dirname $(dirname $(readlink -f $(which java))))
echo "JAVA_HOME detected at: $JAVA_HOME_PATH"

# Set execute permissions
sudo chmod +x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

# Create the system-wide environment file
sudo tee /etc/profile.d/android_sdk.sh > /dev/null <<EOF
export ANDROID_HOME=$ANDROID_SDK_ROOT
export PATH="\${PATH}:${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools"
EOF

# Temporarily disable exit on error for license acceptance
set +e
echo "Accepting Android SDK licenses..."
echo "Please respond to the license prompts that follow:"
sudo env JAVA_HOME="$JAVA_HOME_PATH" \
     PATH="$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin" \
     "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --licenses
LICENSE_RESULT=$?
set -e

if [ $LICENSE_RESULT -ne 0 ]; then
    echo "Warning: Not all licenses were accepted. Some SDK components may not install."
fi

echo "Installing Android platform-tools, platforms, and build-tools..."
sudo env JAVA_HOME="$JAVA_HOME_PATH" \
     PATH="$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin" \
     "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" \
     "platform-tools" "platforms;android-34" "build-tools;34.0.0"

# --- 5. Install scrcpy ---
echo "[5/8] Installing scrcpy (native backend)..."
cd /opt

# Download pre-built scrcpy server
echo "Downloading scrcpy server..."
SCRCPY_VERSION="v2.4"
sudo wget -q --show-progress -O scrcpy-server.jar "https://github.com/Genymobile/scrcpy/releases/download/${SCRCPY_VERSION}/scrcpy-server-${SCRCPY_VERSION}"
sudo mkdir -p /usr/local/share/scrcpy
sudo mv scrcpy-server.jar /usr/local/share/scrcpy/scrcpy-server

# Build scrcpy from source
echo "Building scrcpy from source..."
sudo git clone -q https://github.com/Genymobile/scrcpy.git
cd scrcpy
git checkout ${SCRCPY_VERSION}

# Show build output for debugging
echo "Running meson setup..."
sudo meson setup x --buildtype release --strip -Db_lto=true -Dprebuilt_server=/usr/local/share/scrcpy/scrcpy-server
echo "Building with ninja..."
sudo ninja -Cx
echo "Installing scrcpy..."
sudo ninja -Cx install

# --- 6. Install scrcpy-web ---
echo "[6/8] Installing scrcpy-web..."
cd /opt
sudo git clone -q https://github.com/NetrisTV/scrcpy-web.git
sudo chown -R $CUSER:$CUSER scrcpy-web
cd scrcpy-web
echo "Installing npm dependencies (this may take a few minutes)..."
npm install

# --- 7. Create and Enable Systemd Services ---
echo "[7/8] Creating and enabling systemd services..."
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

cat <<EOF > .env
OPENVSCODE_SERVER_URL=http://$IP:$OVSC_PORT
OPENVSCODE_SERVER_PASSWORD=$OVSC_PASS
SCRCPY_WEB_URL=http://$IP:$SCRCPY_WEB_PORT
EOF
