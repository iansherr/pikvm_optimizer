#!/usr/bin/env bash
# ==============================================================================
# PiKVM Optimizer
# Single-file macOS/Linux launcher with embedded PiKVM remote optimizer.
# Version: 1.0.0
# ==============================================================================

set -euo pipefail

VERSION="1.0.0"

# ------------------------------------------------------------------------------
# Local launcher options
# ------------------------------------------------------------------------------

DRY_RUN=false
YES=false
NO_COLOR_LOCAL=false
PI_HOST=""
PI_USER=""
SSH_KEY=""
PUBKEY_FILE=""
SUDO_USER=""
EDID_URL=""
EDID_FILE=""
PRINT_REMOTE=false
REMOTE_ARGS=()

require_arg() {
    local opt="$1"
    local val="${2:-}"
    if [ -z "$val" ]; then
        printf "Error: %s requires a value\n" "$opt" >&2
        exit 1
    fi
}

usage() {
    cat <<EOF
Usage:
  $0 [options]

Connection options:
  --host HOST        PiKVM IP address or hostname
  --user USER        SSH user, default: root
  --identity PATH    SSH identity file

Run modes:
  --dry-run          Preview actions without persistent PiKVM changes
  --yes              Non-interactive mode; run selected flags/preset directly
  --health-check     Run diagnostics only
  --uninstall        Open uninstall/cleanup menu
  --restore          Restore /etc/kvmd/override.yaml from backup

Presets:
  --recommended      Select recommended modules
  --all              Select all safe modules; does not include restricted sudo
  --none             Select no modules

Module flags:
  --core             Enable core streamer/VNC settings
  --no-core          Disable core streamer/VNC settings
  --mtu              Enable Tailscale MTU module
  --edid             Enable EDID module
  --edid-url URL     EDID hex file URL (non-interactive)
  --edid-file PATH   EDID hex file local path (non-interactive)
  --ssl              Enable Tailscale SSL module
  --fan              Enable fan curve module
  --watchdog         Enable Tailscale watchdog module
  --key              Enable SSH public key install module
  --pubkey-file PATH SSH public key file for non-interactive install
  --install          Install optimizer permanently on PiKVM
  --sudo             Configure restricted NOPASSWD sudo for installed optimizer
  --sudo-user USER   User for restricted sudo (non-interactive)

Other:
  --print-remote     Print embedded remote script and exit
  --no-color         Disable color output
  -V, --version      Show version
  -h, --help         Show this help

Examples:
  $0
  $0 --host pikvm.local --dry-run
  $0 --host pikvm.local --recommended --yes
  $0 --host pikvm.local --all
  $0 --host pikvm.local --health-check --yes
  $0 --host pikvm.local --uninstall
  $0 --host pikvm.local --key --pubkey-file ~/.ssh/id_ed25519.pub --yes
  $0 --host pikvm.local --sudo --sudo-user admin --yes
  $0 --host pikvm.local --edid --edid-url https://example.com/edid.hex --yes
  $0 --print-remote > /tmp/pikvm-optimizer-remote.sh
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --host)
            require_arg "$1" "${2:-}"
            PI_HOST="$2"
            shift 2
            ;;
        --user)
            require_arg "$1" "${2:-}"
            PI_USER="$2"
            shift 2
            ;;
        --identity|-i)
            require_arg "$1" "${2:-}"
            SSH_KEY="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            REMOTE_ARGS+=(--dry-run)
            shift
            ;;
        --yes|--non-interactive)
            YES=true
            REMOTE_ARGS+=(--yes)
            shift
            ;;
        --health-check)
            REMOTE_ARGS+=(--health-check)
            shift
            ;;
        --uninstall)
            REMOTE_ARGS+=(--uninstall)
            shift
            ;;
        --restore)
            REMOTE_ARGS+=(--restore)
            shift
            ;;
        --recommended)
            REMOTE_ARGS+=(--recommended)
            shift
            ;;
        --all)
            REMOTE_ARGS+=(--all)
            shift
            ;;
        --none)
            REMOTE_ARGS+=(--none)
            shift
            ;;
        --core|--no-core|--mtu|--edid|--ssl|--fan|--watchdog|--key|--install|--sudo)
            REMOTE_ARGS+=("$1")
            shift
            ;;
        --edid-url)
            require_arg "$1" "${2:-}"
            EDID_URL="$2"
            REMOTE_ARGS+=(--edid-url "$EDID_URL")
            shift 2
            ;;
        --edid-file)
            require_arg "$1" "${2:-}"
            EDID_FILE="$2"
            REMOTE_ARGS+=(--edid-file "$EDID_FILE")
            shift 2
            ;;
        --pubkey-file)
            require_arg "$1" "${2:-}"
            PUBKEY_FILE="$2"
            if [ ! -f "$PUBKEY_FILE" ]; then
                printf "Error: Public key file not found: %s\n" "$PUBKEY_FILE" >&2
                exit 1
            fi
            PUBKEY_CONTENT="$(cat "$PUBKEY_FILE")"
            REMOTE_ARGS+=(--pubkey-content "$PUBKEY_CONTENT")
            shift 2
            ;;
        --sudo-user)
            require_arg "$1" "${2:-}"
            SUDO_USER="$2"
            REMOTE_ARGS+=(--sudo-user "$SUDO_USER")
            shift 2
            ;;
        --print-remote)
            PRINT_REMOTE=true
            shift
            ;;
        --no-color)
            export NO_COLOR=true
            NO_COLOR_LOCAL=true
            REMOTE_ARGS+=(--no-color)
            shift
            ;;
        -V|--version)
            printf "PiKVM Optimizer v%s\n" "$VERSION"
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf "Unknown option: %s\n\n" "$1"
            usage
            exit 1
            ;;
    esac
done

# Validate input values
if [ -n "$PI_HOST" ] && [[ "$PI_HOST" == -* ]]; then
    printf "Error: --host cannot start with '-'\n" >&2
    exit 1
fi

if [ -n "$PI_USER" ] && [[ "$PI_USER" == -* ]]; then
    printf "Error: --user cannot start with '-'\n" >&2
    exit 1
fi

if [ -n "$SUDO_USER" ] && [[ "$SUDO_USER" == -* ]]; then
    printf "Error: --sudo-user cannot start with '-'\n" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Local launcher UI/helpers
# ------------------------------------------------------------------------------

R="\033[31m"
G="\033[32m"
Y="\033[33m"
C="\033[36m"
BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"

if [ "${TERM:-}" = "dumb" ] || [ "${NO_COLOR:-false}" = "true" ]; then
    R=""
    G=""
    Y=""
    C=""
    BOLD=""
    DIM=""
    RESET=""
fi

REMOTE_DEST=""
LOCAL_CLEANED=false

