# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.4.2] - 2026-06-16

### Changed

- Reframed the install module as an on-device command install/update at `/usr/local/sbin/pikvm-optimizer`
- Expanded README documentation for fresh setup, module behavior, official PiKVM docs, safety model, and on-device updates
- Added remote script `--help` and `--version` output for installed/on-device usage
- Added `--config` and `--write-config-template` for declarative, non-secret YAML configuration
- Added standalone [`pikvm-optimizer.yaml.example`](pikvm-optimizer.yaml.example) template in the repo
- Added non-secret WiFi wizard defaults via YAML or `--wifi-ssid`, `--wifi-country`, and `--wifi-ap-ssid`

### Fixed

- Fixed local and remote menu box rendering so ANSI color escapes no longer print literally or break border width
- Added validation for remote options that require values
- Clarified "fallback AP" prompt to explain it is a hotspot PiKVM creates when client WiFi is unavailable
- Added "blank to skip" option to MSD storage protocol prompt so blank skips the entire module instead of defaulting to NFS
- Added "blank to skip" option to MSD drives, NFS export path, and SMB share path prompts
- Added "(blank to skip)" hint to root password, admin password, and TOTP verify prompts
- Added password minimum-length hint to WiFi client password prompt
- Added mandatory TOTP code verification after 2FA setup — retries 3 times, offers skip or disable on failure
- Added password retry loop (3 attempts) for root and Web/KVM admin passwords — hard fails instead of silently skipping
- Added preset feedback messages when toggling via interactive menu
- Added visual section separators between module groups during execution
- Added preset/summary line showing what preset or flags are active
- Clarified Tailscale crash fix in-progress message to say "32-bit ARM"
- Added section-comment headers grouping the execution block into hardware/networking/security
- Fixed QR code rendering corruption by printing TOTP output outside the box border system
- Clarified module selection menu prompt to show "Enter to proceed" instead of bare "Selection:"
- Fixed installed/on-device cleanup so it never removes `/usr/local/sbin` or other non-temporary script directories
- Limited MSD storage uninstall cleanup to optimizer-marked `/etc/fstab` entries
- Hardened password and TOTP setup error handling
- Restricted generated WiFi auto script permissions because it contains fallback AP credentials

## [1.4.1] - 2026-06-16

### Added

- `--tailscale-setup` module to install/start Tailscale and run interactive `tailscale up`
- WiFi SSID scanner/selector for interactive `--wifi` setup

### Changed

- Clarified Dell D2721H bundled EDID language and why it is the safe default
- Clarified root vs Web/KVM admin password prompts
- Clarified network storage setup requirements, persistence, and rerun guidance
- Uninstall-all no longer prompts for SSH key or disabled sudo cleanup by default
- Sudo cleanup now removes only optimizer-managed sudoers files without prompting

### Fixed

- 2FA setup now creates `/etc/kvmd/override.d` before using `kvmd-totp`

## [1.4.0] - 2026-06-16

### Added

- `--wifi` module for PiKVM WiFi auto mode:
  - Client mode via native `systemd-networkd` + `wpa_supplicant@wlanX`
  - Fallback AP mode via `hostapd@wlanX` + dedicated dnsmasq service
  - Runtime WiFi interface detection so a later USB dongle can enable simultaneous client+AP mode
  - Auto re-evaluation timer (`pikvm-wifi-auto.timer`) for client/AP fallback decisions
- `--root-password` module for interactive Linux root password changes
- `--first-run` module for interactive Web/KVM `admin` password setup with `kvmd-htpasswd`
- `--2fa` module for PiKVM TOTP setup/show using `kvmd-totp`
- 2FA uninstall support via `kvmd-totp del`

### Changed

- `--all` remains limited to safe non-secret modules; WiFi, root password, first-run, and 2FA require explicit selection
- `--print-remote` extraction now matches the heredoc opener correctly

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
