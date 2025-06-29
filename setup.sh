#!/bin/bash
#
# MTVT VM Config - Final Fixed Setup Script
# Author: KdogDevs
# Date: 2025-06-29
#

# Turn off strict error checking
set +e

# Configuration
OVSC_PASS=$(openssl rand -base64 18)
OVSC_PORT=8080
SCRCPY_WEB_PORT=5000
ANDROID_SDK_ROOT="/opt/android-sdk"
CUSER=$(whoami)

echo "=== MTVT VM Setup Starting ==="

# Function to check if command succeeded
check_step() {
    if [ $? -eq 0 ]; then
        echo "✓ $1 completed successfully"
    else
        echo "✗ $1 failed, but continuing..."
    fi
}

# 1. Cleanup
echo "Step 1: Cleaning up..."
sudo systemctl stop openvscode-server.service 2>/dev/null
sudo systemctl stop scrcpy-web.service 2>/dev/null
sudo rm -rf /opt/openvscode-server /opt/scrcpy-web "$ANDROID_SDK_ROOT"
sudo rm -f /etc/systemd/system/openvscode-server.service
sudo rm -f /etc/systemd/system/scrcpy-web.service
sudo systemctl daemon-reload 2>/dev/null
check_step "Cleanup"

# 2. Install basic packages
echo "Step 2: Installing packages..."
sudo apt-get update
sudo apt-get install -y wget curl unzip tar git openjdk-17-jdk adb
check_step "Package installation"

# 3. Install Node.js
echo "Step 3: Installing Node.js..."
if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi
check_step "Node.js installation"

# 4. Install OpenVSCode Server
echo "Step 4: Installing OpenVSCode Server..."
cd /opt
sudo wget -O openvscode-server.tar.gz "https://github.com/gitpod-io/openvscode-server/releases/download/openvscode-server-v1.101.2/openvscode-server-v1.101.2-linux-x64.tar.gz"
sudo tar -xzf openvscode-server.tar.gz
sudo rm openvscode-server.tar.gz
sudo mv openvscode-server-v1.101.2-linux-x64 openvscode-server
sudo chown -R $CUSER:$CUSER openvscode-server
check_step "OpenVSCode Server installation"

# 5. Install Android SDK
echo "Step 5: Installing Android SDK..."
sudo mkdir -p "$ANDROID_SDK_ROOT"
cd "$ANDROID_SDK_ROOT"
sudo wget -O commandlinetools.zip "https://dl.google.com/android/repository/commandlinetools-linux-10406996_latest.zip"
sudo unzip -o commandlinetools.zip -d temp
sudo mkdir -p cmdline-tools
sudo mv temp/cmdline-tools cmdline-tools/latest
sudo rm -rf temp commandlinetools.zip
sudo chmod +x "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager"

# Set up environment
echo "export ANDROID_HOME=$ANDROID_SDK_ROOT" | sudo tee /etc/profile.d/android_sdk.sh
echo "export PATH=\$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools" | sudo tee -a /etc/profile.d/android_sdk.sh

JAVA_HOME_PATH=$(dirname $(dirname $(readlink -f $(which java))))

if [ -f "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" ]; then
    echo "Step 5a: Please accept Android SDK licenses when prompted..."
    sudo env JAVA_HOME="$JAVA_HOME_PATH" PATH="$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin" "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" --licenses

    echo "Step 5b: Installing Android components..."
    sudo env JAVA_HOME="$JAVA_HOME_PATH" PATH="$PATH:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin" "$ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager" "platform-tools" "platforms;android-34" "build-tools;34.0.0"
fi
check_step "Android SDK installation"

# 6. Install scrcpy-web (FIXED - use wget instead of git)
echo "Step 6: Installing scrcpy-web..."
cd /opt
# Download the latest release directly instead of cloning
sudo wget -O scrcpy-web.zip "https://github.com/NetrisTV/scrcpy-web/archive/refs/heads/main.zip"
sudo unzip -o scrcpy-web.zip
sudo mv scrcpy-web-main scrcpy-web
sudo rm scrcpy-web.zip
sudo chown -R $CUSER:$CUSER scrcpy-web

if [ -d "scrcpy-web" ]; then
    cd scrcpy-web
    npm install
    check_step "scrcpy-web installation"
else
    echo "✗ scrcpy-web installation failed"
fi

# 7. Create services
echo "Step 7: Creating services..."
sudo tee /etc/systemd/system/openvscode-server.service >/dev/null <<EOF
[Unit]
Description=OpenVSCode Server
After=network.target

[Service]
Type=simple
User=$CUSER
WorkingDirectory=/opt/openvscode-server
Environment=PASSWORD=$OVSC_PASS
ExecStart=/opt/openvscode-server/bin/openvscode-server --host 0.0.0.0 --port $OVSC_PORT --without-connection-token --auth password
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Make sure scrcpy-web service only starts if directory exists
if [ -d "/opt/scrcpy-web" ]; then
sudo tee /etc/systemd/system/scrcpy-web.service >/dev/null <<EOF
[Unit]
Description=scrcpy-web
After=network.target

[Service]
Type=simple
User=$CUSER
WorkingDirectory=/opt/scrcpy-web
Environment=PORT=$SCRCPY_WEB_PORT
Environment=PATH=/usr/bin:/usr/local/bin:$ANDROID_SDK_ROOT/platform-tools
ExecStart=/usr/bin/node server.js
Restart=always

[Install]
WantedBy=multi-user.target
EOF
fi

sudo systemctl daemon-reload
sudo systemctl enable openvscode-server.service
if [ -d "/opt/scrcpy-web" ]; then
    sudo systemctl enable scrcpy-web.service
    sudo systemctl start scrcpy-web.service
fi
sudo systemctl start openvscode-server.service
check_step "Service creation"

# 8. Final output
echo "=== Setup Complete! ==="
IP=$(hostname -I | awk '{print $1}')
echo ""
echo "OpenVSCode Server: http://$IP:$OVSC_PORT"
echo "Password: $OVSC_PASS"
echo ""

if [ -d "/opt/scrcpy-web" ]; then
    echo "scrcpy-web: http://$IP:$SCRCPY_WEB_PORT"
    echo "(No login required)"
else
    echo "scrcpy-web: Installation failed - service not available"
fi

echo ""

# Create .env file in user's home directory
cat > /home/$CUSER/.env <<EOF
OPENVSCODE_SERVER_URL=http://$IP:$OVSC_PORT
OPENVSCODE_SERVER_PASSWORD=$OVSC_PASS
SCRCPY_WEB_URL=http://$IP:$SCRCPY_WEB_PORT
EOF

echo "Credentials saved to /home/$CUSER/.env file"
echo ""
echo "ADB Usage:"
echo "For USB devices: Connect via USB, enable USB debugging, then the web interface will detect it"
echo "For WiFi devices: Use 'adb connect DEVICE_IP:5555' first, then use the web interface"
echo ""
echo "Your ADB connection to 192.168.1.131 is already established!"
echo "Now visit http://$IP:$SCRCPY_WEB_PORT to control your device in the browser."
echo ""
echo "=== All Done! ==="