shell_quote() {
    # Single-quote a string for remote shell use.
    printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

quote_args() {
    local out=""
    local arg=""

    for arg in "$@"; do
        out="${out} $(shell_quote "$arg")"
    done

    printf "%s" "$out"
}

cleanup_local() {
    local rc=$?

    if [ "$LOCAL_CLEANED" = true ]; then
        exit "$rc"
    fi

    LOCAL_CLEANED=true

    if [ -n "${PI_HOST:-}" ] && [ -n "${PI_USER:-}" ] && [ -n "${REMOTE_DIR:-}" ] && [ "${#SSH_OPTS[@]:-0}" -gt 0 ]; then
        ssh "${SSH_OPTS[@]}" "${PI_USER}@${PI_HOST}" "rm -rf '$REMOTE_DIR'" >/dev/null 2>&1 || true
    fi

    exit "$rc"
}

cancel_local() {
    printf "\n%bCancelled locally. Cleaning up remote temp file if possible...%b\n" "$Y" "$RESET"
    cleanup_local
}

if [ "$PRINT_REMOTE" = true ]; then
    sed -n '/^PIKVM_REMOTE_SCRIPT$/,/^PIKVM_REMOTE_SCRIPT$/p' "$0" | sed '1d;$d'
    exit 0
fi

printf "%b\n" "${C}${BOLD}PiKVM Optimizer${RESET}"
printf "%b\n" "${DIM}Single-file launcher. The PiKVM-side optimizer is embedded and sent over SSH.${RESET}"

if [ "$DRY_RUN" = true ]; then
    printf "%b\n" "${Y}${BOLD}DRY RUN ENABLED:${RESET} persistent PiKVM changes will be skipped where possible."
fi

printf "\n"

if [ -z "$PI_HOST" ]; then
    read -rp "PiKVM target IP or hostname: " PI_HOST
fi

[ -z "$PI_HOST" ] && exit 1

if [ -z "$PI_USER" ]; then
    read -rp "SSH user [root]: " PI_USER
    PI_USER="${PI_USER:-root}"
fi

if [ -z "$SSH_KEY" ]; then
    read -rp "Optional SSH identity file path [default SSH agent/keychain]: " SSH_KEY
fi

REMOTE_DIR=""
REMOTE_DEST=""

SSH_OPTS=(
    -o ConnectTimeout=10
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=2
    -o StrictHostKeyChecking=accept-new
)

if [ -n "$SSH_KEY" ]; then
    SSH_OPTS+=(-i "$SSH_KEY")
fi

trap cancel_local INT TERM

printf "\n%bTesting SSH access...%b\n" "$DIM" "$RESET"

if ! ssh "${SSH_OPTS[@]}" "${PI_USER}@${PI_HOST}" "echo ok" >/dev/null; then
    printf "%bSSH login failed.%b\n" "$R" "$RESET"
    printf "Use the PiKVM Linux SSH account, usually root, not just the web UI account.\n"
    exit 1
fi

printf "%bCreating secure temp directory...%b\n" "$DIM" "$RESET"

REMOTE_DIR="$(ssh "${SSH_OPTS[@]}" "${PI_USER}@${PI_HOST}" "mktemp -d /tmp/pikvm-optimizer.XXXXXXXXXX" 2>/dev/null)" || {
    printf "%bFailed to create temp directory on PiKVM.%b\n" "$R" "$RESET"
    exit 1
}

REMOTE_DEST="${REMOTE_DIR}/optimizer.sh"

printf "%bUploading embedded optimizer...%b\n" "$DIM" "$RESET"

ssh "${SSH_OPTS[@]}" "${PI_USER}@${PI_HOST}" "cat > '$REMOTE_DEST' && chmod 700 '$REMOTE_DEST'" <<'PIKVM_REMOTE_SCRIPT'
#!/usr/bin/env bash
# ==============================================================================
# Embedded PiKVM Remote Optimizer
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Remote options
# ------------------------------------------------------------------------------

DRY_RUN=false
YES=false
MODE="optimize"
PRESET="interactive"
FLAGS_PROVIDED=false

RUN_CORE=true
RUN_MTU=false
RUN_EDID=false
RUN_SSL=false
RUN_FAN=false
RUN_WATCHDOG=false
RUN_KEY=false
RUN_INSTALL=false
RUN_SUDO=false

UN_CORE=false
UN_MTU=false
UN_EDID=false
UN_SSL=false
UN_FAN=false
UN_WATCHDOG=false
UN_KEY=false
UN_INSTALL=false
UN_SUDO=false

EDID_URL=""
EDID_FILE=""
PUBKEY_CONTENT=""
SUDO_USER=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --yes|--non-interactive)
            YES=true
            shift
            ;;
        --health-check)
            MODE="health"
            shift
            ;;
        --uninstall)
            MODE="uninstall"
            shift
            ;;
        --restore)
            MODE="restore"
            shift
            ;;
        --recommended)
            PRESET="recommended"
            RUN_CORE=true
            RUN_MTU=false
            RUN_EDID=false
            RUN_SSL=false
            RUN_FAN=false
            RUN_WATCHDOG=false
            RUN_KEY=false
            RUN_INSTALL=false
            RUN_SUDO=false
            shift
            ;;
        --all)
            PRESET="all"
            RUN_CORE=true
            RUN_MTU=true
            RUN_EDID=true
            RUN_SSL=true
            RUN_FAN=true
            RUN_WATCHDOG=true
            RUN_KEY=true
            RUN_INSTALL=true
            RUN_SUDO=false
            FLAGS_PROVIDED=true
            shift
            ;;
        --none)
            PRESET="none"
            RUN_CORE=false
            RUN_MTU=false
            RUN_EDID=false
            RUN_SSL=false
            RUN_FAN=false
            RUN_WATCHDOG=false
            RUN_KEY=false
            RUN_INSTALL=false
            RUN_SUDO=false
            FLAGS_PROVIDED=true
            shift
            ;;
        --core)
            RUN_CORE=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --no-core)
            RUN_CORE=false
            FLAGS_PROVIDED=true
            shift
            ;;
        --mtu)
            RUN_MTU=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --edid)
            RUN_EDID=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --ssl)
            RUN_SSL=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --fan)
            RUN_FAN=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --watchdog)
            RUN_WATCHDOG=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --key)
            RUN_KEY=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --install)
            RUN_INSTALL=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --sudo)
            RUN_SUDO=true
            RUN_INSTALL=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --edid-url)
            EDID_URL="${2:-}"
            shift 2
            ;;
        --edid-file)
            EDID_FILE="${2:-}"
            shift 2
            ;;
        --pubkey-content)
            PUBKEY_CONTENT="${2:-}"
            shift 2
            ;;
        --sudo-user)
            SUDO_USER="${2:-}"
            shift 2
            ;;
        --no-color)
            export NO_COLOR=true
            shift
            ;;
        *)
            printf "Unknown remote option: %s\n" "$1"
            exit 1
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Remote UI / constants
# ------------------------------------------------------------------------------

R="\033[31m"
G="\033[32m"
Y="\033[33m"
C="\033[36m"
W="\033[37m"
BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"
CLEAR="\033[2J\033[H"
HIDE_CURSOR="\033[?25l"
SHOW_CURSOR="\033[?25h"

if [ "${TERM:-}" = "dumb" ] || [ "${NO_COLOR:-false}" = "true" ]; then
    R=""
    G=""
    Y=""
    C=""
    W=""
    BOLD=""
    DIM=""
    RESET=""
    CLEAR=""
    HIDE_CURSOR=""
    SHOW_CURSOR=""
fi

CONFIG_FILE="/etc/kvmd/override.yaml"
LOG_FILE="/root/pikvm-optimizer.log"
INSTALL_PATH="/usr/local/sbin/pikvm-optimizer"

BACKUP_FILE=""
FAN_BACKUP_FILE=""
INSTALL_BACKUP_FILE=""
MTU_BACKUP_FILE=""
EDID_BACKUP_FILE=""
SSL_BACKUP_FILE=""
WATCHDOG_BACKUP_FILE=""
KEY_TARGET_FILE=""
KEY_INSTALLED_LINE=""
SUDOERS_FILE=""

MADE_RW=false
SUCCESS=false

CONFIG_CHANGED=false
FAN_CHANGED=false
WATCHDOG_CHANGED=false
MTU_CHANGED=false
EDID_CHANGED=false
SSL_CHANGED=false
KEY_CHANGED=false
INSTALL_CHANGED=false
SUDOERS_CHANGED=false

# ------------------------------------------------------------------------------
# Remote UI helpers
# ------------------------------------------------------------------------------

box_top() {
    printf "%b\n" "${C}${BOLD}+------------------------------------------------------------------------------+${RESET}"
}

box_bottom() {
    printf "%b\n" "${C}${BOLD}+------------------------------------------------------------------------------+${RESET}"
}

box_line() {
    local text="${1:-}"
    printf "%b|%b %-76s %b|%b\n" "${C}${BOLD}" "$RESET" "$text" "${C}${BOLD}" "$RESET"
}

box_line_color() {
    local color="$1"
    local text="$2"
    printf "%b|%b %b%-76s%b %b|%b\n" "${C}${BOLD}" "$RESET" "$color" "$text" "$RESET" "${C}${BOLD}" "$RESET"
}

draw() {
    local title="$1"
    printf "%b" "$CLEAR"
    box_top
    printf "%b|%b %b%-76s%b %b|%b\n" "${C}${BOLD}" "$RESET" "${W}${BOLD}" "$title" "$RESET" "${C}${BOLD}" "$RESET"
    box_top
    box_line ""
}

close_box() {
    box_line ""
    box_bottom
}

info() {
    box_line "[INFO] $1"
    log_msg "INFO" "$1"
}

ok() {
    box_line_color "$G" "[OK] $1"
    log_msg "OK" "$1"
}

warn() {
    box_line_color "$Y" "[WARN] $1"
    log_msg "WARN" "$1"
}

err() {
    box_line_color "$R" "[ERR] $1"
    log_msg "ERR" "$1"
}

log_msg() {
    local level="$1"
    local msg="$2"

    if [ "$DRY_RUN" = true ]; then
        return 0
    fi

    {
        printf "[%s] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$msg"
    } >> "$LOG_FILE" 2>/dev/null || true
}

yn_marker() {
    if [ "$1" = true ]; then
        printf "x"
    else
        printf " "
    fi
}

toggle_bool() {
    local var="$1"
    local current="${!var}"

    if [ "$current" = true ]; then
        printf -v "$var" false
    else
        printf -v "$var" true
    fi
}

# ------------------------------------------------------------------------------
# Remote safety / cleanup
# ------------------------------------------------------------------------------

make_rw() {
    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: would run rw."
        return 0
    fi

    if command -v rw >/dev/null 2>&1; then
        rw >/dev/null 2>&1 || rw
        MADE_RW=true
    else
        warn "Command 'rw' not found; continuing without remount helper."
    fi
}

