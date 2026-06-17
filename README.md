# PiKVM Optimizer

A single-file macOS/Linux launcher with an embedded PiKVM remote optimizer for first-run setup, video tuning, network access, MSD/USB configuration, and safe rollback.

The script runs from your workstation, copies a temporary remote script to your PiKVM over SSH, applies the selected modules, validates configuration where possible, and removes the temporary remote copy afterward.

## Highlights

- **First-run setup**: Set the Web/KVM `admin` password, change the Linux `root` password, and configure TOTP 2FA.
- **Video and viewer tuning**: Apply streamer/VNC settings, persistent EDID, JPEG quality cap, and fan curve settings.
- **WiFi onboarding**: Configure WiFi client mode with automatic fallback AP mode, including later USB WiFi dongle support.
- **Tailscale setup and diagnostics**: Install/start Tailscale (with automatic curl-based fallback if pacman mirror fails), run `tailscale up`, tune MTU/keepalive, and diagnose networking issues.
- **PiKVM OS updates**: Refresh package databases and upgrade all packages with built-in retries, reboot detection, and post-update reconnection guidance.
- **MSD and USB utilities**: Apply BIOS-safe MSD behavior, configure USB device presets/extras, mount network storage, and add virtual MSD drives.
- **Safe operations**: Dry-run mode, backups before config writes, uninstall/cleanup menus, and rollback guidance.

## Relationship to PiKVM docs

This project automates common PiKVM setup tasks; it does not replace the official documentation. Use the PiKVM docs as the source of truth for hardware-specific behavior and advanced configuration:

