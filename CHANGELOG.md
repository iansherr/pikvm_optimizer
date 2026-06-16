# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.0] - 2026-06-16

### Added

- `--tailscale-crash-fix` module: 32-bit ARM crash mitigations for Tailscale gVisor alignment bug
  - Auto-detects architecture via `uname -m` (ignores on 64-bit aarch64/amd64)
  - On 32-bit ARM: disables IPv6 on tailscale0, sets systemd WatchdogSec=15s + RestartSec=1s
  - Reduces crash cycle downtime from ~38s to ~23s
- `--msd-bios-fix` module: MSD BIOS compatibility mode with UEFI/NVRAM workaround
- `--usb-preset` module: USB device preset configuration (Normal/BIOS safe mode)
- `--usb-extra` module: USB extras (Ethernet/Serial/Audio) with interactive multi-select
- `--msd-storage` module: Network storage mount (NFS/SMB) for MSD ISO images
- `--msd-drives` module: Dual MSD virtual drives (HDD + CD-ROM) support
- `--override-d` module: override.d YAML fragment directory support
- `--tailscale-diag` module: read-only Tailscale networking diagnosis
- `detect_arch()` helper function for architecture-specific logic
- `--none` flag now properly passed through local launcher to remote script
- `--tailscale-crash-fix` flag in `--all` preset, interactive menu (`c` key), and uninstall menu

### Changed

- `--all` preset includes all new modules (crash fix, MSD fix, USB preset, USB extras, MSD storage, MSD drives, override.d)
- Interactive module menu reorganized with letter-key bindings for extended module set
- Version bumped from 1.2.0 to 1.3.0

### Fixed

- `run_tailscale_diag` → `apply_tailscale_diag` function name mismatch in execution block
- `$VERSION` unbound variable error in remote script mode when not passed as flag
- Stale README file in `/etc/kvmd/override.d/` breaking `kvmd -M` YAML validation

## [1.2.0] - 2026-06-14

### Added

- `--reboot` flag to auto-reboot PiKVM after changes
- Post-run reboot warning for MTU/EDID modules
- 5-second delay before reboot with Ctrl+C cancel option

### Changed

- Service restarts are non-fatal; script continues on failure
- SSH connection multiplexing (ControlMaster) for single auth prompt
- Health check warnings don't trigger rollback
- Malformed config replacement uses YAML syntax validation only

### Fixed

- `set +e` in remote script to prevent premature exit on errors
- Bad substitution fix: `${#SSH_OPTS[@]:-0}` → `${#SSH_OPTS[@]}`
- `final_restart` non-fatal; `health_check` non-fatal
- `--print-remote` outputs only remote script
- SSH key prompt clarity improved
- UI box line truncation for long paths

## [1.1.0] - 2026-06-14

### Security

- Use `mktemp -d` for secure remote temp directories instead of predictable paths
- Add backups for all overwritten files (MTU, EDID, SSL, watchdog)
- Make config writes atomic using temp file + `mv` instead of `cp`
- Require HTTPS for EDID downloads and validate file type/size
- Validate SSH key install paths to reject symlinks
- Add input validation for options requiring values
- Reject host/user values starting with `-` to prevent SSH option injection

### Fixed

- `--print-remote` now outputs only the remote script without local banner
- `--pubkey-file` reads the file locally and passes content to remote script
- Service restart failures are now properly reported
- Improved error handling for critical operations

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