make_ro() {
    if [ "$DRY_RUN" = true ]; then
        MADE_RW=false
        return 0
    fi

    if [ "${MADE_RW:-false}" = true ] && command -v ro >/dev/null 2>&1; then
        ro >/dev/null 2>&1 || ro || true
        MADE_RW=false
    fi
}

safe_restart() {
    local svc="$1"

    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart "$svc" >/dev/null 2>&1 || true
    fi
}

rollback_changes() {
    if [ "$DRY_RUN" = true ]; then
        warn "DRY RUN: rollback not needed."
        return 0
    fi

    warn "Rolling back changes from this run where possible..."
    make_rw

    if [ "$CONFIG_CHANGED" = true ] && [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
        cp "$BACKUP_FILE" "$CONFIG_FILE" || true
        warn "Restored $CONFIG_FILE from backup."
        safe_restart kvmd.service
    fi

    if [ "$FAN_CHANGED" = true ] && [ -n "$FAN_BACKUP_FILE" ] && [ -f "$FAN_BACKUP_FILE" ]; then
        cp "$FAN_BACKUP_FILE" /etc/conf.d/kvmd-fan || true
        warn "Restored /etc/conf.d/kvmd-fan from backup."
        safe_restart kvmd-fan.service
    fi

    if [ "$WATCHDOG_CHANGED" = true ]; then
        systemctl disable --now pikvm-tailscale-watchdog.timer >/dev/null 2>&1 || true
        rm -f \
            /usr/local/bin/pikvm-tailscale-watchdog.sh \
            /etc/systemd/system/pikvm-tailscale-watchdog.service \
            /etc/systemd/system/pikvm-tailscale-watchdog.timer
        systemctl daemon-reload >/dev/null 2>&1 || true
        warn "Removed watchdog files installed by this run."
    fi

    if [ "$MTU_CHANGED" = true ]; then
        if [ -n "$MTU_BACKUP_FILE" ] && [ -f "$MTU_BACKUP_FILE" ]; then
            cp "$MTU_BACKUP_FILE" /etc/systemd/network/99-tailscale-mtu.link || true
            warn "Restored Tailscale MTU config from backup."
        else
            rm -f /etc/systemd/network/99-tailscale-mtu.link
            warn "Removed Tailscale MTU link file installed by this run."
        fi
    fi

    if [ "$EDID_CHANGED" = true ]; then
        if [ -n "$EDID_BACKUP_FILE" ] && [ -f "$EDID_BACKUP_FILE" ]; then
            cp "$EDID_BACKUP_FILE" /etc/kvmd/tc358743-edid.hex || true
            warn "Restored EDID file from backup."
        else
            rm -f /etc/kvmd/tc358743-edid.hex
            warn "Removed EDID file installed by this run."
        fi
    fi

    if [ "$SSL_CHANGED" = true ]; then
        rm -f /etc/kvmd/nginx/ssl/server.crt /etc/kvmd/nginx/ssl/server.key
        safe_restart kvmd-nginx.service
        warn "Removed generated SSL cert/key from this run."
    fi

    if [ "$KEY_CHANGED" = true ] && [ -n "$KEY_TARGET_FILE" ] && [ -n "$KEY_INSTALLED_LINE" ] && [ -f "$KEY_TARGET_FILE" ]; then
        grep -vxF "$KEY_INSTALLED_LINE" "$KEY_TARGET_FILE" > "${KEY_TARGET_FILE}.tmp" || true
        mv "${KEY_TARGET_FILE}.tmp" "$KEY_TARGET_FILE"
        chmod 600 "$KEY_TARGET_FILE" || true
        warn "Removed SSH public key added by this run."
    fi

    if [ "$SUDOERS_CHANGED" = true ] && [ -n "$SUDOERS_FILE" ]; then
        rm -f "$SUDOERS_FILE"
        warn "Removed sudoers rule installed by this run."
    fi

    if [ "$INSTALL_CHANGED" = true ]; then
        if [ -n "$INSTALL_BACKUP_FILE" ] && [ -f "$INSTALL_BACKUP_FILE" ]; then
            cp "$INSTALL_BACKUP_FILE" "$INSTALL_PATH" || true
            chmod 755 "$INSTALL_PATH" || true
            warn "Restored previous permanent optimizer install."
        else
            rm -f "$INSTALL_PATH"
            warn "Removed permanent optimizer install from this run."
        fi
    fi
}

cleanup_remote() {
    local rc=$?
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"

    if [ "$SUCCESS" != true ] && [ "$rc" -ne 0 ]; then
        rollback_changes
    fi

    make_ro
    rm -rf "$script_dir" 2>/dev/null || true
    printf "%b" "$SHOW_CURSOR"
    exit "$rc"
}

cancel_remote() {
    warn "Cancellation requested. Attempting rollback..."
    exit 130
}

trap cancel_remote INT TERM
trap cleanup_remote EXIT

# ------------------------------------------------------------------------------
# Remote misc helpers
# ------------------------------------------------------------------------------

require_command() {
    local cmd="$1"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        err "Missing required command: $cmd"
        exit 1
    fi
}

service_exists() {
    local svc="$1"
    systemctl list-unit-files "$svc" >/dev/null 2>&1 || systemctl status "$svc" >/dev/null 2>&1
}

restart_service_if_exists() {
    local svc="$1"
    local fatal="${2:-false}"

    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: would restart $svc if present."
        return 0
    fi

    if service_exists "$svc"; then
        if ! systemctl restart "$svc" >/dev/null 2>&1; then
            warn "Could not restart $svc."
            if [ "$fatal" = true ]; then
                err "Fatal: service restart failed for $svc"
                return 1
            fi
        fi
    else
        warn "Service $svc not found; skipped restart."
    fi
}

enable_service_if_exists() {
    local svc="$1"

    if [ "$DRY_RUN" = true ]; then
        info "DRY RUN: would enable and start $svc if present."
        return 0
    fi

    if service_exists "$svc"; then
        systemctl enable --now "$svc" >/dev/null 2>&1 || warn "Could not enable $svc."
    else
        warn "Service $svc not found; skipped enable."
    fi
}

validate_kvmd_config() {
    local file="$1"

    if command -v kvmd >/dev/null 2>&1; then
        kvmd -M --config="$file" >/dev/null 2>&1
        return $?
    fi

    return 0
}

python_yaml_available() {
    command -v python3 >/dev/null 2>&1 || return 1

    python3 - <<'PY' >/dev/null 2>&1
import yaml
PY
}

config_is_empty_or_trivial() {
    local file="$1"

    if [ ! -f "$file" ]; then
        return 0
    fi

    local cleaned
    cleaned="$(grep -v '^[[:space:]]*#' "$file" | sed '/^[[:space:]]*$/d' || true)"

    case "$cleaned" in
        ""|"{}"|"kvmd:"|"kvmd: {}")
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

write_yaml_merge_helper() {
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    local helper="${script_dir}/pikvm-yaml-merge.py"

    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import sys
import yaml
from pathlib import Path

base_path = Path(sys.argv[1])
patch_path = Path(sys.argv[2])
out_path = Path(sys.argv[3])

def load_yaml(path):
    if not path.exists():
        return {}
    text = path.read_text()
    if not text.strip():
        return {}
    data = yaml.safe_load(text)
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise SystemExit(f"{path} does not contain a YAML mapping at top level")
    return data

def deep_merge(base, patch):
    for key, value in patch.items():
        if key in base and isinstance(base[key], dict) and isinstance(value, dict):
            deep_merge(base[key], value)
        else:
            base[key] = value
    return base

base = load_yaml(base_path)
patch = load_yaml(patch_path)
merged = deep_merge(base, patch)

out_path.write_text(
    yaml.safe_dump(
        merged,
        default_flow_style=False,
        sort_keys=False,
        indent=4,
    )
)
PY

    chmod +x "$helper"
}

write_yaml_delete_helper() {
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    local helper="${script_dir}/pikvm-yaml-delete.py"

    cat > "$helper" <<'PY'
#!/usr/bin/env python3
import sys
import yaml
from pathlib import Path

config_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
paths = sys.argv[3:]

def load_yaml(path):
    if not path.exists():
        return {}
    text = path.read_text()
    if not text.strip():
        return {}
    data = yaml.safe_load(text)
    if data is None:
        return {}
    if not isinstance(data, dict):
        raise SystemExit(f"{path} does not contain a YAML mapping at top level")
    return data

def delete_path(data, dotted):
    parts = dotted.split(".")
    cur = data
    parents = []

    for part in parts[:-1]:
        if not isinstance(cur, dict) or part not in cur:
            return
        parents.append((cur, part))
        cur = cur[part]

    if isinstance(cur, dict):
        cur.pop(parts[-1], None)

    # Prune empty dicts upward.
    for parent, key in reversed(parents):
        if isinstance(parent.get(key), dict) and not parent[key]:
            parent.pop(key, None)

data = load_yaml(config_path)

for path in paths:
    delete_path(data, path)

out_path.write_text(
    yaml.safe_dump(
        data if data else {},
        default_flow_style=False,
        sort_keys=False,
        indent=4,
    )
)
PY

    chmod +x "$helper"
}

print_patch_for_manual_merge() {
    local patch_file="$1"

    box_line ""
    box_line "Manual YAML patch to merge into:"
    box_line "  $CONFIG_FILE"
    box_line "----------------------------------------------------------------------"

    while IFS= read -r line; do
        box_line "  ${line:0:72}"
    done < "$patch_file"

    box_line "----------------------------------------------------------------------"
    box_line ""
    box_line "After manual merge, run:"
    box_line "  kvmd -M --config=$CONFIG_FILE"
    box_line "  systemctl restart kvmd"
}

manual_yaml_fallback() {
    local patch_file="$1"
    local saved_patch="/root/pikvm-optimizer-manual-patch.$(date +%Y%m%d-%H%M%S).yaml"

    warn "Python YAML module is missing."

    if [ "$DRY_RUN" = true ]; then
        warn "DRY RUN: existing override.yaml has content; would save a manual patch."
        print_patch_for_manual_merge "$patch_file"
        return 0
    fi

    make_rw
    cp "$patch_file" "$saved_patch"

    warn "Existing override.yaml has content, so I will not auto-edit it with sed."
    warn "Saved manual patch to: $saved_patch"

    print_patch_for_manual_merge "$patch_file"
}

fallback_write_clean_config() {
    local patch_file="$1"
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    local work_file="${script_dir}/pikvm-optimizer.clean.yaml"

    cp "$patch_file" "$work_file"

    if validate_kvmd_config "$work_file"; then
        if [ "$DRY_RUN" = true ]; then
            ok "DRY RUN: PyYAML missing, but config is empty/trivial; clean config validates."
            print_patch_for_manual_merge "$patch_file"
            return 0
        fi

        make_rw
        local atomic_tmp="${CONFIG_FILE}.tmp.$$"
        cp "$work_file" "$atomic_tmp"
        mv -f "$atomic_tmp" "$CONFIG_FILE"
        CONFIG_CHANGED=true
        ok "PyYAML missing, but config was empty/trivial; wrote clean override.yaml."
    else
        err "Fallback clean config failed kvmd validation; config not changed."
        return 1
    fi
}

merge_yaml_patch() {
    local patch_file="$1"
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    local work_file="${script_dir}/pikvm-optimizer.merged.yaml"

    if python_yaml_available; then
        write_yaml_merge_helper
        python3 "${script_dir}/pikvm-yaml-merge.py" "$CONFIG_FILE" "$patch_file" "$work_file"

        if validate_kvmd_config "$work_file"; then
            if [ "$DRY_RUN" = true ]; then
                ok "DRY RUN: merged config validates; would write $CONFIG_FILE."
                return 0
            fi

            make_rw
            local atomic_tmp="${CONFIG_FILE}.tmp.$$"
            cp "$work_file" "$atomic_tmp"
            mv -f "$atomic_tmp" "$CONFIG_FILE"
            CONFIG_CHANGED=true
            ok "Validated and applied config update."
        else
            err "kvmd validation failed; config not changed."
            if [ -n "$BACKUP_FILE" ]; then
                warn "Backup remains available: $BACKUP_FILE"
            fi
            return 1
        fi

        return 0
    fi

    if config_is_empty_or_trivial "$CONFIG_FILE"; then
        fallback_write_clean_config "$patch_file"
        return $?
    fi

    manual_yaml_fallback "$patch_file"
    return 0
}

delete_yaml_paths() {
    local script_dir
    script_dir="$(cd "$(dirname "$0")" && pwd)"
    local work_file="${script_dir}/pikvm-optimizer.deleted.yaml"

    if ! python_yaml_available; then
        warn "Python YAML module missing; cannot safely remove YAML keys."
        warn "Skipped YAML cleanup to avoid corrupting $CONFIG_FILE."
        return 0
    fi

    write_yaml_delete_helper
    python3 "${script_dir}/pikvm-yaml-delete.py" "$CONFIG_FILE" "$work_file" "$@"

    if validate_kvmd_config "$work_file"; then
        if [ "$DRY_RUN" = true ]; then
            ok "DRY RUN: YAML cleanup validates; would write $CONFIG_FILE."
            return 0
        fi

        make_rw
        local atomic_tmp="${CONFIG_FILE}.tmp.$$"
        cp "$work_file" "$atomic_tmp"
        mv -f "$atomic_tmp" "$CONFIG_FILE"
        CONFIG_CHANGED=true
        ok "YAML cleanup applied."
    else
        warn "YAML cleanup failed validation; config not changed."
    fi
}

backup_config() {
    if [ "$DRY_RUN" = true ]; then
        if [ -f "$CONFIG_FILE" ]; then
            BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
            ok "DRY RUN: would back up $CONFIG_FILE to $BACKUP_FILE."
        else
            ok "DRY RUN: would create $CONFIG_FILE with kvmd: {}."
        fi
        return 0
    fi

    make_rw
    mkdir -p "$(dirname "$CONFIG_FILE")"

    if [ -f "$CONFIG_FILE" ]; then
        BACKUP_FILE="${CONFIG_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$CONFIG_FILE" "$BACKUP_FILE"
        ok "Backup saved: $BACKUP_FILE"
    else
        printf "kvmd: {}\n" > "$CONFIG_FILE"
        ok "Created new $CONFIG_FILE."
    fi
}

# ------------------------------------------------------------------------------
# Interactive menus
# ------------------------------------------------------------------------------

apply_recommended_preset() {
    RUN_CORE=true
    RUN_MTU=false
    RUN_EDID=false
    RUN_SSL=false
    RUN_FAN=false
    RUN_WATCHDOG=false
    RUN_KEY=false
    RUN_INSTALL=false
    RUN_SUDO=false
}

apply_all_preset() {
    RUN_CORE=true
    RUN_MTU=true
    RUN_EDID=true
    RUN_SSL=true
    RUN_FAN=true
    RUN_WATCHDOG=true
    RUN_KEY=true
    RUN_INSTALL=true
    RUN_SUDO=false
}

apply_none_preset() {
    RUN_CORE=false
    RUN_MTU=false
    RUN_EDID=false
    RUN_SSL=false
    RUN_FAN=false
    RUN_WATCHDOG=false
    RUN_KEY=false
    RUN_INSTALL=false
    RUN_SUDO=false
}

interactive_module_menu() {
    local choice=""

    while true; do
        draw "MODULE SELECTION"
        box_line "Type numbers to toggle modules. Press Enter with no input to continue."
        box_line "Presets: a = all safe, n = none, r = recommended, u = uninstall menu"
        box_line "Other:   h = health check, b = restore backup, q = quit"
        box_line ""
        box_line "[1] [$(yn_marker "$RUN_CORE")] Core streamer/VNC settings"
        box_line "[2] [$(yn_marker "$RUN_MTU")] Tailscale MTU"
        box_line "[3] [$(yn_marker "$RUN_EDID")] Persistent HDMI EDID"
        box_line "[4] [$(yn_marker "$RUN_SSL")] Tailscale SSL certificate"
        box_line "[5] [$(yn_marker "$RUN_FAN")] Fan curve"
        box_line "[6] [$(yn_marker "$RUN_WATCHDOG")] Tailscale watchdog"
        box_line "[7] [$(yn_marker "$RUN_KEY")] Install SSH public key"
        box_line "[8] [$(yn_marker "$RUN_INSTALL")] Install optimizer permanently"
        box_line "[9] [$(yn_marker "$RUN_SUDO")] Restricted NOPASSWD sudo for installed optimizer"
        box_line ""
        close_box

        printf "Selection: "
        read -r choice

        case "$choice" in
            "")
                if [ "$RUN_SUDO" = true ] && [ "$RUN_INSTALL" != true ]; then
                    RUN_INSTALL=true
                    warn "Restricted sudo requires permanent install; install module enabled."
                    sleep 1
                fi
                return 0
                ;;
            1) toggle_bool RUN_CORE ;;
            2) toggle_bool RUN_MTU ;;
            3) toggle_bool RUN_EDID ;;
            4) toggle_bool RUN_SSL ;;
            5) toggle_bool RUN_FAN ;;
            6) toggle_bool RUN_WATCHDOG ;;
            7) toggle_bool RUN_KEY ;;
            8) toggle_bool RUN_INSTALL ;;
            9)
                toggle_bool RUN_SUDO
                if [ "$RUN_SUDO" = true ]; then
                    RUN_INSTALL=true
                fi
                ;;
            a|A) apply_all_preset ;;
            n|N) apply_none_preset ;;
            r|R) apply_recommended_preset ;;
            u|U)
                MODE="uninstall"
                return 0
                ;;
            h|H)
                MODE="health"
                return 0
                ;;
            b|B)
                MODE="restore"
                return 0
                ;;
            q|Q)
                exit 0
                ;;
            *)
                warn "Unknown selection: $choice"
                sleep 1
                ;;
        esac
    done
}

