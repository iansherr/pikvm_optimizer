# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-06-14

### Added

- Initial release of PiKVM Optimizer
- Core streamer/VNC settings optimization
- Tailscale MTU configuration
- Persistent EDID setup
- Tailscale SSL certificate deployment
- Fan curve configuration
- Tailscale watchdog installation
- SSH public key management
- Permanent optimizer installation
- Restricted NOPASSWD sudo configuration
- Health check diagnostics
- Uninstall and restore functionality
- Dry run mode for safe testing
- Non-interactive mode with `--yes` flag
- `--pubkey-file` for non-interactive SSH key install
- `--sudo-user` for non-interactive restricted sudo
- `--edid-url` and `--edid-file` for non-interactive EDID setup
- `--print-remote` to extract embedded remote script
- Version flag (`--version`)
- Comprehensive command-line interface
- Automatic backups and rollback support
- MIT License