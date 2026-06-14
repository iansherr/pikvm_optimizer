# PiKVM Optimizer

A single-file macOS/Linux launcher with embedded PiKVM remote optimizer for configuring and optimizing PiKVM devices.

## Features

- **Core Streamer/VNC Settings**: Optimize video streaming and VNC performance
- **Tailscale MTU**: Configure Tailscale MTU for optimal network performance
- **Persistent EDID**: Set up custom EDID for HDMI capture
- **Tailscale SSL**: Deploy Tailscale SSL certificates for secure connections
- **Fan Curve**: Configure fan cooling profiles
- **Tailscale Watchdog**: Automatic Tailscale connection monitoring
- **SSH Key Management**: Install and manage SSH public keys
- **Permanent Installation**: Install optimizer permanently on PiKVM
- **Restricted Sudo**: Configure passwordless sudo for non-root users
- **Health Check**: Run diagnostics and status checks
- **Uninstall/Restore**: Clean up changes and restore backups

## Installation

### Quick Install

```bash
# Download the latest release
curl -LO https://github.com/iansherr/pikvm-optimizer/releases/latest/download/pikvm_optimizer.sh

# Make executable
chmod +x pikvm_optimizer.sh

# Run
./pikvm_optimizer.sh
```

### From Source

```bash
git clone https://github.com/iansherr/pikvm-optimizer.git
cd pikvm-optimizer
chmod +x pikvm_optimizer.sh
./pikvm_optimizer.sh
```

## Usage

### Basic Usage

```bash
# Interactive mode - will prompt for PiKVM target
./pikvm_optimizer.sh

# Specify target directly
./pikvm_optimizer.sh --host pikvm.local --recommended --yes
```

### Command Line Options

| Option | Description |
|--------|-------------|
| `--host HOST` | PiKVM IP address or hostname |
| `--user USER` | SSH user (default: root) |
| `--identity PATH` | SSH identity file |
| `--dry-run` | Preview actions without persistent changes |
| `--yes` | Non-interactive mode |
| `--health-check` | Run diagnostics only |
| `--uninstall` | Open uninstall/cleanup menu |
| `--restore` | Restore /etc/kvmd/override.yaml from backup |

### Presets

| Preset | Description |
|--------|-------------|
| `--recommended` | Select recommended modules (core settings only) |
| `--all` | Select all safe modules |
| `--none` | Select no modules |

### Module Flags

| Flag | Module |
|------|--------|
| `--core` | Core streamer/VNC settings |
| `--mtu` | Tailscale MTU |
| `--edid` | Persistent EDID |
| `--ssl` | Tailscale SSL certificate |
| `--fan` | Fan curve |
| `--watchdog` | Tailscale watchdog |
| `--key` | SSH public key install |
| `--install` | Install optimizer permanently |
| `--sudo` | Configure restricted NOPASSWD sudo |

## Configuration

The optimizer modifies the following files on your PiKVM:

- `/etc/kvmd/override.yaml` - Main KVMD configuration
- `/etc/conf.d/kvmd-fan` - Fan configuration
- `/etc/systemd/network/99-tailscale-mtu.link` - Tailscale MTU config
- `/etc/kvmd/tc358743-edid.hex` - EDID configuration
- `/etc/kvmd/nginx/ssl/` - SSL certificates
- `/usr/local/bin/pikvm-tailscale-watchdog.sh` - Watchdog script
- `/etc/systemd/system/pikvm-tailscale-watchdog.*` - Watchdog service/timer

All changes are backed up before modification and can be rolled back.

## Safety Features

- **Dry Run Mode**: Preview changes without modifying your system
- **Automatic Backups**: All configuration files are backed up before changes
- **Rollback Support**: Undo changes if something goes wrong
- **Validation**: Configuration changes are validated before applying
- **SSH Cleanup**: Temporary files are automatically removed

## Examples

```bash
# Dry run to see what would be changed
./pikvm_optimizer.sh --host pikvm.local --dry-run

# Apply recommended settings non-interactively
./pikvm_optimizer.sh --host pikvm.local --recommended --yes

# Apply all safe modules
./pikvm_optimizer.sh --host pikvm.local --all

# Run health check
./pikvm_optimizer.sh --host pikvm.local --health-check --yes

# Uninstall optimizer changes
./pikvm_optimizer.sh --host pikvm.local --uninstall

# Restore configuration from backup
./pikvm_optimizer.sh --host pikvm.local --restore
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- **PiKVM Community** - For the amazing PiKVM project and community support ([GitHub](https://github.com/pikvm/pikvm), [Reddit](https://reddit.com/r/pikvm))
- **PiKVM Project** - For creating the excellent PiKVM platform
- **AI Agent** - For iterative development assistance and code refinement
- **Time Worthy Media** - For project support and development

## Author

**Ian Sherr** - [iansherr.com](https://iansherr.com)

Project by [Time Worthy Media](https://timeworthymedia.com)

---

*This tool was developed with help from the PiKVM community, the PiKVM project itself, and iterative work with an AI agent.*