interactive_uninstall_menu() {
    local choice=""

    while true; do
        draw "UNINSTALL / CLEANUP"
        box_line "These remove optimizer-created or optimizer-managed changes."
        box_line "Type numbers to toggle. Press Enter with no input to continue."
        box_line "Presets: a = all cleanup, n = none, q = back"
        box_line ""
        box_line "[1] [$(yn_marker "$UN_CORE")] Remove optimizer core config keys"
        box_line "[2] [$(yn_marker "$UN_MTU")] Remove Tailscale MTU link file"
        box_line "[3] [$(yn_marker "$UN_EDID")] Remove EDID file and EDID config key"
        box_line "[4] [$(yn_marker "$UN_SSL")] Remove Tailscale SSL cert/key"
        box_line "[5] [$(yn_marker "$UN_FAN")] Restore latest fan backup if available"
        box_line "[6] [$(yn_marker "$UN_WATCHDOG")] Remove Tailscale watchdog"
        box_line "[7] [$(yn_marker "$UN_KEY")] Remove SSH public key from authorized_keys"
        box_line "[8] [$(yn_marker "$UN_INSTALL")] Remove permanent optimizer install"
        box_line "[9] [$(yn_marker "$UN_SUDO")] Remove restricted sudoers rule"
        box_line ""
        close_box

        printf "Selection: "
        read -r choice

        case "$choice" in
            "")
                return 0
                ;;
            1) toggle_bool UN_CORE ;;
            2) toggle_bool UN_MTU ;;
            3) toggle_bool UN_EDID ;;
            4) toggle_bool UN_SSL ;;
            5) toggle_bool UN_FAN ;;
            6) toggle_bool UN_WATCHDOG ;;
            7) toggle_bool UN_KEY ;;
            8) toggle_bool UN_INSTALL ;;
            9) toggle_bool UN_SUDO ;;
            a|A)
                UN_CORE=true
                UN_MTU=true
                UN_EDID=true
                UN_SSL=true
                UN_FAN=true
                UN_WATCHDOG=true
                UN_KEY=true
                UN_INSTALL=true
                UN_SUDO=true
                ;;
            n|N)
                UN_CORE=false
                UN_MTU=false
                UN_EDID=false
                UN_SSL=false
                UN_FAN=false
                UN_WATCHDOG=false
                UN_KEY=false
                UN_INSTALL=false
                UN_SUDO=false
                ;;
            q|Q)
                MODE="optimize"
                interactive_module_menu
                return 0
                ;;
            *)
                warn "Unknown selection: $choice"
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------------------------
# Optimizer modules
# ------------------------------------------------------------------------------