- [PiKVM documentation](https://docs.pikvm.org/)
- [PiKVM V4 docs](https://docs.pikvm.org/v4/)
- [WiFi](https://docs.pikvm.org/wifi/)
- [Authentication and 2FA](https://docs.pikvm.org/auth/)
- [Tailscale](https://docs.pikvm.org/tailscale/)
- [EDID](https://docs.pikvm.org/edid/)

## Installation

### Download release

```bash
curl -LO https://github.com/iansherr/pikvm_optimizer/releases/latest/download/pikvm_optimizer.sh
chmod +x pikvm_optimizer.sh
./pikvm_optimizer.sh
```

### From source

```bash
git clone https://github.com/iansherr/pikvm_optimizer.git
cd pikvm_optimizer
chmod +x pikvm_optimizer.sh
./pikvm_optimizer.sh
```

## Quick start for a fresh PiKVM

Run interactively from your Mac or Linux workstation:

```bash
./pikvm_optimizer.sh --host pikvm.local
```

Recommended first-run modules to consider:

```bash
# First, update the PiKVM OS to refresh package databases (recommended before tailscale)
./pikvm_optimizer.sh --host pikvm.local --pikvm-update

# Then apply setup modules
./pikvm_optimizer.sh --host pikvm.local --first-run --root-password --wifi --tailscale-setup --2fa
```

Notes:

- `--first-run` changes the PiKVM Web UI/API/VNC `admin` password.
- `--root-password` changes the Linux `root` password used for SSH/serial console.
- `--wifi` can configure client WiFi and fallback AP mode. Generated fallback AP credentials are printed after setup.
- `--tailscale-setup` installs/enables Tailscale and runs `tailscale up` in interactive mode. Has automatic fallback if pacman mirror fails.
- `--2fa` initializes or shows the PiKVM TOTP secret.
- `--pikvm-update` refreshes package databases and upgrades all PiKVM OS packages. Run it before other modules to ensure package versions are current.

## Common commands

```bash
# Preview selected changes without intentionally persisting them
./pikvm_optimizer.sh --host pikvm.local --dry-run

# Apply the conservative recommended preset non-interactively
./pikvm_optimizer.sh --host pikvm.local --recommended --yes

# Apply all safe non-secret modules
./pikvm_optimizer.sh --host pikvm.local --all

# Configure WiFi client + fallback AP
./pikvm_optimizer.sh --host pikvm.local --wifi

# Refresh package DBs and upgrade all PiKVM OS packages
./pikvm_optimizer.sh --host pikvm.local --pikvm-update

# Install/start Tailscale and log in
./pikvm_optimizer.sh --host pikvm.local --tailscale-setup

# Run diagnostics only
./pikvm_optimizer.sh --host pikvm.local --health-check --yes

# Open cleanup menu
./pikvm_optimizer.sh --host pikvm.local --uninstall

# Restore /etc/kvmd/override.yaml from backup
./pikvm_optimizer.sh --host pikvm.local --restore

# Extract the embedded remote script for debugging
./pikvm_optimizer.sh --print-remote > /tmp/pikvm-optimizer-remote.sh
```

## Command-line reference

### Connection options

| Option | Description |
|--------|-------------|
| `--host HOST` | PiKVM IP address or hostname |
| `--user USER` | SSH user, default: `root` |
| `--identity PATH` | SSH private key path |
| `--config PATH` | Load declarative YAML config; later CLI flags override it |
| `--write-config-template PATH` | Write a starter YAML config template and exit; use `-` for stdout |

### Run modes

| Option | Description |
|--------|-------------|
| `--dry-run` | Preview actions without persistent PiKVM changes where possible |
| `--yes` | Non-interactive mode; run selected flags/preset directly |
| `--health-check` | Run diagnostics only |
| `--uninstall` | Open uninstall/cleanup menu |
| `--restore` | Restore `/etc/kvmd/override.yaml` from backup |
| `--print-remote` | Print embedded remote script and exit |
| `--reboot` | Reboot PiKVM after changes |
| `--no-color` | Disable color output |
| `-V`, `--version` | Show version |

### Presets

| Preset | Description |
|--------|-------------|
| `--recommended` | Conservative defaults for core tuning and BIOS-safe MSD behavior |
| `--all` | All safe non-secret modules; excludes WiFi, Tailscale login, password changes, and 2FA |
| `--none` | Select no modules |

### Module flags

| Flag | Module |
|------|--------|
| `--core` / `--no-core` | Enable or disable core streamer/VNC settings |
| `--mtu` | Tailscale MTU tuning |
| `--edid` | Persistent HDMI EDID |
| `--edid-url URL` | EDID hex file URL for non-interactive setup |
| `--edid-file PATH` | Local EDID hex file for non-interactive setup |
| `--ssl` | Tailscale SSL certificate deployment |
| `--fan` | Fan curve configuration |
| `--watchdog` | Tailscale watchdog timer |
| `--quality-cap` | VNC JPEG quality cap for viewer compatibility |
| `--keepalive` | TCP keepalive tuning for Tailscale stability |
| `--tailscale-diag` | Read-only Tailscale networking diagnosis |
| `--tailscale-setup` | Install/enable Tailscale and run `tailscale up` (auto-retries with DB refresh and curl fallback) |
| `--tailscale-crash-fix` | 32-bit ARM Tailscale crash mitigations; skipped on 64-bit systems |
| `--pikvm-update` | Refresh package databases and upgrade all PiKVM OS packages (3 retries each step) |
| `--wifi` | WiFi client mode with fallback AP mode |
| `--root-password` | Change Linux root password |
| `--first-run` | Set Web/KVM admin password |
| `--2fa` | Configure PiKVM TOTP 2FA |
| `--msd-bios-fix` | BIOS-safe MSD behavior for UEFI boot-loop avoidance |
| `--usb-preset` | USB device preset, including Normal/BIOS mode |
| `--usb-extra` | USB extras: Ethernet, Serial, Audio |
| `--msd-storage` | Mount NFS/SMB network storage for MSD images |
| `--msd-drives` | Configure additional MSD virtual drives |
| `--override-d` | Enable `/etc/kvmd/override.d/` YAML fragments |
| `--key` | Install SSH public key |
| `--pubkey-file PATH` | SSH public key file for non-interactive install |
| `--install` | Install or update the on-device command at `/usr/local/sbin/pikvm-optimizer` |

Restricted sudo support is intentionally disabled in current interactive flows. Cleanup removes only optimizer-managed files matching `/etc/sudoers.d/pikvm-optimizer-*`.

## On-device install and updates

`--install` copies the currently running remote optimizer script onto the PiKVM as:

```text
/usr/local/sbin/pikvm-optimizer
```

That lets you run the optimizer directly from the PiKVM later, for example:

```bash
pikvm-optimizer --health-check --yes
pikvm-optimizer --version
```

It does not install a daemon, background updater, package manager hook, or scheduled job. To update the on-device copy, download or clone a newer launcher on your workstation and run `--install` again:

```bash
./pikvm_optimizer.sh --host pikvm.local --install --yes
```

If an on-device copy already exists, the script backs it up before replacing it. Remove the installed command from the uninstall/cleanup menu.

## Declarative YAML config

You can keep repeatable, non-secret choices in a YAML config file. A starter template is included in the repo at
[`pikvm-optimizer.yaml.example`](pikvm-optimizer.yaml.example):

```bash
cp pikvm-optimizer.yaml.example pikvm-optimizer.yaml
./pikvm_optimizer.sh --config pikvm-optimizer.yaml
```

You can also generate the template from the script itself:

```bash
./pikvm_optimizer.sh --write-config-template pikvm-optimizer.yaml
./pikvm_optimizer.sh --config pikvm-optimizer.yaml
```

Omitted keys use the script defaults. Config is expanded before normal option parsing, so explicit CLI flags override the file:

```bash
# Use the config, but force dry-run for this invocation
./pikvm_optimizer.sh --config pikvm-optimizer.yaml --dry-run
```

The template supports connection settings, run mode, preset, module toggles, EDID URL/file, and SSH public key file. It intentionally does not store passwords, TOTP secrets, WiFi passphrases, private keys, or Tailscale credentials. YAML support requires Python with PyYAML on the workstation running the launcher.

For interactive modules, config values act as wizard defaults. For example, `wifi.ssid`, `wifi.country`, and `wifi.ap_ssid` prefill the WiFi prompts, but the client WiFi password is still requested interactively and the fallback AP password is still generated unless you type one at the prompt.

Use `run.non_interactive: true` in YAML for `--yes` behavior. The template avoids a key literally named `yes` because some YAML parsers treat unquoted `yes` as a boolean instead of a string key.

## What the optimizer changes

Depending on selected modules, the optimizer may manage these files on the PiKVM:

- `/etc/kvmd/override.yaml` - main KVMD configuration
- `/etc/kvmd/override.d/` - optional YAML fragment directory
- `/etc/kvmd/tc358743-edid.hex` - EDID configuration
- `/etc/conf.d/kvmd-fan` - fan configuration
- `/etc/systemd/network/99-tailscale-mtu.link` - Tailscale MTU config
- `/etc/sysctl.d/60-tailscale0-ipv6.conf` - 32-bit Tailscale crash mitigation
- `/etc/kvmd/nginx/ssl/` - SSL certificate/key files
- `/usr/local/bin/pikvm-tailscale-watchdog.sh` - Tailscale watchdog script
- `/etc/systemd/system/pikvm-tailscale-watchdog.*` - watchdog service/timer
- `/usr/local/bin/pikvm-wifi-auto.sh` - WiFi client/AP orchestration script
- `/etc/systemd/system/pikvm-wifi-auto.*` - WiFi auto service/timer
- `/etc/systemd/system/pikvm-wifi-ap-dnsmasq.service` - fallback AP DHCP/DNS service
- `/etc/systemd/network/25-wlan*.network` - generated WiFi networkd config
- `/etc/wpa_supplicant/wpa_supplicant-wlan*.conf` - generated WiFi client config
- `/etc/hostapd/wlan*.conf` - generated fallback AP config
- `/etc/fstab` - optional NFS/SMB MSD storage mounts

The script backs up edited configuration files before writing where practical and prints rollback guidance when a risky config path is detected.

## Safety model

- Use `--dry-run` first when exploring modules.
- Secret/login modules and `--pikvm-update` are explicit opt-in and are not included in `--all` or `--recommended`.
- Password modules explain the difference between Linux `root` and Web/KVM `admin` credentials before prompting.
- WiFi setup prints the generated fallback AP SSID/password and fallback URL.
- Network storage setup expects an existing NFS/SMB server and persists mounts in `/etc/fstab`.
- The uninstall menu targets optimizer-created or optimizer-managed changes instead of broad system cleanup.

## Troubleshooting

```bash
# Check script syntax locally
bash -n pikvm_optimizer.sh

# Verify the embedded remote script parses
./pikvm_optimizer.sh --print-remote > /tmp/pikvm-optimizer-remote.sh
bash -n /tmp/pikvm-optimizer-remote.sh

# Run PiKVM health checks
./pikvm_optimizer.sh --host pikvm.local --health-check --yes
```

If a module fails, rerun with `--dry-run` or use `--health-check` to inspect service status before applying more changes.

## Contributing

Contributions are welcome. Please keep changes focused and test the launcher plus extracted remote script before opening a pull request.

1. Fork the repository.
2. Create a feature branch.
3. Run `bash -n pikvm_optimizer.sh`.
4. Run `./pikvm_optimizer.sh --print-remote > /tmp/pikvm-optimizer-remote.sh && bash -n /tmp/pikvm-optimizer-remote.sh`.
5. Commit your changes and open a pull request.

## Versioning

This project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html). See [CHANGELOG.md](CHANGELOG.md) for release notes.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

- **PiKVM Project** - For creating the excellent PiKVM platform ([GitHub](https://github.com/pikvm/pikvm))
- **PiKVM Community** - For community support and operational guidance ([Reddit](https://reddit.com/r/pikvm))
- **AI Agent** - For iterative development assistance and code refinement

## Author

**Ian Sherr** - [iansherr.com](https://iansherr.com)

Project by [Time Worthy Media](https://timeworthymedia.com)
