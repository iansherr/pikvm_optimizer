# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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