apply_core_config() {
    info "Applying core streamer/VNC settings..."

    local patch="/tmp/pikvm-optimizer.core.yaml"

    cat > "$patch" <<'EOF'
kvmd:
    streamer:
        gop: 0
        quality: 35
        h264_bitrate: 1500
        h264_boost: true
    vnc:
        mac_command_as_meta: true
        relative_scroll: true
EOF

    merge_yaml_patch "$patch"
}

apply_tailscale_mtu() {
    info "Configuring Tailscale MTU..."

    if ! command -v tailscale >/dev/null 2>&1; then
        warn "Tailscale not installed; skipped MTU."
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would write /etc/systemd/network/99-tailscale-mtu.link."
        ok "DRY RUN: would set tailscale0 MTU to 1280 if the interface exists."
        warn "Would not restart systemd-networkd automatically."
        return 0
    fi

    make_rw
    mkdir -p /etc/systemd/network

    if [ -f /etc/systemd/network/99-tailscale-mtu.link ]; then
        MTU_BACKUP_FILE="/etc/systemd/network/99-tailscale-mtu.link.bak.$(date +%Y%m%d-%H%M%S)"
        cp /etc/systemd/network/99-tailscale-mtu.link "$MTU_BACKUP_FILE"
        ok "Backed up existing MTU config to $MTU_BACKUP_FILE"
    fi

    cat > /etc/systemd/network/99-tailscale-mtu.link <<'EOF'
[Match]
OriginalName=tailscale0

[Link]
MTUBytes=1280
EOF

    MTU_CHANGED=true

    if ip link show tailscale0 >/dev/null 2>&1; then
        ip link set dev tailscale0 mtu 1280 || warn "Could not immediately set tailscale0 MTU."
    fi

    ok "Tailscale MTU config written."
    warn "Not restarting systemd-networkd automatically to avoid dropping SSH."
}

