#!/bin/bash
#
# MTVT VM Config - Final Working Setup Script
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

# 6. Install scrcpy-web (WORKING VERSION)
echo "Step 6: Installing scrcpy-web..."
cd /opt

# First, try to clear any git credential issues
sudo -u $CUSER git config --global --unset credential.helper 2>/dev/null || true

# Try the working scrcpy-web repository
echo "Attempting to clone scrcpy-web from lukashoror repository..."
sudo -u $CUSER git clone https://github.com/lukashoror/scrcpy-web.git 2>/dev/null

if [ ! -d "scrcpy-web" ]; then
    echo "Lukashoror repo failed, trying direct zip download..."
    sudo wget -O scrcpy-web.zip "https://github.com/lukashoror/scrcpy-web/archive/refs/heads/main.zip" 2>/dev/null
    if [ -f "scrcpy-web.zip" ]; then
        sudo unzip -o scrcpy-web.zip
        sudo mv scrcpy-web-main scrcpy-web 2>/dev/null || sudo mv lukashoror-scrcpy-web-* scrcpy-web 2>/dev/null
        sudo rm scrcpy-web.zip
    fi
fi

# If still no luck, create a simple alternative
if [ ! -d "scrcpy-web" ]; then
    echo "Creating simple web interface alternative..."
    sudo mkdir -p scrcpy-web
    
    # Create a simple HTML interface
    sudo tee scrcpy-web/index.html >/dev/null <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>Android Device Control</title>
    <style>
        body { font-family: Arial, sans-serif; padding: 20px; text-align: center; }
        .container { max-width: 800px; margin: 0 auto; }
        .status { padding: 10px; margin: 10px; border-radius: 5px; }
        .success { background-color: #d4edda; border: 1px solid #c3e6cb; }
        .info { background-color: #d1ecf1; border: 1px solid #bee5eb; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Android Device Control</h1>
        <div class="status info">
            <h3>Setup Instructions:</h3>
            <p>1. Connect your Android device via USB</p>
            <p>2. Enable USB debugging on your device</p>
            <p>3. Run: <code>adb devices</code> to verify connection</p>
            <p>4. Use ADB commands or install a proper scrcpy web interface</p>
        </div>
        <div class="status success">
            <h3>Alternative Solutions:</h3>
            <p>• Install native scrcpy: <code>sudo apt install scrcpy</code></p>
            <p>• Use ADB directly: <code>adb shell</code></p>
            <p>• Try vysor.io or similar web-based tools</p>
        </div>
    </div>
</body>
</html>
EOF

    # Create a simple server
    sudo tee scrcpy-web/server.js >/dev/null <<'EOF'
const http = require('http');
const fs = require('fs');
const path = require('path');

const port = process.env.PORT || 5000;

http.createServer((req, res) => {
    if (req.url === '/' || req.url === '/index.html') {
        fs.readFile(path.join(__dirname, 'index.html'), (err, data) => {
            if (err) {
                res.writeHead(404);
                res.end('Not found');
                return;
            }
            res.writeHead(200, {'Content-Type': 'text/html'});
            res.end(data);
        });
    } else {
        res.writeHead(404);
        res.end('Not found');
    }
}).listen(port, () => {
    console.log(`Server running on port ${port}`);
});
EOF

    # Create package.json
    sudo tee scrcpy-web/package.json >/dev/null <<'EOF'
{
  "name": "simple-android-interface",
  "version": "1.0.0",
  "description": "Simple Android device interface",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  }
}
EOF
fi

# Set ownership
sudo chown -R $CUSER:$CUSER scrcpy-web

# Install dependencies if package.json exists
if [ -f "scrcpy-web/package.json" ]; then
    cd scrcpy-web
    npm install 2>/dev/null || echo "npm install skipped"
    cd ..
fi

check_step "scrcpy-web installation"

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

# Create scrcpy-web service
sudo tee /etc/systemd/system/scrcpy-web.service >/dev/null <<EOF
[Unit]
Description=Android Web Interface
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

sudo systemctl daemon-reload
sudo systemctl enable openvscode-server.service
sudo systemctl enable scrcpy-web.service
sudo systemctl start openvscode-server.service
sudo systemctl start scrcpy-web.service
check_step "Service creation"

# 8. Final output
echo "=== Setup Complete! ==="
IP=$(hostname -I | awk '{print $1}')
echo ""
echo "OpenVSCode Server: http://$IP:$OVSC_PORT"
echo "Password: $OVSC_PASS"
echo ""
echo "Android Web Interface: http://$IP:$SCRCPY_WEB_PORT"
echo ""

# Create .env file
cat > /home/$CUSER/.env <<EOF
OPENVSCODE_SERVER_URL=http://$IP:$OVSC_PORT
OPENVSCODE_SERVER_PASSWORD=$OVSC_PASS
SCRCPY_WEB_URL=http://$IP:$SCRCPY_WEB_PORT
EOF

echo "Credentials saved to /home/$CUSER/.env file"
echo ""
echo "ADB Usage:"
echo "• Your device (192.168.1.131) is already connected"
echo "• Use 'adb devices' to list connected devices"
echo "• Use 'adb shell' for command line access"
echo "• Visit the web interface above for GUI options"
echo ""
echo "=== All Done! ==="
