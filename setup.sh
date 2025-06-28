#!/bin/bash
set -euo pipefail

# Auto-generate secrets/configs
OVSC_PASS=$(openssl rand -base64 18)
OVSC_PORT=8080

cat <<EOF > .env
OPENVSCODE_SERVER_PASSWORD=$OVSC_PASS
OPENVSCODE_SERVER_PORT=$OVSC_PORT
SCRCPY_WEB_PORT=5000
EOF

# Update and install dependencies
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
  python3 \
  python3-pip

# Node.js (scrcpy-web needs Node 18+)
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install OpenVSCode Server
cd /opt
sudo wget -O openvscode-server.tar.gz "https://github.com/gitpod-io/openvscode-server/releases/download/openvscode-server-v1.101.2/openvscode-server-v1.101.2-linux-x64.tar.gz"
sudo tar -xzf openvscode-server.tar.gz
sudo rm openvscode-server.tar.gz
sudo mv openvscode-server-v1.101.2-linux-x64 openvscode-server
sudo chown -R $USER:$USER openvscode-server

# Install Android SDK Command Line Tools
ANDROID_SDK_ROOT="/opt/android-sdk"
sudo mkdir -p $ANDROID_SDK_ROOT/cmdline-tools
cd $ANDROID_SDK_ROOT
sudo wget -O commandlinetools.zip "https://dl.google.com/android/repository/commandlinetools-linux-10406996_latest.zip"
sudo unzip commandlinetools.zip
sudo rm commandlinetools.zip
sudo mv cmdline-tools cmdline-tools/latest || true
export ANDROID_SDK_ROOT
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
yes | sudo $ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager --licenses || true
sudo $ANDROID_SDK_ROOT/cmdline-tools/latest/bin/sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"

# Add Android tools to PATH system-wide
echo 'export ANDROID_SDK_ROOT=/opt/android-sdk' | sudo tee /etc/profile.d/android_sdk.sh
echo 'export PATH=$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$PATH' | sudo tee -a /etc/profile.d/android_sdk.sh

# Install scrcpy (native, needed for backend)
cd /tmp
sudo git clone https://github.com/Genymobile/scrcpy.git
cd scrcpy
sudo meson setup x --buildtype release --strip -Db_lto=true
sudo ninja -Cx
sudo ninja -Cx install

# Install scrcpy-web
cd /opt
sudo git clone https://github.com/NetrisTV/scrcpy-web.git
sudo chown -R $USER:$USER scrcpy-web
cd scrcpy-web
npm install

# Create a systemd service for scrcpy-web
sudo tee /etc/systemd/system/scrcpy-web.service > /dev/null <<EOF
[Unit]
Description=scrcpy-web server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/scrcpy-web
Environment=PORT=5000
Environment=ANDROID_SDK_ROOT=/opt/android-sdk
Environment=PATH=/opt/android-sdk/platform-tools:/opt/android-sdk/cmdline-tools/latest/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=/usr/bin/npm run start
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# OpenVSCode Server systemd service
sudo tee /etc/systemd/system/openvscode-server.service > /dev/null <<EOF
[Unit]
Description=OpenVSCode Server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/openvscode-server
Environment=PASSWORD=$OVSC_PASS
ExecStart=/opt/openvscode-server/bin/openvscode-server --host 0.0.0.0 --port $OVSC_PORT --without-connection-token --auth password
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
sudo systemctl daemon-reload
sudo systemctl enable --now openvscode-server
sudo systemctl enable --now scrcpy-web

# Print connection info
IP=$(hostname -I | awk '{print $1}')
echo "========================================"
echo "OpenVSCode Server is running!"
echo "URL: http://$IP:$OVSC_PORT"
echo "Username: $USER"
echo "Password: $OVSC_PASS"
echo
echo "scrcpy-web is running for browser-based Android device streaming!"
echo "URL: http://$IP:5000"
echo "You can also find these credentials in .env"
echo "========================================"