apply_edid() {
    info "Configuring persistent EDID..."

    local edid_source=""
    local edid_dest="/etc/kvmd/tc358743-edid.hex"
    local patch="/tmp/pikvm-optimizer.edid.yaml"

    if [ -n "$EDID_URL" ]; then
        edid_source="$EDID_URL"
    elif [ -n "$EDID_FILE" ]; then
        edid_source="$EDID_FILE"
    elif [ "$YES" = true ]; then
        warn "EDID source required for non-interactive mode; skipped EDID."
        return 0
    else
        printf "\nEnter EDID hex file URL or local path on PiKVM.\n"
        printf "Leave blank to skip EDID setup.\n"
        printf "EDID source: "
        read -r edid_source
    fi

    if [ -z "$edid_source" ]; then
        warn "No EDID source provided; skipped EDID."
        return 0
    fi

    cat > "$patch" <<EOF
kvmd:
    tc358743:
        edid: "$edid_dest"
EOF

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would install EDID to $edid_dest."
        merge_yaml_patch "$patch"
        return 0
    fi

    make_rw

    if [ -f "$edid_dest" ]; then
        EDID_BACKUP_FILE="${edid_dest}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$edid_dest" "$EDID_BACKUP_FILE"
        ok "Backed up existing EDID to $EDID_BACKUP_FILE"
    fi

    if [[ "$edid_source" =~ ^https?:// ]]; then
        if [[ "$edid_source" =~ ^http:// ]]; then
            warn "HTTP not allowed for EDID downloads; use HTTPS."
            return 0
        fi

        if ! command -v curl >/dev/null 2>&1; then
            warn "curl not installed; cannot download EDID."
            return 0
        fi

        local edid_tmp
        edid_tmp="$(mktemp /tmp/pikvm-edid.XXXXXXXXXX)"

        if ! curl -fsSL --max-time 30 --max-filesize 1048576 -o "$edid_tmp" "$edid_source"; then
            warn "Failed to download EDID."
            rm -f "$edid_tmp"
            return 0
        fi

        if ! file "$edid_tmp" | grep -qi "text"; then
            warn "Downloaded EDID is not a text file; rejected."
            rm -f "$edid_tmp"
            return 0
        fi

        if [ "$(wc -c < "$edid_tmp" | tr -d ' ')" -gt 65536 ]; then
            warn "Downloaded EDID is too large (>64KB); rejected."
            rm -f "$edid_tmp"
            return 0
        fi

        mv "$edid_tmp" "$edid_dest"
        EDID_CHANGED=true
    else
        if [ ! -f "$edid_source" ]; then
            warn "EDID source file not found: $edid_source"
            return 0
        fi

        cp "$edid_source" "$edid_dest"
        EDID_CHANGED=true
    fi

    merge_yaml_patch "$patch"
    ok "EDID file installed at $edid_dest."
}

apply_tailscale_ssl() {
    info "Configuring Tailscale SSL certificate..."

    if ! command -v tailscale >/dev/null 2>&1; then
        warn "Tailscale not installed; skipped SSL."
        return 0
    fi

    if ! tailscale status >/dev/null 2>&1; then
        warn "Tailscale not running/authenticated; skipped SSL."
        return 0
    fi

    local ts_dns=""
    ts_dns="$(tailscale status --json 2>/dev/null | awk -F'"' '/"DNSName":/ { print $4; exit }' || true)"

    if [ -z "$ts_dns" ]; then
        warn "Could not determine Tailscale DNS name."
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would request Tailscale cert for $ts_dns."
        ok "DRY RUN: would write cert/key under /etc/kvmd/nginx/ssl."
        ok "DRY RUN: would restart kvmd-nginx.service if present."
        return 0
    fi

    make_rw
    mkdir -p /etc/kvmd/nginx/ssl

    if [ -f /etc/kvmd/nginx/ssl/server.crt ] || [ -f /etc/kvmd/nginx/ssl/server.key ]; then
        SSL_BACKUP_DIR="/etc/kvmd/nginx/ssl.bak.$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$SSL_BACKUP_DIR"
        [ -f /etc/kvmd/nginx/ssl/server.crt ] && cp /etc/kvmd/nginx/ssl/server.crt "$SSL_BACKUP_DIR/"
        [ -f /etc/kvmd/nginx/ssl/server.key ] && cp /etc/kvmd/nginx/ssl/server.key "$SSL_BACKUP_DIR/"
        ok "Backed up existing SSL certs to $SSL_BACKUP_DIR"
    fi

    if tailscale cert \
        --cert-file /etc/kvmd/nginx/ssl/server.crt \
        --key-file /etc/kvmd/nginx/ssl/server.key \
        "$ts_dns" >/dev/null 2>&1; then

        SSL_CHANGED=true
        restart_service_if_exists kvmd-nginx.service
        ok "Tailscale cert deployed for $ts_dns."
    else
        warn "tailscale cert failed. Check Tailscale HTTPS/cert permissions."
    fi
}

apply_fan_curve() {
    info "Configuring fan curve..."

    if [ ! -f /etc/conf.d/kvmd-fan ]; then
        warn "/etc/conf.d/kvmd-fan not found; skipped fan curve."
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would back up and rewrite /etc/conf.d/kvmd-fan."
        ok "DRY RUN: would restart kvmd-fan.service if present."
        return 0
    fi

    make_rw

    FAN_BACKUP_FILE="/etc/conf.d/kvmd-fan.bak.$(date +%Y%m%d-%H%M%S)"
    cp /etc/conf.d/kvmd-fan "$FAN_BACKUP_FILE"

    cat > /etc/conf.d/kvmd-fan <<'EOF'
KVMD_FAN_ARGS="--speed-idle 40 --speed-low 50 --temp-low 60 --speed-high 100 --temp-high 75"
EOF

    FAN_CHANGED=true

    restart_service_if_exists kvmd-fan.service
    ok "Fan curve updated."
}

enable_oled_if_present() {
    if command -v kvmd-oled >/dev/null 2>&1 || [ -f /usr/bin/kvmd-oled ]; then
        info "Enabling OLED service..."

        if [ "$DRY_RUN" = true ]; then
            ok "DRY RUN: would enable kvmd-oled.service if present."
            return 0
        fi

        make_rw
        enable_service_if_exists kvmd-oled.service
        ok "OLED enable attempted."
    fi
}

apply_tailscale_watchdog() {
    info "Installing Tailscale watchdog..."

    if ! command -v tailscale >/dev/null 2>&1; then
        warn "Tailscale not installed; skipped watchdog."
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would install /usr/local/bin/pikvm-tailscale-watchdog.sh."
        ok "DRY RUN: would install pikvm-tailscale-watchdog.service."
        ok "DRY RUN: would install and enable pikvm-tailscale-watchdog.timer."
        return 0
    fi

    make_rw

    if [ -f /usr/local/bin/pikvm-tailscale-watchdog.sh ]; then
        WATCHDOG_BACKUP_DIR="/usr/local/bin/pikvm-tailscale-watchdog.sh.bak.$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$WATCHDOG_BACKUP_DIR"
        cp /usr/local/bin/pikvm-tailscale-watchdog.sh "$WATCHDOG_BACKUP_DIR/"
        ok "Backed up existing watchdog script to $WATCHDOG_BACKUP_DIR"
    fi

    cat > /usr/local/bin/pikvm-tailscale-watchdog.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if ! command -v tailscale >/dev/null 2>&1; then
    exit 0
fi

if ! command -v systemctl >/dev/null 2>&1; then
    exit 0
fi

if ! tailscale status >/dev/null 2>&1; then
    systemctl restart tailscaled.service >/dev/null 2>&1 || true
fi
EOF

    chmod +x /usr/local/bin/pikvm-tailscale-watchdog.sh

    if [ -f /etc/systemd/system/pikvm-tailscale-watchdog.service ] || [ -f /etc/systemd/system/pikvm-tailscale-watchdog.timer ]; then
        WATCHDOG_BACKUP_DIR="/etc/systemd/system/pikvm-tailscale-watchdog.bak.$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$WATCHDOG_BACKUP_DIR"
        [ -f /etc/systemd/system/pikvm-tailscale-watchdog.service ] && cp /etc/systemd/system/pikvm-tailscale-watchdog.service "$WATCHDOG_BACKUP_DIR/"
        [ -f /etc/systemd/system/pikvm-tailscale-watchdog.timer ] && cp /etc/systemd/system/pikvm-tailscale-watchdog.timer "$WATCHDOG_BACKUP_DIR/"
        ok "Backed up existing watchdog service/timer to $WATCHDOG_BACKUP_DIR"
    fi

    cat > /etc/systemd/system/pikvm-tailscale-watchdog.service <<'EOF'
[Unit]
Description=PiKVM Tailscale watchdog
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/pikvm-tailscale-watchdog.sh
EOF

    cat > /etc/systemd/system/pikvm-tailscale-watchdog.timer <<'EOF'
[Unit]
Description=Run PiKVM Tailscale watchdog every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Unit=pikvm-tailscale-watchdog.service

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable --now pikvm-tailscale-watchdog.timer >/dev/null 2>&1
    WATCHDOG_CHANGED=true

    ok "Tailscale watchdog installed."
}

apply_ssh_key() {
    info "Installing SSH public key..."

    local target_user=""
    local pubkey=""
    local home_dir=""

    if [ -n "$PUBKEY_CONTENT" ]; then
        pubkey="$PUBKEY_CONTENT"
        target_user="root"
    elif [ "$YES" = true ]; then
        warn "SSH key install requires --pubkey-file for non-interactive mode; skipped."
        return 0
    else
        printf "\nInstall key for which user? [root]: "
        read -r target_user
        target_user="${target_user:-root}"

        printf "Paste SSH public key, usually starting with ssh-ed25519 or ssh-rsa:\n"
        read -r pubkey
    fi

    if [ -z "$pubkey" ]; then
        warn "No public key provided; skipped SSH key install."
        return 0
    fi

    case "$pubkey" in
        ssh-ed25519\ *|ssh-rsa\ *|ecdsa-sha2-nistp256\ *|ecdsa-sha2-nistp384\ *|ecdsa-sha2-nistp521\ *)
            ;;
        *)
            warn "That does not look like a standard SSH public key; skipped."
            return 0
            ;;
    esac

    if [ "$target_user" = "root" ]; then
        home_dir="/root"
    else
        home_dir="$(getent passwd "$target_user" | cut -d: -f6 || true)"
    fi

    if [ -z "$home_dir" ] || [ ! -d "$home_dir" ]; then
        warn "Could not find home directory for user: $target_user"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would add public key to $home_dir/.ssh/authorized_keys."
        return 0
    fi

    make_rw

    local ssh_dir="$home_dir/.ssh"
    local auth_file="$ssh_dir/authorized_keys"

    if [ -L "$ssh_dir" ] || [ -L "$auth_file" ]; then
        warn "Refusing to modify symlinked .ssh directory or authorized_keys; security risk."
        return 0
    fi

    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    chown "$target_user:$target_user" "$ssh_dir" 2>/dev/null || true

    KEY_TARGET_FILE="$auth_file"
    touch "$KEY_TARGET_FILE"
    chmod 600 "$KEY_TARGET_FILE"
    chown "$target_user:$target_user" "$KEY_TARGET_FILE" 2>/dev/null || true

    if ! grep -qxF "$pubkey" "$KEY_TARGET_FILE"; then
        printf "%s\n" "$pubkey" >> "$KEY_TARGET_FILE"
        KEY_CHANGED=true
        KEY_INSTALLED_LINE="$pubkey"
        ok "SSH public key installed for $target_user."
    else
        ok "SSH public key already present for $target_user."
    fi

    if command -v chown >/dev/null 2>&1; then
        chown -R "$target_user:$target_user" "$home_dir/.ssh" 2>/dev/null || true
    fi
}

install_optimizer_permanently() {
    info "Installing optimizer permanently..."

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would install current remote optimizer to $INSTALL_PATH."
        return 0
    fi

    make_rw
    mkdir -p "$(dirname "$INSTALL_PATH")"

    if [ -f "$INSTALL_PATH" ]; then
        INSTALL_BACKUP_FILE="${INSTALL_PATH}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$INSTALL_PATH" "$INSTALL_BACKUP_FILE"
    fi

    cp "$0" "$INSTALL_PATH"
    chmod 755 "$INSTALL_PATH"
    INSTALL_CHANGED=true

    ok "Optimizer installed permanently at $INSTALL_PATH."
}

apply_restricted_sudo() {
    info "Configuring restricted passwordless sudo..."

    local sudo_user=""

    if [ -n "$SUDO_USER" ]; then
        sudo_user="$SUDO_USER"
    elif [ "$YES" = true ]; then
        warn "Restricted sudo requires --sudo-user for non-interactive mode; skipped."
        return 0
    else
        printf "\nNon-root user to grant restricted sudo access: "
        read -r sudo_user
    fi

    if [ -z "$sudo_user" ] || [ "$sudo_user" = "root" ]; then
        warn "Invalid or root user; skipped sudoers setup."
        return 0
    fi

    if ! id "$sudo_user" >/dev/null 2>&1; then
        warn "User does not exist: $sudo_user"
        return 0
    fi

    if ! command -v visudo >/dev/null 2>&1; then
        warn "visudo not found; refusing to edit sudoers."
        return 0
    fi

    if [ ! -f "$INSTALL_PATH" ] && [ "$RUN_INSTALL" != true ]; then
        warn "Permanent optimizer install not found; sudoers rule skipped."
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would create /etc/sudoers.d/pikvm-optimizer-$sudo_user."
        box_line "Would allow:"
        box_line "  $sudo_user ALL=(root) NOPASSWD: $INSTALL_PATH"
        return 0
    fi

    make_rw
    mkdir -p /etc/sudoers.d

    SUDOERS_FILE="/etc/sudoers.d/pikvm-optimizer-$sudo_user"

    cat > "${SUDOERS_FILE}.tmp" <<EOF
$sudo_user ALL=(root) NOPASSWD: $INSTALL_PATH
EOF

    chmod 440 "${SUDOERS_FILE}.tmp"

    if visudo -cf "${SUDOERS_FILE}.tmp" >/dev/null 2>&1; then
        mv "${SUDOERS_FILE}.tmp" "$SUDOERS_FILE"
        chmod 440 "$SUDOERS_FILE"
        SUDOERS_CHANGED=true
        ok "Restricted sudoers rule installed for $sudo_user."
    else
        rm -f "${SUDOERS_FILE}.tmp"
        warn "sudoers validation failed; no sudoers change made."
    fi
}

# ------------------------------------------------------------------------------
# Uninstall / restore / health
# ------------------------------------------------------------------------------

uninstall_core_config() {
    info "Removing optimizer-managed core YAML keys..."
    delete_yaml_paths \
        kvmd.streamer.gop \
        kvmd.streamer.quality \
        kvmd.streamer.h264_bitrate \
        kvmd.streamer.h264_boost \
        kvmd.vnc.mac_command_as_meta \
        kvmd.vnc.relative_scroll
}

uninstall_mtu() {
    info "Removing Tailscale MTU link file..."

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would remove /etc/systemd/network/99-tailscale-mtu.link."
        return 0
    fi

    make_rw
    rm -f /etc/systemd/network/99-tailscale-mtu.link
    ok "Removed Tailscale MTU link file."
}

uninstall_edid() {
    info "Removing EDID file and config key..."

    delete_yaml_paths kvmd.tc358743.edid

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would remove /etc/kvmd/tc358743-edid.hex."
        return 0
    fi

    make_rw
    rm -f /etc/kvmd/tc358743-edid.hex
    ok "Removed EDID file."
}

uninstall_ssl() {
    info "Removing Tailscale SSL cert/key..."

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would remove /etc/kvmd/nginx/ssl/server.crt and server.key."
        return 0
    fi

    make_rw
    rm -f /etc/kvmd/nginx/ssl/server.crt /etc/kvmd/nginx/ssl/server.key
    restart_service_if_exists kvmd-nginx.service
    ok "Removed SSL cert/key."
}

uninstall_fan() {
    info "Restoring latest fan backup..."

    local latest_backup=""
    latest_backup="$(ls -t /etc/conf.d/kvmd-fan.bak.* 2>/dev/null | head -n 1 || true)"

    if [ -z "$latest_backup" ]; then
        warn "No fan backup found."
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would restore fan config from $latest_backup."
        return 0
    fi

    make_rw
    cp "$latest_backup" /etc/conf.d/kvmd-fan
    restart_service_if_exists kvmd-fan.service
    ok "Restored fan config from $latest_backup."
}

uninstall_watchdog() {
    info "Removing Tailscale watchdog..."

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would remove watchdog service, timer, and script."
        return 0
    fi

    make_rw
    systemctl disable --now pikvm-tailscale-watchdog.timer >/dev/null 2>&1 || true
    rm -f \
        /usr/local/bin/pikvm-tailscale-watchdog.sh \
        /etc/systemd/system/pikvm-tailscale-watchdog.service \
        /etc/systemd/system/pikvm-tailscale-watchdog.timer
    systemctl daemon-reload >/dev/null 2>&1 || true
    ok "Removed Tailscale watchdog."
}

uninstall_ssh_key() {
    info "Removing SSH public key..."

    local target_user=""
    local pubkey=""
    local home_dir=""
    local auth_file=""

    if [ "$YES" = true ]; then
        warn "SSH key removal requires interactive public key input; skipped in --yes mode."
        return 0
    fi

    printf "\nRemove key from which user? [root]: "
    read -r target_user
    target_user="${target_user:-root}"

    printf "Paste exact SSH public key to remove:\n"
    read -r pubkey

    if [ -z "$pubkey" ]; then
        warn "No public key provided; skipped removal."
        return 0
    fi

    if [ "$target_user" = "root" ]; then
        home_dir="/root"
    else
        home_dir="$(getent passwd "$target_user" | cut -d: -f6 || true)"
    fi

    auth_file="$home_dir/.ssh/authorized_keys"

    if [ ! -f "$auth_file" ]; then
        warn "authorized_keys not found for $target_user."
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would remove matching key from $auth_file."
        return 0
    fi

    make_rw
    grep -vxF "$pubkey" "$auth_file" > "${auth_file}.tmp" || true
    mv "${auth_file}.tmp" "$auth_file"
    chmod 600 "$auth_file" || true
    ok "Removed matching SSH key if present."
}

uninstall_permanent_install() {
    info "Removing permanent optimizer install..."

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would remove $INSTALL_PATH."
        return 0
    fi

    make_rw
    rm -f "$INSTALL_PATH"
    ok "Removed $INSTALL_PATH."
}

uninstall_sudoers() {
    info "Removing restricted sudoers rule..."

    local sudo_user=""
    local file=""

    if [ "$YES" = true ]; then
        warn "Sudoers cleanup requires interactive username input; skipped in --yes mode."
        return 0
    fi

    printf "\nNon-root user whose optimizer sudoers rule should be removed: "
    read -r sudo_user

    if [ -z "$sudo_user" ] || [ "$sudo_user" = "root" ]; then
        warn "Invalid or root user; skipped sudoers cleanup."
        return 0
    fi

    file="/etc/sudoers.d/pikvm-optimizer-$sudo_user"

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would remove $file."
        return 0
    fi

    make_rw
    rm -f "$file"
    ok "Removed sudoers rule if present: $file"
}

restore_from_backup() {
    draw "RESTORE CONFIG BACKUP"

    local backups=()
    local i=0
    local choice=""
    local selected=""

    while IFS= read -r line; do
        backups+=("$line")
    done < <(ls -t /etc/kvmd/override.yaml.bak.* 2>/dev/null || true)

    if [ "${#backups[@]}" -eq 0 ]; then
        warn "No override.yaml backups found."
        close_box
        return 0
    fi

    box_line "Available backups:"
    box_line ""

    for i in "${!backups[@]}"; do
        box_line "[$((i + 1))] ${backups[$i]}"
    done

    box_line ""
    close_box

    if [ "$YES" = true ]; then
        warn "Restore requires interactive selection; skipped in --yes mode."
        return 0
    fi

    printf "Backup number to restore, or blank to cancel: "
    read -r choice

    if [ -z "$choice" ]; then
        warn "Restore cancelled."
        return 0
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
        warn "Invalid selection."
        return 0
    fi

    if [ "$choice" -lt 1 ] || [ "$choice" -gt "${#backups[@]}" ]; then
        warn "Selection out of range."
        return 0
    fi

    selected="${backups[$((choice - 1))]}"

    if ! validate_kvmd_config "$selected"; then
        warn "Selected backup failed kvmd validation; not restoring."
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would restore $selected to $CONFIG_FILE."
        return 0
    fi

    make_rw
    cp "$CONFIG_FILE" "${CONFIG_FILE}.pre-restore.$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
    local atomic_tmp="${CONFIG_FILE}.tmp.$$"
    cp "$selected" "$atomic_tmp"
    mv -f "$atomic_tmp" "$CONFIG_FILE"
    restart_service_if_exists kvmd.service true
    ok "Restored $CONFIG_FILE from $selected."
}

health_check() {
    draw "HEALTH CHECK"

    info "PiKVM optimizer health report"

    if [ "$DRY_RUN" = true ]; then
        warn "Dry-run mode active."
    fi

    if [ -f "$CONFIG_FILE" ]; then
        ok "Config exists: $CONFIG_FILE"
        if validate_kvmd_config "$CONFIG_FILE"; then
            ok "kvmd config validation passed."
        else
            warn "kvmd config validation failed."
        fi
    else
        warn "Config missing: $CONFIG_FILE"
    fi

    if python_yaml_available; then
        ok "Python YAML support available."
    else
        warn "Python YAML support missing."
    fi

    for svc in kvmd.service kvmd-nginx.service kvmd-vnc.service tailscaled.service kvmd-fan.service kvmd-oled.service pikvm-tailscale-watchdog.timer; do
        if service_exists "$svc"; then
            if systemctl is-active "$svc" >/dev/null 2>&1; then
                ok "$svc is active."
            else
                warn "$svc exists but is not active."
            fi
        else
            info "$svc not present on this system."
        fi
    done

    if command -v tailscale >/dev/null 2>&1; then
        if tailscale status >/dev/null 2>&1; then
            ok "Tailscale appears running/authenticated."
        else
            warn "Tailscale command exists but status failed."
        fi
    else
        info "Tailscale not installed."
    fi

    if [ -f /etc/systemd/network/99-tailscale-mtu.link ]; then
        ok "Tailscale MTU link file exists."
    else
        info "Tailscale MTU link file not installed."
    fi

    if [ -f /usr/local/bin/pikvm-tailscale-watchdog.sh ]; then
        ok "Tailscale watchdog script exists."
    else
        info "Tailscale watchdog script not installed."
    fi

    if [ -f "$INSTALL_PATH" ]; then
        ok "Permanent optimizer install exists: $INSTALL_PATH"
    else
        info "Permanent optimizer install not present."
    fi

    if [ -d /etc/sudoers.d ]; then
        local sudo_count
        sudo_count="$(ls /etc/sudoers.d/pikvm-optimizer-* 2>/dev/null | wc -l | tr -d ' ')"
        info "Restricted optimizer sudoers files: $sudo_count"
    fi

    if [ -f "$LOG_FILE" ]; then
        info "Log file exists: $LOG_FILE"
    else
        info "Log file not created yet."
    fi

    close_box
}

final_restart() {
    info "Reloading systemd and restarting PiKVM services..."

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would run systemctl daemon-reload."
        ok "DRY RUN: would restart kvmd.service if present."
        if [ "${RUN_SSL:-false}" = true ]; then
            ok "DRY RUN: would restart kvmd-nginx.service if present."
        fi
        return 0
    fi

    systemctl daemon-reload >/dev/null 2>&1 || true
    restart_service_if_exists kvmd.service true

    if [ "${RUN_SSL:-false}" = true ]; then
        restart_service_if_exists kvmd-nginx.service
    fi

    ok "Service refresh complete."
}

rollback_hint() {
    if [ -n "$BACKUP_FILE" ]; then
        box_line "Rollback command:"
        box_line "  rw && cp '$BACKUP_FILE' '$CONFIG_FILE' && systemctl restart kvmd && ro"
    fi
}

# ------------------------------------------------------------------------------
# Remote main
# ------------------------------------------------------------------------------

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    printf "%bERROR:%b Run this as root on PiKVM.\n" "$R" "$RESET"
    exit 1
fi

printf "%b" "$HIDE_CURSOR"

draw "INITIALIZATION"

if [ "$DRY_RUN" = true ]; then
    warn "DRY RUN ENABLED: persistent changes will be skipped where possible."
fi

info "Press Ctrl-C to cancel; rollback will be attempted for changes already made."
info "Verifying PiKVM environment..."

require_command systemctl
require_command awk
require_command sed
require_command grep
require_command cp
require_command mkdir

if command -v kvmd >/dev/null 2>&1; then
    ok "kvmd command detected."
else
    warn "kvmd command not found; config validation will be limited."
fi

if python_yaml_available; then
    ok "Python YAML support detected."
else
    warn "Python YAML support not detected; safe fallback mode enabled."
    warn "Will not sed-edit existing non-trivial YAML."
fi

info "Target config: $CONFIG_FILE"
info "Log file: $LOG_FILE"

if [ "$MODE" = "health" ]; then
    close_box
    health_check
    SUCCESS=true
    make_ro
    exit 0
fi

if [ "$MODE" = "restore" ]; then
    close_box
    restore_from_backup
    SUCCESS=true
    make_ro
    exit 0
fi

backup_config
close_box
sleep 0.5

if [ "$MODE" = "uninstall" ]; then
    if [ "$YES" != true ]; then
        interactive_uninstall_menu
    fi

    draw "UNINSTALL / CLEANUP"

    if [ "$UN_CORE" = true ]; then uninstall_core_config; fi
    if [ "$UN_MTU" = true ]; then uninstall_mtu; fi
    if [ "$UN_EDID" = true ]; then uninstall_edid; fi
    if [ "$UN_SSL" = true ]; then uninstall_ssl; fi
    if [ "$UN_FAN" = true ]; then uninstall_fan; fi
    if [ "$UN_WATCHDOG" = true ]; then uninstall_watchdog; fi
    if [ "$UN_KEY" = true ]; then uninstall_ssh_key; fi
    if [ "$UN_INSTALL" = true ]; then uninstall_permanent_install; fi
    if [ "$UN_SUDO" = true ]; then uninstall_sudoers; fi

    final_restart

    SUCCESS=true
    make_ro

    box_line ""
    box_line_color "$G" "[DONE] Uninstall/cleanup finished."
    rollback_hint
    close_box
    exit 0
fi

if [ "$YES" != true ]; then
    interactive_module_menu
fi

if [ "$MODE" = "uninstall" ]; then
    interactive_uninstall_menu
    draw "UNINSTALL / CLEANUP"

    if [ "$UN_CORE" = true ]; then uninstall_core_config; fi
    if [ "$UN_MTU" = true ]; then uninstall_mtu; fi
    if [ "$UN_EDID" = true ]; then uninstall_edid; fi
    if [ "$UN_SSL" = true ]; then uninstall_ssl; fi
    if [ "$UN_FAN" = true ]; then uninstall_fan; fi
    if [ "$UN_WATCHDOG" = true ]; then uninstall_watchdog; fi
    if [ "$UN_KEY" = true ]; then uninstall_ssh_key; fi
    if [ "$UN_INSTALL" = true ]; then uninstall_permanent_install; fi
    if [ "$UN_SUDO" = true ]; then uninstall_sudoers; fi

    final_restart
    SUCCESS=true
    make_ro

    box_line ""
    box_line_color "$G" "[DONE] Uninstall/cleanup finished."
    rollback_hint
    close_box
    exit 0
fi

if [ "$MODE" = "health" ]; then
    health_check
    SUCCESS=true
    make_ro
    exit 0
fi

if [ "$MODE" = "restore" ]; then
    restore_from_backup
    SUCCESS=true
    make_ro
    exit 0
fi

draw "EXECUTING OPTIMIZATION PACKS"

if [ "$RUN_CORE" = true ]; then apply_core_config; fi
if [ "$RUN_MTU" = true ]; then apply_tailscale_mtu; fi
if [ "$RUN_EDID" = true ]; then apply_edid; fi
if [ "$RUN_SSL" = true ]; then apply_tailscale_ssl; fi
if [ "$RUN_FAN" = true ]; then apply_fan_curve; fi

enable_oled_if_present

if [ "$RUN_WATCHDOG" = true ]; then apply_tailscale_watchdog; fi
if [ "$RUN_KEY" = true ]; then apply_ssh_key; fi
if [ "$RUN_INSTALL" = true ]; then install_optimizer_permanently; fi
if [ "$RUN_SUDO" = true ]; then apply_restricted_sudo; fi

final_restart
health_check

SUCCESS=true
make_ro

box_line ""

if [ "$DRY_RUN" = true ]; then
    box_line_color "$G" "[DONE] Dry run finished. No persistent changes were intentionally made."
else
    box_line_color "$G" "[DONE] Optimization routine finished."
fi

if [ -n "$BACKUP_FILE" ]; then
    box_line "Backup file: $BACKUP_FILE"
fi

rollback_hint
close_box

printf "%b" "$SHOW_CURSOR"
exit 0
PIKVM_REMOTE_SCRIPT

printf "%bRunning optimizer remotely...%b\n\n" "$DIM" "$RESET"

REMOTE_ARG_STRING="$(quote_args "${REMOTE_ARGS[@]}")"

if [ "$PI_USER" = "root" ]; then
    ssh -t "${SSH_OPTS[@]}" "${PI_USER}@${PI_HOST}" \
        "'$REMOTE_DEST' $REMOTE_ARG_STRING; rc=\$?; rm -f '$REMOTE_DEST'; exit \$rc"
else
    ssh -t "${SSH_OPTS[@]}" "${PI_USER}@${PI_HOST}" \
        "sudo '$REMOTE_DEST' $REMOTE_ARG_STRING; rc=\$?; rm -f '$REMOTE_DEST'; exit \$rc"
fi

trap - INT TERM
cleanup_local