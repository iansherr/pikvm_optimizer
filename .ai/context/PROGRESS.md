# Progress

## 2026-06-17

### Done
- **Fixed Tailscale package name**: Changed `pacman -S tailscale` → `pacman -S tailscale-pikvm` (PiKVM ships Tailscale under a different package name, confirmed by PiKVM docs at docs.pikvm.org/tailscale/)
- **Fixed cancel/rollback bug**: `cancel_remote()` was calling `trap - EXIT INT TERM` before `exit 130`, which silently removed the EXIT trap — `cleanup_remote()` (and thus `rollback_changes()`) NEVER actually ran on Ctrl-C. Changed to `trap - INT TERM` only, preserving the EXIT trap.
- **Added irreversible module tracking**: New `_EXECUTED` flags for root password, admin password, 2FA/TOTP, Tailscale setup, WiFi config, and Tailscale crash fix — set on successful completion so rollback summary can report what can't be undone.
- **Added rollback summary**: At the end of `rollback_changes()`, a boxed summary lists everything that was reverted and everything left in place (irreversible actions). The `cancel_remote()` message now sets expectations upfront about what can't be undone.

### Pending
- Live PiKVM test: deploy remote script and test --tailscale-setup, box wrapping, Ctrl-C rollback summary
- Create TODO.md

### Known Issues
- PiKVM not on network right now for testing
