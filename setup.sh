#!/bin/bash
set -euo pipefail

# Auto-generate secrets/configs
OVSC_PASS=$(openssl rand -base64 18)
OVSC_PORT=8080

# Save password in .env for user reference
cat <<EOF > .env
OPENVSCODE_SERVER_PASSWORD=$OVSC_PASS
OPENVSCODE_SERVER_PORT=$OVSC_PORT
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
  libwebsockets-dev

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

# Install scrcpy
cd /tmp
sudo git clone https://github.com/Genymobile/scrcpy.git
cd scrcpy
sudo meson setup x --buildtype release --strip -Db_lto=true
sudo ninja -Cx
sudo ninja -Cx install

# Create script to keep scrcpy running for browser streaming
sudo tee /usr/local/bin/android_stream_service.sh > /dev/null <<'EOF'
#!/bin/bash
export ANDROID_SDK_ROOT=/opt/android-sdk
export PATH=$ANDROID_SDK_ROOT/platform-tools:$PATH

adb start-server

while true; do
    if adb devices | grep -w "device" | grep -v "List"; then
        scrcpy --tcpip=localhost --no-display --no-control &
        sleep 60
    else
        sleep 5
    fi
done
EOF
sudo chmod +x /usr/local/bin/android_stream_service.sh

# Create OpenVSCode Server systemd service
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

# Create Android stream systemd service
sudo tee /etc/systemd/system/android-stream.service > /dev/null <<EOF
[Unit]
Description=Android Stream (scrcpy) Service
After=network.target

[Service]
Type=simple
User=$USER
ExecStart=/usr/local/bin/android_stream_service.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
sudo systemctl daemon-reload
sudo systemctl enable --now openvscode-server
sudo systemctl enable --now android-stream.service

# Print connection info
IP=$(hostname -I | awk '{print $1}')
echo "========================================"
echo "OpenVSCode Server is running!"
echo "URL: http://$IP:$OVSC_PORT"
echo "Username: $USER"
echo "Password: $OVSC_PASS"
echo "You can also find these credentials in .env"
echo "========================================"
