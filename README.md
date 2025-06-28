# Android Dev & OpenVSCode Server One-Click Setup

## Usage (one command)

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/setup.sh)
```

- Installs OpenVSCode Server v1.101.2
- Installs Android SDK/NDK, scrcpy, and dependencies
- Sets up always-on Android streaming service
- Auto-generates connection password and prints it at the end

## After install

- Access your OpenVSCode Server in the browser (see printed credentials)
- Android streaming service will auto-start with your device attached

## Security

- Credentials are auto-generated and saved to `openvscode_env.txt`
- You may want to set up a firewall or HTTPS for public deployments

## Troubleshooting

- If you encounter errors, check systemd logs:
  - `sudo systemctl status openvscode-server`
  - `sudo systemctl status android-stream.service`