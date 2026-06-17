#!/usr/bin/env bash
# ==============================================================================
# PiKVM Optimizer
# Single-file macOS/Linux launcher with embedded PiKVM remote optimizer.
# Version: 1.4.2
# ==============================================================================

set -euo pipefail

VERSION="1.4.2"

# ------------------------------------------------------------------------------
# Local launcher options
# ------------------------------------------------------------------------------

DRY_RUN=false
LOCAL_YES=false
PI_HOST=""
PI_USER=""
SSH_KEY=""
PUBKEY_FILE=""
SUDO_USER=""
EDID_URL=""
EDID_FILE=""
PRINT_REMOTE=false
REMOTE_ARGS=()

CONFIG_FILE=""
WRITE_CONFIG_TEMPLATE=""

require_arg() {
    local opt="$1"
    local val="${2:-}"
    if [ -z "$val" ]; then
        printf "Error: %s requires a value\n" "$opt" >&2
        exit 1
    fi
}

write_config_template() {
    local target="$1"
    local tmp=""

    if [ "$target" != "-" ]; then
        tmp="$(dirname "$target")"
        if [ ! -d "$tmp" ]; then
            printf "Error: parent directory does not exist: %s\n" "$tmp" >&2
            exit 1
        fi
    fi

    if [ "$target" = "-" ]; then
        cat
    else
        cat > "$target"
        printf "Wrote config template: %s\n" "$target"
    fi <<'EOF'
# PiKVM Optimizer declarative config template.
# Omitted keys use the script defaults. Explicit CLI flags override this file.
# Do not store passwords, TOTP secrets, WiFi passphrases, or private keys here.

connection:
  host: pikvm.local
  user: root
  # identity: ~/.ssh/id_ed25519

run:
  dry_run: true
  non_interactive: false
  # health_check: false
  # uninstall: false
  # restore: false
  # reboot: false
  # no_color: false

# One of: recommended, all, none. Leave blank/null for the interactive default.
preset: recommended

modules:
  core: true
  mtu: false
  edid: false
  ssl: false
  fan: false
  watchdog: false
  quality_cap: false
  keepalive: false
  tailscale_diag: false
  tailscale_setup: false
  tailscale_crash_fix: false
  wifi: false
  root_password: false
  first_run: false
  two_fa: false
  msd_bios_fix: true
  usb_preset: false
  usb_extra: false
  msd_storage: false
  msd_drives: false
  override_d: false
  key: false
  install: false

edid:
  # url: https://example.com/edid.hex
  # file: /path/to/edid.hex

ssh:
  # Public key file to install when modules.key is true.
  # pubkey_file: ~/.ssh/id_ed25519.pub

wifi:
  # Non-secret defaults for the interactive WiFi wizard.
  # ssid: MyNetwork
  country: US
  # ap_ssid: PiKVM-setup
  #   Fallback AP: hotspot PiKVM creates when client WiFi is unavailable.
EOF
}

config_to_args() {
    local config_path="$1"

    if [ ! -f "$config_path" ]; then
        printf "Error: config file not found: %s\n" "$config_path" >&2
        exit 1
    fi

    python3 - "$config_path" <<'PY'
import sys

try:
    import yaml
except Exception:
    print("Error: --config requires Python PyYAML on the launcher machine", file=sys.stderr)
    sys.exit(1)

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

if not isinstance(data, dict):
    print("Error: config root must be a YAML mapping", file=sys.stderr)
    sys.exit(1)

args = []

def section(name):
    value = data.get(name) or {}
    if not isinstance(value, dict):
        print(f"Error: config section '{name}' must be a mapping", file=sys.stderr)
        sys.exit(1)
    return value

def add_pair(flag, value):
    if value is not None and value != "":
        args.extend([flag, str(value)])

def add_bool(flag, value):
    if value is True:
        args.append(flag)
    elif value not in (False, None):
        print(f"Error: {flag} must be true or false", file=sys.stderr)
        sys.exit(1)

conn = section("connection")
add_pair("--host", conn.get("host"))
add_pair("--user", conn.get("user"))
add_pair("--identity", conn.get("identity"))

run = section("run")
run_bool_flags = [
    ("dry_run", "--dry-run"),
    ("non_interactive", "--yes"),
    ("health_check", "--health-check"),
    ("uninstall", "--uninstall"),
    ("restore", "--restore"),
    ("reboot", "--reboot"),
    ("no_color", "--no-color"),
]
for key, flag in run_bool_flags:
    value = run.get(key)
    if key == "non_interactive":
        value = run.get("non_interactive", run.get("yes", run.get(True)))
    add_bool(flag, value)

preset = data.get("preset")
if preset not in (None, ""):
    preset_map = {"recommended": "--recommended", "all": "--all", "none": "--none"}
    if preset not in preset_map:
        print("Error: preset must be recommended, all, none, or blank", file=sys.stderr)
        sys.exit(1)
    args.append(preset_map[preset])

modules = section("modules")
module_flags = {
    "core": "--core",
    "mtu": "--mtu",
    "edid": "--edid",
    "ssl": "--ssl",
    "fan": "--fan",
    "watchdog": "--watchdog",
    "quality_cap": "--quality-cap",
    "keepalive": "--keepalive",
    "tailscale_diag": "--tailscale-diag",
    "tailscale_setup": "--tailscale-setup",
    "tailscale_crash_fix": "--tailscale-crash-fix",
    "wifi": "--wifi",
    "root_password": "--root-password",
    "first_run": "--first-run",
    "two_fa": "--2fa",
    "msd_bios_fix": "--msd-bios-fix",
    "usb_preset": "--usb-preset",
    "usb_extra": "--usb-extra",
    "msd_storage": "--msd-storage",
    "msd_drives": "--msd-drives",
    "override_d": "--override-d",
    "key": "--key",
    "install": "--install",
}
for key in modules:
    if key not in module_flags:
        print(f"Error: unknown module key: {key}", file=sys.stderr)
        sys.exit(1)
for key, flag in module_flags.items():
    value = modules.get(key)
    if key == "core" and value is False:
        args.append("--no-core")
    else:
        add_bool(flag, value)

edid = section("edid")
add_pair("--edid-url", edid.get("url"))
add_pair("--edid-file", edid.get("file"))

ssh = section("ssh")
add_pair("--pubkey-file", ssh.get("pubkey_file"))

wifi = section("wifi")
add_pair("--wifi-ssid", wifi.get("ssid"))
add_pair("--wifi-country", wifi.get("country"))
add_pair("--wifi-ap-ssid", wifi.get("ap_ssid"))

for arg in args:
    print(arg)
PY
}

usage() {
    cat <<EOF
Usage:
  $0 [options]

Connection options:
  --host HOST        PiKVM IP address or hostname
  --user USER        SSH user, default: root
  --identity PATH    SSH identity file
  --config PATH      Load declarative YAML config; later CLI flags override it
  --write-config-template PATH|-  Write a config template and exit

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
  --quality-cap      Enable VNC JPEG quality cap (fixes Screens client issues)
  --keepalive        Enable TCP keepalive tuning for Tailscale stability
  --tailscale-diag   Run Tailscale networking diagnosis (read-only)
  --tailscale-setup  Install/enable Tailscale and run tailscale up
  --tailscale-crash-fix  Enable Tailscale crash mitigations for 32-bit ARM (auto-detects arch)
  --wifi             Configure WiFi (AP fallback + client mode)
  --wifi-ssid SSID   Default WiFi client SSID for the interactive WiFi wizard
  --wifi-country CC  Default WiFi country code for the interactive WiFi wizard
  --wifi-ap-ssid SSID Default fallback AP SSID for the interactive WiFi wizard
  --root-password    Change root password
  --2fa              Enable two-factor authentication (TOTP)
  --first-run        Run first-run setup wizard
  --msd-bios-fix     Enable MSD BIOS compatibility mode (fixes UEFI boot-loop)
  --usb-preset       Configure USB device preset (Normal/BIOS mode)
  --usb-extra        Enable USB extras (Ethernet/Serial/Audio)
  --msd-storage      Configure network storage mount for MSD ISOs
  --msd-drives       Enable additional MSD virtual drives
  --override-d       Enable override.d YAML fragment support
  --key              Enable SSH public key install module
  --pubkey-file PATH SSH public key file for non-interactive install
  --install          Install/update on-device command at /usr/local/sbin/pikvm-optimizer
  # --sudo             Configure restricted NOPASSWD sudo for installed optimizer (DISABLED)
  # --sudo-user USER   User for restricted sudo (non-interactive) (DISABLED)

Other:
  --print-remote     Print embedded remote script and exit
  --reboot           Reboot PiKVM after changes
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
  $0 --host pikvm.local --install --yes
  $0 --host pikvm.local --edid --edid-url https://example.com/edid.hex --yes
  $0 --write-config-template pikvm-optimizer.yaml
  $0 --config pikvm-optimizer.yaml --dry-run
  $0 --print-remote > /tmp/pikvm-optimizer-remote.sh
EOF
}

if [ "$#" -gt 0 ]; then
    ORIGINAL_ARGS=("$@")
    USER_ARGS=()

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --config)
                require_arg "$1" "${2:-}"
                CONFIG_FILE="$2"
                shift 2
                ;;
            --write-config-template)
                require_arg "$1" "${2:-}"
                WRITE_CONFIG_TEMPLATE="$2"
                shift 2
                ;;
            *)
                USER_ARGS+=("$1")
                shift
                ;;
        esac
    done

    if [ -n "$WRITE_CONFIG_TEMPLATE" ]; then
        write_config_template "$WRITE_CONFIG_TEMPLATE"
        exit 0
    fi

    if [ -n "$CONFIG_FILE" ]; then
        CONFIG_ARGS=()
        CONFIG_ARGS_FILE="$(mktemp /tmp/pikvm-optimizer-config-args.XXXXXXXXXX)"
        if ! config_to_args "$CONFIG_FILE" > "$CONFIG_ARGS_FILE"; then
            rm -f "$CONFIG_ARGS_FILE"
            exit 1
        fi

        while IFS= read -r arg; do
            CONFIG_ARGS+=("$arg")
        done < "$CONFIG_ARGS_FILE"
        rm -f "$CONFIG_ARGS_FILE"

        set -- "${CONFIG_ARGS[@]}" "${USER_ARGS[@]}"
    else
        set -- "${ORIGINAL_ARGS[@]}"
    fi
fi

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
            LOCAL_YES=true
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
        --core|--no-core|--mtu|--edid|--ssl|--fan|--watchdog|--key|--install|--sudo|--quality-cap|--keepalive|--tailscale-diag|--tailscale-setup|--tailscale-crash-fix|--wifi|--root-password|--2fa|--first-run|--msd-bios-fix|--usb-preset|--usb-extra|--msd-storage|--msd-drives|--override-d)
            REMOTE_ARGS+=("$1")
            shift
            ;;
        --wifi-ssid|--wifi-country|--wifi-ap-ssid)
            require_arg "$1" "${2:-}"
            REMOTE_ARGS+=("$1" "$2")
            shift 2
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
        --reboot)
            REMOTE_ARGS+=(--reboot)
            shift
            ;;
        --no-color)
            export NO_COLOR=true
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

R=$'\033[31m'
G=$'\033[32m'
Y=$'\033[33m'
C=$'\033[36m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RESET=$'\033[0m'

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
    local rc="${1:-$?}"
    local remote_dir_q=""

    if [ "$LOCAL_CLEANED" = true ]; then
        exit "$rc"
    fi

    LOCAL_CLEANED=true

    if [ -n "${PI_HOST:-}" ] && [ -n "${PI_USER:-}" ] && [ -n "${REMOTE_DIR:-}" ] && [ "${#SSH_OPTS[@]}" -gt 0 ]; then
        remote_dir_q="$(shell_quote "$REMOTE_DIR")"
        ssh "${SSH_OPTS[@]}" "${PI_USER}@${PI_HOST}" "rm -rf -- $remote_dir_q" >/dev/null 2>&1 || true
    fi

    # Close SSH multiplexed connection
    if [ -n "${PI_HOST:-}" ] && [ -n "${PI_USER:-}" ] && [ "${#SSH_OPTS[@]}" -gt 0 ]; then
        ssh -O exit "${SSH_OPTS[@]}" "${PI_USER}@${PI_HOST}" >/dev/null 2>&1 || true
    fi

    exit "$rc"
}

cancel_local() {
    printf "\n%bCancelled locally. Cleaning up remote temp file if possible...%b\n" "$Y" "$RESET"
    cleanup_local 130
}

if [ "$PRINT_REMOTE" = true ]; then
    sed -n "/<<'PIKVM_REMOTE_SCRIPT'$/,/^PIKVM_REMOTE_SCRIPT$/p" "$0" | sed '1d;$d'
    exit 0
fi

LOCAL_BOX_W=76
local_box_border() {
    local left="$1"
    local right="$2"
    local border="$left"
    local i
    for ((i = 0; i < LOCAL_BOX_W + 2; i++)); do
        border+="═"
    done
    border+="$right"
    printf "%b%s%b\n" "${C}${BOLD}" "$border" "$RESET"
}

local_box_line() {
    local text="$1"
    local plain
    plain=$(printf "%s" "$text" | cut -c 1-"$LOCAL_BOX_W")
    printf "%b║%b %-*s %b║%b\n" "${C}${BOLD}" "$RESET" "$LOCAL_BOX_W" "$plain" "${C}${BOLD}" "$RESET"
}

local_box_border "╔" "╗"
local_box_line "PiKVM Optimizer v${VERSION}                                  $(date +%Y-%m-%d)"
local_box_line "Single-file macOS/Linux launcher with embedded PiKVM remote optimizer"
local_box_border "╚" "╝"

if [ "$DRY_RUN" = true ]; then
    printf "%b\n" "${Y}${BOLD}DRY RUN ENABLED:${RESET} persistent PiKVM changes will be skipped where possible."
fi

printf "\n"
if [ "$LOCAL_YES" != true ]; then
    printf "%bPress Enter to continue...%b\n" "$DIM" "$RESET"
    read -r
    printf "\n"
fi

if [ -z "$PI_HOST" ]; then
    read -rp "PiKVM target IP or hostname: " PI_HOST
fi

[ -z "$PI_HOST" ] && exit 1

if [ -z "$PI_USER" ]; then
    read -rp "SSH user [root]: " PI_USER
    PI_USER="${PI_USER:-root}"
fi

if [ -z "$SSH_KEY" ] && [ "$LOCAL_YES" != true ]; then
    read -rp "Optional: SSH private key path (for key-based auth) [Enter to use SSH agent/keychain]: " SSH_KEY
fi

REMOTE_DIR=""
REMOTE_DEST=""

SSH_OPTS=(
    -o ConnectTimeout=10
    -o ServerAliveInterval=15
    -o ServerAliveCountMax=2
    -o StrictHostKeyChecking=accept-new
    -o ControlMaster=auto
    -o ControlPath="/tmp/pikvm-optimizer-ssh-%r@%h:%p"
    -o ControlPersist=60
)

if [ -n "$SSH_KEY" ]; then
    SSH_OPTS+=(-i "$SSH_KEY")
fi

trap cancel_local INT TERM

printf "\n%b  Testing SSH access...%b" "$DIM" "$RESET"

if ! ssh "${SSH_OPTS[@]}" "${PI_USER}@${PI_HOST}" "echo ok" >/dev/null; then
    printf "\r%b  [ERR] SSH login failed.%b\n" "$R" "$RESET"
    printf "  Use the PiKVM Linux SSH account, usually root, not just the web UI account.\n"
    exit 1
fi
printf "\r%b  [OK] SSH connection established.%b\n" "$G" "$RESET"

printf "%b  Creating secure temp directory...%b" "$DIM" "$RESET"

REMOTE_DIR="$(ssh "${SSH_OPTS[@]}" "${PI_USER}@${PI_HOST}" "mktemp -d /tmp/pikvm-optimizer.XXXXXXXXXX" 2>/dev/null)" || {
    printf "\r%b  [ERR] Failed to create temp directory on PiKVM.%b\n" "$R" "$RESET"
    exit 1
}
printf "\r%b  [OK] Temp directory created.%b\n" "$G" "$RESET"

REMOTE_DEST="${REMOTE_DIR}/optimizer.sh"

printf "  Uploading embedded optimizer...\n"

REMOTE_DEST_Q="$(shell_quote "$REMOTE_DEST")"
ssh "${SSH_OPTS[@]}" "${PI_USER}@${PI_HOST}" "cat > $REMOTE_DEST_Q && chmod 700 $REMOTE_DEST_Q" <<'PIKVM_REMOTE_SCRIPT'
#!/usr/bin/env bash
# ==============================================================================
# Embedded PiKVM Remote Optimizer
# ==============================================================================

set -euo pipefail
set +e  # Disable exit-on-error; we handle errors manually

REMOTE_VERSION="1.4.2"

# ------------------------------------------------------------------------------
# Remote options
# ------------------------------------------------------------------------------

DRY_RUN=false
YES=false
MODE="optimize"
PRESET="interactive"
FLAGS_PROVIDED=false

remote_usage() {
    cat <<'EOF'
Usage:
  pikvm-optimizer-remote [options]

Run modes:
  --dry-run          Preview actions without persistent changes
  --yes              Non-interactive mode; run selected flags/preset directly
  --health-check     Run diagnostics only
  --uninstall        Open uninstall/cleanup menu
  --restore          Restore /etc/kvmd/override.yaml from backup

Presets:
  --recommended      Select recommended modules
  --all              Select all safe modules; excludes secret/login modules
  --none             Select no modules

Install/update:
  --install          Copy this remote optimizer to /usr/local/sbin/pikvm-optimizer
                     Re-running --install with a newer launcher updates that copy.

Wizard defaults:
  --wifi-ssid SSID   Prefill WiFi client SSID; password is still prompted
  --wifi-country CC  Prefill WiFi country code
  --wifi-ap-ssid SSID Prefill fallback AP SSID

Use the local launcher help for connection options and examples:
  ./pikvm_optimizer.sh --help
EOF
}

require_remote_arg() {
    local opt="$1"
    local val="${2:-}"
    if [ -z "$val" ] || [ "${val#-}" != "$val" ]; then
        printf "Remote option error: %s requires a value\n" "$opt" >&2
        exit 1
    fi
}

RUN_CORE=true
RUN_MTU=false
RUN_EDID=false
RUN_SSL=false
RUN_FAN=false
RUN_WATCHDOG=false
RUN_KEY=false
RUN_INSTALL=false
RUN_SUDO=false
RUN_QUALITY_CAP=false
RUN_KEEPALIVE=false

UN_CORE=false
UN_MTU=false
UN_EDID=false
UN_SSL=false
UN_FAN=false
UN_WATCHDOG=false
UN_KEY=false
UN_INSTALL=false
UN_SUDO=false
UN_QUALITY_CAP=false
UN_KEEPALIVE=false

RUN_TAILSCALE_DIAG=false
RUN_TAILSCALE_SETUP=false
RUN_TAILSCALE_CRASH_FIX=false
RUN_WIFI=false
RUN_ROOT_PASSWORD=false
RUN_2FA=false
RUN_FIRST_RUN=false
RUN_MSD_BIOS_FIX=false
RUN_USB_PRESET=false
RUN_USB_EXTRA=false
RUN_MSD_STORAGE=false
RUN_MSD_DRIVES=false
RUN_OVERRIDE_D=false

UN_WIFI=false
UN_2FA=false
UN_MSD_BIOS_FIX=false
UN_TAILSCALE_CRASH_FIX=false
UN_USB_PRESET=false
UN_USB_EXTRA=false
UN_MSD_STORAGE=false
UN_MSD_DRIVES=false
UN_OVERRIDE_D=false

EDID_URL=""
EDID_FILE=""
PUBKEY_CONTENT=""
SUDO_USER=""
REBOOT=false
WIFI_SSID=""
WIFI_COUNTRY=""
WIFI_AP_SSID=""

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
            RUN_QUALITY_CAP=false
            RUN_KEEPALIVE=false
            RUN_TAILSCALE_DIAG=false
            RUN_TAILSCALE_SETUP=false
            RUN_TAILSCALE_CRASH_FIX=false
            RUN_WIFI=false
            RUN_ROOT_PASSWORD=false
            RUN_2FA=false
            RUN_FIRST_RUN=false
            RUN_MSD_BIOS_FIX=true
            RUN_USB_PRESET=false
            RUN_USB_EXTRA=false
            RUN_MSD_STORAGE=false
            RUN_MSD_DRIVES=false
            RUN_OVERRIDE_D=false
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
            RUN_QUALITY_CAP=true
            RUN_KEEPALIVE=true
            RUN_TAILSCALE_DIAG=true
            RUN_TAILSCALE_SETUP=false
            RUN_TAILSCALE_CRASH_FIX=true
            RUN_WIFI=false
            RUN_ROOT_PASSWORD=false
            RUN_2FA=false
            RUN_FIRST_RUN=false
            RUN_MSD_BIOS_FIX=true
            RUN_USB_PRESET=true
            RUN_USB_EXTRA=true
            RUN_MSD_STORAGE=true
            RUN_MSD_DRIVES=true
            RUN_OVERRIDE_D=true
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
            RUN_QUALITY_CAP=false
            RUN_KEEPALIVE=false
            RUN_TAILSCALE_DIAG=false
            RUN_TAILSCALE_SETUP=false
            RUN_TAILSCALE_CRASH_FIX=false
            RUN_WIFI=false
            RUN_ROOT_PASSWORD=false
            RUN_2FA=false
            RUN_FIRST_RUN=false
            RUN_MSD_BIOS_FIX=false
            RUN_USB_PRESET=false
            RUN_USB_EXTRA=false
            RUN_MSD_STORAGE=false
            RUN_MSD_DRIVES=false
            RUN_OVERRIDE_D=false
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
        --quality-cap)
            RUN_QUALITY_CAP=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --keepalive)
            RUN_KEEPALIVE=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --tailscale-diag)
            RUN_TAILSCALE_DIAG=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --tailscale-setup)
            RUN_TAILSCALE_SETUP=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --tailscale-crash-fix)
            RUN_TAILSCALE_CRASH_FIX=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --wifi)
            RUN_WIFI=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --root-password)
            RUN_ROOT_PASSWORD=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --2fa)
            RUN_2FA=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --first-run)
            RUN_FIRST_RUN=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --msd-bios-fix)
            RUN_MSD_BIOS_FIX=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --usb-preset)
            RUN_USB_PRESET=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --usb-extra)
            RUN_USB_EXTRA=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --msd-storage)
            RUN_MSD_STORAGE=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --msd-drives)
            RUN_MSD_DRIVES=true
            FLAGS_PROVIDED=true
            shift
            ;;
        --override-d)
            RUN_OVERRIDE_D=true
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
            require_remote_arg "$1" "${2:-}"
            EDID_URL="${2:-}"
            shift 2
            ;;
        --edid-file)
            require_remote_arg "$1" "${2:-}"
            EDID_FILE="${2:-}"
            shift 2
            ;;
        --pubkey-content)
            require_remote_arg "$1" "${2:-}"
            PUBKEY_CONTENT="${2:-}"
            shift 2
            ;;
        --sudo-user)
            require_remote_arg "$1" "${2:-}"
            SUDO_USER="${2:-}"
            shift 2
            ;;
        --wifi-ssid)
            require_remote_arg "$1" "${2:-}"
            WIFI_SSID="${2:-}"
            shift 2
            ;;
        --wifi-country)
            require_remote_arg "$1" "${2:-}"
            WIFI_COUNTRY="${2:-}"
            shift 2
            ;;
        --wifi-ap-ssid)
            require_remote_arg "$1" "${2:-}"
            WIFI_AP_SSID="${2:-}"
            shift 2
            ;;
        --no-color)
            export NO_COLOR=true
            shift
            ;;
        --reboot)
            REBOOT=true
            shift
            ;;
        -V|--version)
            printf "PiKVM Optimizer remote v%s\n" "$REMOTE_VERSION"
            exit 0
            ;;
        -h|--help)
            remote_usage
            exit 0
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

R=$'\033[31m'
G=$'\033[32m'
Y=$'\033[33m'
C=$'\033[36m'
W=$'\033[37m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
RESET=$'\033[0m'
CLEAR=$'\033[2J\033[H'
HIDE_CURSOR=$'\033[?25l'
SHOW_CURSOR=$'\033[?25h'

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
# Pick first writable path for the log file
LOG_FILE=""
for _try in "/root/pikvm-optimizer.log" "/var/log/pikvm-optimizer.log" "/tmp/pikvm-optimizer.log"; do
    if touch "$_try" 2>/dev/null; then
        LOG_FILE="$_try"
        break
    fi
done
INSTALL_PATH="/usr/local/sbin/pikvm-optimizer"

BACKUP_FILE=""
FAN_BACKUP_FILE=""
INSTALL_BACKUP_FILE=""
MTU_BACKUP_FILE=""
EDID_BACKUP_FILE=""
SSL_BACKUP_FILE=""
WATCHDOG_BACKUP_FILE=""
KEEPALIVE_BACKUP_FILE=""
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
QUALITY_CAP_CHANGED=false
KEEPALIVE_CHANGED=false
MSD_BIOS_FIX_CHANGED=false
USB_PRESET_CHANGED=false
USB_EXTRA_CHANGED=false
MSD_STORAGE_CHANGED=false
MSD_DRIVES_CHANGED=false
OVERRIDE_D_CHANGED=false

# Irreversible module tracking (for rollback summary)
ROOT_PASSWORD_EXECUTED=false
ADMIN_PASSWORD_EXECUTED=false
TFA_EXECUTED=false
TAILSCALE_SETUP_EXECUTED=false
WIFI_EXECUTED=false
TAILSCALE_CRASH_FIX_EXECUTED=false

# ------------------------------------------------------------------------------
# Remote UI helpers
# ------------------------------------------------------------------------------

# Box-drawing characters ─ ASCII fallback on dumb terminals
if [ "${TERM:-dumb}" != "dumb" ]; then
    TL="╔" TR="╗" BL="╚" BR="╝" H="═" V="║" SL="╠" SR="╣"
else
    TL="+" TR="+" BL="+" BR="+" H="-" V="|" SL="+" SR="+"
fi

BOX_W=76  # inner content width (80 total: 2 borders + 2 spaces + 76 content)

# Terminal detection and centering
TERM_W="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
BOX_TOTAL=80
if [ "$TERM_W" -gt "$BOX_TOTAL" ]; then
    BOX_LEFT=$(( (TERM_W - BOX_TOTAL) / 2 ))
else
    BOX_LEFT=0
fi

repeat_text() {
    local text="$1"
    local count="$2"
    local out=""
    local i
    for ((i = 0; i < count; i++)); do
        out+="$text"
    done
    printf "%s" "$out"
}

__top_border="${TL}$(repeat_text "$H" "$((BOX_W + 2))")${TR}"
__bot_border="${BL}$(repeat_text "$H" "$((BOX_W + 2))")${BR}"
__sep_border="${SL}$(repeat_text "$H" "$((BOX_W + 2))")${SR}"

# Extract first N visible characters from an ANSI-colored string
# (skips ANSI escape sequences without counting them toward N)
ansi_take() {
    local str="$1" count="$2"
    local result="" vi=0 si=0 c
    while [ $vi -lt "$count" ] && [ $si -lt ${#str} ]; do
        c="${str:$si:1}"
        if [[ "$c" == $'\x1b' ]]; then
            result+="$c"; si=$((si + 1))
            # Copy rest of escape sequence up to 'm'
            while [ $si -lt ${#str} ] && [[ "${str:$si:1}" != 'm' ]]; do
                result+="${str:$si:1}"; si=$((si + 1))
            done
            if [ $si -lt ${#str} ]; then
                result+="m"; si=$((si + 1))
            fi
        else
            [ $vi -ge 0 ] && result+="$c"
            vi=$((vi + 1)); si=$((si + 1))
        fi
    done
    printf "%s" "$result"
}

box_prefix() { printf "%*s" "$BOX_LEFT" ""; }

box_top()    { box_prefix; printf "%b%s%b\n" "${C}${BOLD}" "$__top_border" "$RESET"; }
box_bottom() { box_prefix; printf "%b%s%b\n" "${C}${BOLD}" "$__bot_border" "$RESET"; }
box_sep()    { box_prefix; printf "%b%s%b\n" "${C}${BOLD}" "$__sep_border" "$RESET"; }

box_line() {
    local text="${1:-}"
    local plain pad line ansi_indent
    plain=$(printf "%s" "$text" | sed 's/\x1b\[[0-9;]*m//g')

    if [ ${#plain} -le $BOX_W ]; then
        # Fits in one line
        pad=$((BOX_W - ${#plain}))
        box_prefix; printf "%b%s %s%*s %s%b\n" "${C}${BOLD}" "$V" "$text" "$pad" "" "$V" "$RESET"
        return
    fi

    # Text too long — word-wrap.  Determine continuation indent from tag.
    local indent=0
    if [[ "$text" =~ \[([A-Z]+)\] ]]; then
        indent=$(( ${#BASH_REMATCH[0]} + 1 ))
    fi
    local cont_w=$((BOX_W - indent))

    local first=true
    while IFS= read -r line; do
        if [ "$first" = true ]; then
            # First line: preserve ANSI codes from original
            ansi_indent=$(ansi_take "$text" ${#line})
            pad=$((BOX_W - ${#line}))
            box_prefix; printf "%b%s %s%*s %s%b\n" "${C}${BOLD}" "$V" "$ansi_indent" "$pad" "" "$V" "$RESET"
            first=false
        else
            # Continuation line: indented under the tag, no color needed
            pad=$((cont_w - ${#line}))
            [ "$pad" -lt 0 ] && pad=0
            box_prefix; printf "%b%s %*s%s%*s %s%b\n" "${C}${BOLD}" "$V" "$indent" "" "$line" "$pad" "" "$V" "$RESET"
        fi
    done < <(printf "%s\n" "$plain" | fold -s -w "$BOX_W")
}

draw() {
    local title="$1"
    printf "%b" "$CLEAR"
    printf "%b" "$HIDE_CURSOR"
    box_top
    box_line "${W}${BOLD}${title}${RESET}"
    box_sep
}

close_box() {
    box_bottom
    printf "%b" "$SHOW_CURSOR"
}

info() {
    box_line "${DIM}[INFO]${RESET} $1"
    log_msg "INFO" "$1"
}

ok() {
    box_line "${G}[OK]${RESET} $1"
    log_msg "OK" "$1"
}

warn() {
    box_line "${Y}[WARN]${RESET} $1"
    log_msg "WARN" "$1"
}

err() {
    box_line "${R}[ERR]${RESET} $1"
    log_msg "ERR" "$1"
}

log_msg() {
    local level="$1"
    local msg="$2"

    if [ "$DRY_RUN" = true ]; then
        return 0
    fi

    if [ -n "$LOG_FILE" ]; then
        printf "[%s] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$msg" >> "$LOG_FILE" 2>/dev/null || true
    fi
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

    if [ "$KEEPALIVE_CHANGED" = true ]; then
        if [ -n "$KEEPALIVE_BACKUP_FILE" ] && [ -f "$KEEPALIVE_BACKUP_FILE" ]; then
            cp "$KEEPALIVE_BACKUP_FILE" /etc/sysctl.d/99-pikvm-tcp-keepalive.conf || true
            warn "Restored TCP keepalive config from backup."
        else
            rm -f /etc/sysctl.d/99-pikvm-tcp-keepalive.conf
            warn "Removed TCP keepalive config installed by this run."
        fi
    fi

    if [ "$QUALITY_CAP_CHANGED" = true ]; then
        local qc_server_py
        qc_server_py="$(find /usr/lib -path '*/kvmd/apps/vnc/server.py' -print -quit 2>/dev/null || true)"
        if [ -n "$qc_server_py" ]; then
            local qc_backup
            qc_backup="$(ls -t "${qc_server_py}.bak."* 2>/dev/null | head -n 1 || true)"
            if [ -n "$qc_backup" ]; then
                cp "$qc_backup" "$qc_server_py" || true
                warn "Restored VNC server.py from backup."
            fi
        fi
    fi

    if [ "$MSD_BIOS_FIX_CHANGED" = true ]; then
        delete_yaml_paths otg.devices.msd.start || true
        warn "Removed MSD BIOS config key from this run."
    fi

    if [ "$USB_PRESET_CHANGED" = true ]; then
        delete_yaml_paths otg.devices.keyboard otg.devices.mouse otg.devices.msd otg.devices.hid || true
        warn "Reset USB device preset from this run."
    fi

    if [ "$USB_EXTRA_CHANGED" = true ]; then
        delete_yaml_paths otg.devices.ethernet otg.devices.serial otg.devices.audio || true
        warn "Removed USB extras config keys from this run."
    fi

    if [ "$MSD_STORAGE_CHANGED" = true ]; then
        local msd_mount=""
        if [ -f /etc/fstab ]; then
            msd_mount="$(grep -E 'nfs|cifs' /etc/fstab 2>/dev/null | awk '{print $2}' | head -1 || true)"
        fi
        if [ -n "$msd_mount" ] && mountpoint -q "$msd_mount" 2>/dev/null; then
            umount "$msd_mount" 2>/dev/null || true
        fi
        if [ -f /etc/fstab ]; then
            grep -v -E 'nfs|cifs' /etc/fstab > /etc/fstab.tmp 2>/dev/null && mv /etc/fstab.tmp /etc/fstab
        fi
        warn "Reverted network storage changes from this run."
    fi

    if [ "$MSD_DRIVES_CHANGED" = true ]; then
        delete_yaml_paths otg.devices.msd_data || true
        warn "Removed additional MSD drives config from this run."
    fi

    if [ "$OVERRIDE_D_CHANGED" = true ]; then
        rm -rf /etc/kvmd/override.d 2>/dev/null || true
        warn "Removed override.d directory from this run."
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
            warn "Restored previous on-device optimizer command."
        else
            rm -f "$INSTALL_PATH"
            warn "Removed on-device optimizer command from this run."
        fi
    fi

    # --- Rollback summary ---
    local reverted="" left="" sep=""
    $CONFIG_CHANGED &&       { reverted+="${sep}KVMD override config"; sep=", "; }
    $FAN_CHANGED &&          { reverted+="${sep}fan curve"; sep=", "; }
    $WATCHDOG_CHANGED &&     { reverted+="${sep}Tailscale watchdog"; sep=", "; }
    $MTU_CHANGED &&          { reverted+="${sep}Tailscale MTU"; sep=", "; }
    $EDID_CHANGED &&         { reverted+="${sep}HDMI EDID"; sep=", "; }
    $KEEPALIVE_CHANGED &&    { reverted+="${sep}TCP keepalive"; sep=", "; }
    $QUALITY_CAP_CHANGED &&  { reverted+="${sep}VNC quality cap"; sep=", "; }
    $MSD_BIOS_FIX_CHANGED && { reverted+="${sep}MSD BIOS fix"; sep=", "; }
    $USB_PRESET_CHANGED &&   { reverted+="${sep}USB device preset"; sep=", "; }
    $USB_EXTRA_CHANGED &&    { reverted+="${sep}USB extras"; sep=", "; }
    $MSD_STORAGE_CHANGED &&  { reverted+="${sep}MSD network storage"; sep=", "; }
    $MSD_DRIVES_CHANGED &&   { reverted+="${sep}MSD drives"; sep=", "; }
    $OVERRIDE_D_CHANGED &&   { reverted+="${sep}override.d directory"; sep=", "; }
    $SSL_CHANGED &&          { reverted+="${sep}SSL certs"; sep=", "; }
    $KEY_CHANGED &&          { reverted+="${sep}SSH public key"; sep=", "; }
    $SUDOERS_CHANGED &&      { reverted+="${sep}sudoers rule"; sep=", "; }
    $INSTALL_CHANGED &&      { reverted+="${sep}on-device optimizer command"; sep=", "; }

    sep=""
    $ROOT_PASSWORD_EXECUTED &&       { left+="${sep}root password change"; sep=", "; }
    $ADMIN_PASSWORD_EXECUTED &&      { left+="${sep}Web/KVM admin password change"; sep=", "; }
    $TFA_EXECUTED &&                 { left+="${sep}TOTP 2FA setup"; sep=", "; }
    $TAILSCALE_SETUP_EXECUTED &&     { left+="${sep}Tailscale install/registration"; sep=", "; }
    $WIFI_EXECUTED &&                { left+="${sep}WiFi configuration"; sep=", "; }
    $TAILSCALE_CRASH_FIX_EXECUTED && { left+="${sep}Tailscale crash fix"; sep=", "; }

    box_sep
    if [ -n "$reverted" ]; then
        box_line "${G}Reverted:${RESET} $reverted"
    else
        box_line "Reverted: (none)"
    fi
    if [ -n "$left" ]; then
        box_line "${Y}Left in place (cannot be undone):${RESET} $left"
    fi
    box_line "Manual cleanup may be needed for the items listed above."
}

cleanup_remote() {
    local rc=$?

    if [ "$SUCCESS" != true ] && [ "$rc" -ne 0 ]; then
        rollback_changes
    fi

    make_ro
    if [ -n "${RUNTIME_DIR:-}" ]; then
        rm -rf -- "$RUNTIME_DIR" 2>/dev/null || true
    fi
    if [ "${REMOVE_SCRIPT_DIR_ON_EXIT:-false}" = true ] && [ -n "${REMOTE_SCRIPT_DIR:-}" ]; then
        rm -rf -- "$REMOTE_SCRIPT_DIR" 2>/dev/null || true
    fi
    printf "%b" "$SHOW_CURSOR"
    exit "$rc"
}

cancel_remote() {
    box_sep
    warn "Cancellation requested. Rolling back reversible changes this run made..."
    box_line "${Y}Note:${RESET} password changes, Tailscale registration, 2FA, and WiFi config"
    box_line "      are irreversible and will be reported at the end."
    trap - INT TERM          # keep EXIT trap so cleanup_remote runs the rollback
    SUCCESS=false
    exit 130
}

REMOTE_SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REMOVE_SCRIPT_DIR_ON_EXIT=false
case "$REMOTE_SCRIPT_DIR" in
    /tmp/pikvm-optimizer.*) REMOVE_SCRIPT_DIR_ON_EXIT=true ;;
esac
RUNTIME_DIR="$(mktemp -d /tmp/pikvm-optimizer-runtime.XXXXXXXXXX)"

trap cancel_remote INT TERM
trap cleanup_remote EXIT

# ------------------------------------------------------------------------------
# Remote misc helpers
# ------------------------------------------------------------------------------

require_command() {
    local cmd="$1"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        err "Missing required command: $cmd. Install it or check your PATH."
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
                err "Service restart failed for $svc; check \`systemctl status $svc\`."
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
        # kvmd --override-config requires the override.d directory to exist
        mkdir -p /etc/kvmd/override.d
        kvmd -M --override-config="$file" >/dev/null 2>&1
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
    local helper="${RUNTIME_DIR}/pikvm-yaml-merge.py"

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
    local helper="${RUNTIME_DIR}/pikvm-yaml-delete.py"

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
    box_line ""

    while IFS= read -r line; do
        box_line "  ${line:0:72}"
    done < "$patch_file"

    box_line ""
    box_line "After manual merge, run:"
    box_line "  kvmd -M --override-config=$CONFIG_FILE"
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
    local work_file="${RUNTIME_DIR}/pikvm-optimizer.clean.yaml"

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
        err "Fallback clean config not accepted by 'kvmd -M'."
        box_line "This module's settings cannot be applied without Python YAML support."
        box_line "Install PyYAML on the PiKVM (python3 -m pip install pyyaml) then rerun,"
        box_line "or merge the patch manually (see saved patch path above)."
        return 1
    fi
}

merge_yaml_patch() {
    local patch_file="$1"
    local work_file="${RUNTIME_DIR}/pikvm-optimizer.merged.yaml"

    if python_yaml_available; then
        write_yaml_merge_helper

        if ! python3 -c "import yaml; yaml.safe_load(open('$CONFIG_FILE').read())" >/dev/null 2>&1; then
            warn "Existing $CONFIG_FILE has malformed YAML. Cannot safely merge."
            warn "Options:"
            warn "  1) Backup and replace with clean config containing this module's settings (recommended)"
            warn "  2) Skip this module and keep broken config"
            if [ "$DRY_RUN" = true ]; then
                ok "DRY RUN: would offer to replace malformed config."
                return 0
            fi
            if [ "$YES" = true ]; then
                info "Non-interactive mode: backing up and replacing malformed config with clean config."
                # Create a minimal valid kvmd config with the patch applied
                python3 -c "
import yaml, sys
with open('$patch_file') as f:
    patch = yaml.safe_load(f)
# Start with minimal valid config
config = {'kvmd': {}}
# Deep merge patch into config
def deep_merge(base, patch):
    for key, value in patch.items():
        if key in base and isinstance(base[key], dict) and isinstance(value, dict):
            deep_merge(base[key], value)
        else:
            base[key] = value
    return base
deep_merge(config, patch)
with open('$work_file', 'w') as f:
    yaml.safe_dump(config, f, default_flow_style=False, sort_keys=False, indent=4)
"
                if validate_kvmd_config "$work_file"; then
                    make_rw
                    local atomic_tmp="${CONFIG_FILE}.tmp.$$"
                    cp "$work_file" "$atomic_tmp"
                    mv -f "$atomic_tmp" "$CONFIG_FILE"
                    CONFIG_CHANGED=true
                    ok "Replaced malformed config with clean config containing module settings."
                    return 0
                else
                    err "Generated config not accepted by 'kvmd -M'; not replacing."
                    box_line "This can happen if the module's config keys differ from what your PiKVM version"
                    box_line "expects. Backup preserved; other modules may still work."
                    return 1
                fi
            fi
            printf "Replace malformed config with clean config containing this module's settings? [y/N]: "
            read -r choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                python3 -c "
import yaml, sys
with open('$patch_file') as f:
    patch = yaml.safe_load(f)
config = {'kvmd': {}}
def deep_merge(base, patch):
    for key, value in patch.items():
        if key in base and isinstance(base[key], dict) and isinstance(value, dict):
            deep_merge(base[key], value)
        else:
            base[key] = value
    return base
deep_merge(config, patch)
with open('$work_file', 'w') as f:
    yaml.safe_dump(config, f, default_flow_style=False, sort_keys=False, indent=4)
"
                # When replacing malformed config, only validate YAML syntax (not full kvmd validation)
                # since the minimal config may not have all required sections
                if python3 -c "import yaml; yaml.safe_load(open('$work_file').read())" >/dev/null 2>&1; then
                    make_rw
                    local atomic_tmp="${CONFIG_FILE}.tmp.$$"
                    cp "$work_file" "$atomic_tmp"
                    mv -f "$atomic_tmp" "$CONFIG_FILE"
                    CONFIG_CHANGED=true
                    ok "Replaced malformed config with clean config containing module settings."
                    warn "Note: Config has minimal structure. Run other modules to complete setup."
                    return 0
                else
                    err "Generated config has invalid YAML; not replacing."
                    return 1
                fi
            else
                warn "Skipping config update for this module."
                return 0
            fi
        fi

        python3 "${RUNTIME_DIR}/pikvm-yaml-merge.py" "$CONFIG_FILE" "$patch_file" "$work_file"

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
            err "kvmd validation failed; config not changed for this module."
            [ -n "$BACKUP_FILE" ] && warn "Backup remains available: $BACKUP_FILE"
            if [ "$DRY_RUN" = false ]; then
                warn "The generated config did not pass 'kvmd -M' validation."
                warn "This can happen if the module's config keys are not supported by your PiKVM version."
                warn "Other modules may still succeed; check the backup and rerun with --health-check."
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
    local work_file="${RUNTIME_DIR}/pikvm-optimizer.deleted.yaml"

    if ! python_yaml_available; then
        warn "Python YAML module missing; cannot safely remove YAML keys."
        warn "Skipped YAML cleanup to avoid corrupting $CONFIG_FILE."
        return 0
    fi

    write_yaml_delete_helper
    python3 "${RUNTIME_DIR}/pikvm-yaml-delete.py" "$CONFIG_FILE" "$work_file" "$@"

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
    printf "Selected recommended preset.\n"
    RUN_CORE=true
    RUN_MTU=false
    RUN_EDID=false
    RUN_SSL=false
    RUN_FAN=false
    RUN_WATCHDOG=false
    RUN_KEY=false
    RUN_INSTALL=false
    RUN_SUDO=false
    RUN_QUALITY_CAP=false
    RUN_KEEPALIVE=false
    RUN_TAILSCALE_DIAG=false
    RUN_TAILSCALE_SETUP=false
    RUN_TAILSCALE_CRASH_FIX=false
    RUN_WIFI=false
    RUN_ROOT_PASSWORD=false
    RUN_2FA=false
    RUN_FIRST_RUN=false
    RUN_MSD_BIOS_FIX=true
    RUN_USB_PRESET=false
    RUN_USB_EXTRA=false
    RUN_MSD_STORAGE=false
    RUN_MSD_DRIVES=false
    RUN_OVERRIDE_D=false
}

apply_all_preset() {
    printf "Selected all safe modules preset.\n"
    RUN_CORE=true
    RUN_MTU=true
    RUN_EDID=true
    RUN_SSL=true
    RUN_FAN=true
    RUN_WATCHDOG=true
    RUN_KEY=true
    RUN_INSTALL=true
    RUN_SUDO=false
    RUN_QUALITY_CAP=true
    RUN_KEEPALIVE=true
    RUN_TAILSCALE_DIAG=true
    RUN_TAILSCALE_SETUP=false
    RUN_TAILSCALE_CRASH_FIX=true
    RUN_WIFI=false
    RUN_ROOT_PASSWORD=false
    RUN_2FA=false
    RUN_FIRST_RUN=false
    RUN_MSD_BIOS_FIX=true
    RUN_USB_PRESET=true
    RUN_USB_EXTRA=true
    RUN_MSD_STORAGE=true
    RUN_MSD_DRIVES=true
    RUN_OVERRIDE_D=true
}

apply_none_preset() {
    printf "Cleared all module selections.\n"
    RUN_CORE=false
    RUN_MTU=false
    RUN_EDID=false
    RUN_SSL=false
    RUN_FAN=false
    RUN_WATCHDOG=false
    RUN_KEY=false
    RUN_INSTALL=false
    RUN_SUDO=false
    RUN_QUALITY_CAP=false
    RUN_KEEPALIVE=false
    RUN_TAILSCALE_DIAG=false
    RUN_TAILSCALE_SETUP=false
    RUN_TAILSCALE_CRASH_FIX=false
    RUN_WIFI=false
    RUN_ROOT_PASSWORD=false
    RUN_2FA=false
    RUN_FIRST_RUN=false
    RUN_MSD_BIOS_FIX=false
    RUN_USB_PRESET=false
    RUN_USB_EXTRA=false
    RUN_MSD_STORAGE=false
    RUN_MSD_DRIVES=false
    RUN_OVERRIDE_D=false
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
        box_line "[8] [$(yn_marker "$RUN_INSTALL")] Install/update on-device optimizer command"
        box_line "[9] [$(yn_marker "$RUN_QUALITY_CAP")] VNC JPEG quality cap (Screens fix)"
        box_line "[0] [$(yn_marker "$RUN_KEEPALIVE")] TCP keepalive tuning (Tailscale)"
        box_line ""
        box_line "[t] [$(yn_marker "$RUN_TAILSCALE_DIAG")] Tailscale networking diagnosis (read-only)"
        box_line "[g] [$(yn_marker "$RUN_TAILSCALE_SETUP")] Tailscale install/login setup"
        box_line "[c] [$(yn_marker "$RUN_TAILSCALE_CRASH_FIX")] Tailscale crash fix (32-bit ARM mitigations)"
        box_line "[w] [$(yn_marker "$RUN_WIFI")] WiFi configuration (AP + client)"
        box_line "[x] [$(yn_marker "$RUN_ROOT_PASSWORD")] Change root password"
        box_line "[z] [$(yn_marker "$RUN_2FA")] Two-factor authentication (TOTP)"
        box_line "[f] [$(yn_marker "$RUN_FIRST_RUN")] First-run setup wizard"
        box_line "[m] [$(yn_marker "$RUN_MSD_BIOS_FIX")] MSD BIOS compatibility (UEFI boot-loop fix)"
        box_line "[p] [$(yn_marker "$RUN_USB_PRESET")] USB device preset (Normal/BIOS mode)"
        box_line "[e] [$(yn_marker "$RUN_USB_EXTRA")] USB extras (Ethernet/Serial/Audio)"
        box_line "[s] [$(yn_marker "$RUN_MSD_STORAGE")] Network storage mount for MSD ISOs"
        box_line "[d] [$(yn_marker "$RUN_MSD_DRIVES")] Additional MSD virtual drives"
        box_line "[o] [$(yn_marker "$RUN_OVERRIDE_D")] override.d YAML fragment support"
        box_line ""
        close_box

        box_prefix; printf "Enter letter/number to toggle, or press Enter to proceed: "
        read -r choice

        case "$choice" in
            "")
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
            9) toggle_bool RUN_QUALITY_CAP ;;
            0) toggle_bool RUN_KEEPALIVE ;;
            t|T) toggle_bool RUN_TAILSCALE_DIAG ;;
            g|G) toggle_bool RUN_TAILSCALE_SETUP ;;
            c|C) toggle_bool RUN_TAILSCALE_CRASH_FIX ;;
            w|W) toggle_bool RUN_WIFI ;;
            x|X) toggle_bool RUN_ROOT_PASSWORD ;;
            z|Z) toggle_bool RUN_2FA ;;
            f|F) toggle_bool RUN_FIRST_RUN ;;
            m|M) toggle_bool RUN_MSD_BIOS_FIX ;;
            p|P) toggle_bool RUN_USB_PRESET ;;
            e|E) toggle_bool RUN_USB_EXTRA ;;
            s|S) toggle_bool RUN_MSD_STORAGE ;;
            d|D) toggle_bool RUN_MSD_DRIVES ;;
            o|O) toggle_bool RUN_OVERRIDE_D ;;
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
        box_line "Type numbers/letters to toggle. Press Enter with no input to continue."
        box_line "Presets: a = all cleanup, n = none, q = back"
        box_line ""
        box_line "[1] [$(yn_marker "$UN_CORE")] Remove optimizer core config keys"
        box_line "[2] [$(yn_marker "$UN_MTU")] Remove Tailscale MTU link file"
        box_line "[3] [$(yn_marker "$UN_EDID")] Remove EDID file and EDID config key"
        box_line "[4] [$(yn_marker "$UN_SSL")] Remove Tailscale SSL cert/key"
        box_line "[5] [$(yn_marker "$UN_FAN")] Restore latest fan backup if available"
        box_line "[6] [$(yn_marker "$UN_WATCHDOG")] Remove Tailscale watchdog"
        box_line "[7] [$(yn_marker "$UN_KEY")] Remove SSH public key from authorized_keys"
        box_line "[8] [$(yn_marker "$UN_INSTALL")] Remove on-device optimizer command"
        box_line "[9] [$(yn_marker "$UN_QUALITY_CAP")] Restore VNC server.py from backup"
        box_line "[0] [$(yn_marker "$UN_KEEPALIVE")] Remove TCP keepalive sysctl config"
        box_line ""
        box_line "[c] [$(yn_marker "$UN_TAILSCALE_CRASH_FIX")] Remove Tailscale crash fix (IPv6 sysctl + watchdog config)"
        box_line "[w] [$(yn_marker "$UN_WIFI")] Remove WiFi configuration"
        box_line "[z] [$(yn_marker "$UN_2FA")] Remove 2FA configuration"
        box_line "[m] [$(yn_marker "$UN_MSD_BIOS_FIX")] Remove MSD BIOS config key"
        box_line "[p] [$(yn_marker "$UN_USB_PRESET")] Reset USB device preset to defaults"
        box_line "[e] [$(yn_marker "$UN_USB_EXTRA")] Remove USB extras config keys"
        box_line "[s] [$(yn_marker "$UN_MSD_STORAGE")] Unmount and remove network storage config"
        box_line "[d] [$(yn_marker "$UN_MSD_DRIVES")] Reset MSD drives to single drive"
        box_line "[o] [$(yn_marker "$UN_OVERRIDE_D")] Remove override.d directory"
        box_line ""
        close_box

        box_prefix; printf "Selection: "
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
            9) toggle_bool UN_QUALITY_CAP ;;
            0) toggle_bool UN_KEEPALIVE ;;
            c|C) toggle_bool UN_TAILSCALE_CRASH_FIX ;;
            w|W) toggle_bool UN_WIFI ;;
            z|Z) toggle_bool UN_2FA ;;
            m|M) toggle_bool UN_MSD_BIOS_FIX ;;
            p|P) toggle_bool UN_USB_PRESET ;;
            e|E) toggle_bool UN_USB_EXTRA ;;
            s|S) toggle_bool UN_MSD_STORAGE ;;
            d|D) toggle_bool UN_MSD_DRIVES ;;
            o|O) toggle_bool UN_OVERRIDE_D ;;
            a|A)
                UN_CORE=true
                UN_MTU=true
                UN_EDID=true
                UN_SSL=true
                UN_FAN=true
                UN_WATCHDOG=true
                UN_KEY=false
                UN_INSTALL=true
                UN_SUDO=false
                UN_QUALITY_CAP=true
                UN_KEEPALIVE=true
                UN_MSD_BIOS_FIX=true
                UN_TAILSCALE_CRASH_FIX=true
                UN_WIFI=true
                UN_2FA=true
                UN_USB_PRESET=true
                UN_USB_EXTRA=true
                UN_MSD_STORAGE=true
                UN_MSD_DRIVES=true
                UN_OVERRIDE_D=true
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
                UN_QUALITY_CAP=false
                UN_KEEPALIVE=false
                UN_MSD_BIOS_FIX=false
                UN_TAILSCALE_CRASH_FIX=false
                UN_WIFI=false
                UN_2FA=false
                UN_USB_PRESET=false
                UN_USB_EXTRA=false
                UN_MSD_STORAGE=false
                UN_MSD_DRIVES=false
                UN_OVERRIDE_D=false
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
        quality: 15
        h264_bitrate:
            default: 1500
            min: 25
            max: 20000
        h264_gop:
            default: 0
            min: 0
            max: 60

vnc:
    auth:
        vncauth:
            enabled: true
EOF

    merge_yaml_patch "$patch"
}

apply_tailscale_mtu() {
    if ! command -v tailscale >/dev/null 2>&1; then
        warn "Tailscale not installed; skipped MTU tuning."
        box_line "Run the Tailscale setup module (--tailscale-setup) first, then rerun this."
        return 0
    fi

    info "Configuring Tailscale MTU..."

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

apply_tailscale_setup() {
    info "Setting up Tailscale..."

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would install tailscale if missing, enable tailscaled, and run tailscale up interactively."
        return 0
    fi

    make_rw

    if ! command -v tailscale >/dev/null 2>&1; then
        if command -v pacman >/dev/null 2>&1; then
            info "Installing tailscale package..."
            if ! pacman -S --needed --noconfirm tailscale-pikvm >/dev/null 2>&1; then
                warn "Could not install tailscale-pikvm with pacman. Check package mirrors/network and rerun."
                return 0
            fi
        else
            warn "tailscale not installed and pacman not found; skipped setup."
            return 0
        fi
    fi

    systemctl enable --now tailscaled.service >/dev/null 2>&1 || warn "Could not enable/start tailscaled.service."

    if tailscale status >/dev/null 2>&1; then
        ok "Tailscale is already authenticated and running."
        TAILSCALE_SETUP_EXECUTED=true
        return 0
    fi

    if [ "$YES" = true ]; then
        warn "Tailscale installed/started, but login requires an interactive auth URL."
        TAILSCALE_SETUP_EXECUTED=true
        box_line "Run later: tailscale up"
        return 0
    fi

    box_line "Tailscale will print a login URL. Open it, authenticate, then return here."
    if tailscale up; then
        ok "Tailscale login completed."
        TAILSCALE_SETUP_EXECUTED=true
    else
        warn "tailscale up did not complete. You can rerun: tailscale up"
    fi
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
        printf "\nEDID source options:\n"
        printf "  URL (https://...)              - Download EDID from URL\n"
        printf "  Local file path                - Use EDID file on PiKVM\n"
        printf "  'dell' or 'd2721h'             - Use bundled Dell D2721H 1080p60 EDID\n"
        printf "                                    (safe default; avoids macOS 1080p24/Screens issues)\n"
        printf "  'current'                      - Persist existing EDID (if any)\n"
        printf "  Leave blank                    - Skip EDID setup\n"
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

    local edid_source_lower
    edid_source_lower="$(printf "%s" "$edid_source" | tr '[:upper:]' '[:lower:]')"

    # Bundled Dell D2721H EDID without 1080p24 VIC 32, which avoids macOS/Screens mode selection issues.
    if [ "$edid_source_lower" = "dell" ] || [ "$edid_source_lower" = "d2721h" ]; then
        info "Using built-in DELL D2721H reference EDID."
        cat > "$edid_dest" <<'DELL_EDID_HEX'
00FFFFFFFFFFFF0010AC132045393639
201E0103803C22782ACD25A3574B9F27
0D5054A54B00714F8180A9C0D1C00101
0101010101010101023A801871382D4058
2C450056502100001E000000FF00333553
35475132330A2020202020000000FC0044
454C4C204432373231480A2000000000FD
00384C1E5311000A202020202020200181
02031AB14F9005040302071601061112
1513141F65030C001000023A80187138
2D40582C450056502100001E011D8018
711C1620582C250056502100009E011D
007251D01E206E28550056502100001E
8C0AD08A20E02D10103E960056502100
0018000000000000000000000000000000
000000000000000000000000000000004F
DELL_EDID_HEX
        EDID_CHANGED=true

    elif [ "$edid_source_lower" = "current" ]; then
        if [ -f "$edid_dest" ]; then
            info "Persisting existing EDID at $edid_dest."
            # File already in place, just need the YAML patch
            EDID_CHANGED=true
        else
            info "No existing EDID found; enabling built-in PiKVM reference."
            cat > "$edid_dest" <<'PIKVM_EDID_HEX'
00FFFFFFFFFFFF005262888800888888
001C0103800000780AEE91A3544C9926
0F5054A54B00714F8180D1C001010101
010101010101011D007251D01E206E28
5500C48E2100001E8C0AD08A20E02D10
103E9600C48E21000018000000FD0038
4B1F5311000A202020202020000000FC
0050692D4B564D0A202020202020015D
020301F14F900F1F3F14200513040302
011D80D0721C1620102C2580C48E2100
009E011D80D0721C1620102C2580C48E
2100009E011D00BC52D01E20B8285540
C48E2100001E8C0AD08A20E02D10103E
9600C48E21000018000000FD00384B1F
5311000A202020202020000000FC0050
692D4B564D0A2020202020200152
PIKVM_EDID_HEX
            EDID_CHANGED=true
        fi

    elif [[ "$edid_source" =~ ^https?:// ]]; then
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
            warn "Failed to download EDID from $edid_source."
            warn "Check the URL is reachable from the PiKVM and that HTTPS is permitted."
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

apply_vnc_quality_cap() {
    info "Applying VNC JPEG quality cap (max 15)..."

    local server_py
    server_py="$(find /usr/lib -path '*/kvmd/apps/vnc/server.py' -print -quit 2>/dev/null || true)"

    if [ -z "$server_py" ]; then
        warn "kvmd-vnc server.py not found; quality cap skipped."
        return 0
    fi

    local backup_file="${server_py}.bak.$(date +%Y%m%d-%H%M%S)"

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would back up $server_py and cap JPEG quality at 15."
        return 0
    fi

    make_rw

    cp "$server_py" "$backup_file"
    ok "Backed up $server_py to $backup_file"

    # Cap JPEG quality at 15 instead of 100 to prevent Screens client from overwhelming the stream
    if grep -q "tight_jpeg_quality, 15)" "$server_py" 2>/dev/null; then
        ok "Quality cap already applied (tight_jpeg_quality capped at 15)."
        QUALITY_CAP_CHANGED=false
    else
        if sed -i 's/tight_jpeg_quality, [0-9]\+)/tight_jpeg_quality, 15)/' "$server_py" 2>/dev/null; then
            ok "JPEG quality capped at 15 in $server_py"
            QUALITY_CAP_CHANGED=true
        else
            warn "Failed to patch $server_py; restoring backup."
            cp "$backup_file" "$server_py" || true
            return 0
        fi
    fi

    restart_service_if_exists kvmd-vnc.service
}

apply_tcp_keepalive() {
    info "Configuring TCP keepalive for Tailscale stability..."

    local sysctl_file="/etc/sysctl.d/99-pikvm-tcp-keepalive.conf"

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would write $sysctl_file with aggressive keepalive settings."
        ok "DRY RUN: would run sysctl -p $sysctl_file."
        return 0
    fi

    make_rw
    mkdir -p /etc/sysctl.d

    if [ -f "$sysctl_file" ]; then
        KEEPALIVE_BACKUP_FILE="${sysctl_file}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$sysctl_file" "$KEEPALIVE_BACKUP_FILE"
        ok "Backed up existing keepalive config to $KEEPALIVE_BACKUP_FILE"
    fi

    cat > "$sysctl_file" <<'EOF'
# PiKVM Optimizer — Aggressive TCP keepalive for Tailscale stability
# Tailscale uses userspace networking (netstack) which terminates TCP locally.
# Short keepalive intervals prevent premature connection drops (~30s timeout).
net.ipv4.tcp_keepalive_time = 10
net.ipv4.tcp_keepalive_intvl = 5
net.ipv4.tcp_keepalive_probes = 3
EOF

    if sysctl -p "$sysctl_file" >/dev/null 2>&1; then
        ok "TCP keepalive settings applied (time=10s, intvl=5s, probes=3)."
        KEEPALIVE_CHANGED=true
    else
        warn "Could not apply sysctl settings (may need reboot)."
        KEEPALIVE_CHANGED=true
    fi
}

apply_tailscale_ssl() {
    if ! command -v tailscale >/dev/null 2>&1; then
        warn "Tailscale not installed; skipped SSL certificate deploy."
        box_line "Run the Tailscale setup module (--tailscale-setup) first, then rerun this."
        return 0
    fi

    if ! tailscale status >/dev/null 2>&1; then
        warn "Tailscale not running/authenticated; skipped SSL."
        box_line "Run 'tailscale up' on the PiKVM to authenticate, then rerun."
        return 0
    fi

    info "Configuring Tailscale SSL certificate..."

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
    if ! command -v tailscale >/dev/null 2>&1; then
        warn "Tailscale not installed; skipped watchdog install."
        box_line "Run the Tailscale setup module (--tailscale-setup) first, then rerun this."
        return 0
    fi

    info "Installing Tailscale watchdog..."

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

        printf "Paste SSH public key (starts with ssh-ed25519, ssh-rsa, ecdsa-...):\n"
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

install_on_device_optimizer() {
    info "Installing/updating on-device optimizer command..."
    info "This copies the current remote optimizer to $INSTALL_PATH."
    info "Run '$INSTALL_PATH --version' on the PiKVM to check the installed version."

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would install/update current remote optimizer at $INSTALL_PATH."
        return 0
    fi

    make_rw
    mkdir -p "$(dirname "$INSTALL_PATH")"

    if [ -f "$INSTALL_PATH" ]; then
        INSTALL_BACKUP_FILE="${INSTALL_PATH}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$INSTALL_PATH" "$INSTALL_BACKUP_FILE"
        local installed_version
        installed_version="$($INSTALL_PATH --version 2>/dev/null || true)"
        if [ -n "$installed_version" ]; then
            info "Existing on-device optimizer: $installed_version"
        else
            info "Existing on-device optimizer found; version unknown."
        fi
    fi

    cp "$0" "$INSTALL_PATH"
    chmod 755 "$INSTALL_PATH"
    INSTALL_CHANGED=true

    ok "On-device optimizer installed at $INSTALL_PATH (v$REMOTE_VERSION)."
    info "Update by running the launcher again with --install; uninstall from the cleanup menu."
}

# DISABLED: apply_restricted_sudo() is fully implemented and tested but intentionally
# disabled because restricted NOPASSWD sudo introduces a security concern that needs
# careful user review before activation. The function is preserved for future use.
apply_restricted_sudo() {
    info "Configuring restricted passwordless sudo..."

    local sudo_user=""

    if [ -n "$SUDO_USER" ]; then
        sudo_user="$SUDO_USER"
    elif [ "$YES" = true ]; then
        warn "Restricted sudo requires --sudo-user for non-interactive mode; skipped."
        return 0
    else
        printf "\nNon-root user to grant restricted sudo access (e.g., 'admin'): "
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
        warn "On-device optimizer install not found; sudoers rule skipped."
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would create /etc/sudoers.d/pikvm-optimizer-$sudo_user."
        box_line "Would allow:"
        local sudo_line="  $sudo_user ALL=(root) NOPASSWD: $INSTALL_PATH"
        box_line "  ${sudo_line:0:74}"
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
# New modules (v1.3.0)
# ------------------------------------------------------------------------------

apply_tailscale_diag() {
    info "Running Tailscale networking diagnosis..."

    if ! command -v tailscale >/dev/null 2>&1; then
        warn "Tailscale not installed; skipping diagnosis."
        return 0
    fi

    local ts_ver
    ts_ver="$(tailscale version 2>/dev/null || echo "unknown")"
    ok "Tailscale version: $ts_ver"

    if tailscale status >/dev/null 2>&1; then
        ok "Tailscale is running and authenticated."
    else
        warn "Tailscale is not running or not authenticated."
        return 0
    fi

    local mode_info
    mode_info="$(journalctl -u tailscaled --no-pager -n 20 2>/dev/null | grep -oP 'New\w+Engine\([^)]+\)' | tail -1 || echo "unknown")"
    box_line "Networking engine: ${mode_info:-unknown}"

    if [ -e /dev/net/tun ]; then
        ok "TUN device exists (/dev/net/tun)."
    else
        warn "TUN device not found."
    fi

    if lsmod 2>/dev/null | grep -q "^tun"; then
        ok "TUN kernel module loaded."
    else
        info "TUN kernel module not loaded."
    fi

    if lsmod 2>/dev/null | grep -q "^wireguard"; then
        ok "WireGuard kernel module loaded."
    else
        info "WireGuard kernel module not loaded (expected on 32-bit ARM)."
    fi

    local iface_info
    iface_info="$(ip addr show tailscale0 2>/dev/null || echo "not found")"
    if echo "$iface_info" | grep -q "inet 100\."; then
        local ts_ip
        ts_ip="$(echo "$iface_info" | grep -oP 'inet \K[0-9.]+')"
        ok "tailscale0 interface active with IP: $ts_ip"
    else
        warn "tailscale0 has no Tailscale IP assigned."
    fi

    local carrier_loss
    carrier_loss="$(journalctl --no-pager 2>/dev/null | grep -c "tailscale0: Lost carrier" 2>/dev/null || echo "0")"
    if [ "$carrier_loss" -gt 0 ] 2>/dev/null; then
        warn "tailscale0 carrier losses detected in logs: $carrier_loss occurrences."
        local recent
        recent="$(journalctl --no-pager 2>/dev/null | grep "tailscale0: Lost carrier" | tail -5 | sed 's/^.*\(...[0-9]\{2\}:[0-9]\{2\}:[0-9]\{2\}\).*/\1/' | tr '\n' ' ')"
        box_line "Recent carrier loss times: ${recent:-unknown}"
        box_line "Note: carrier loss is normal for userspace WireGuard on 32-bit ARM."
        box_line "Kernel WireGuard not available on this platform; no TUN mode fix possible."
    else
        ok "No tailscale0 carrier losses detected."
    fi

    local ts_status
    ts_status="$(tailscale status --json 2>/dev/null || true)"
    if echo "$ts_status" | grep -q '"Online":true'; then
        ok "PiKVM is online on Tailscale."
    else
        warn "PiKVM may be offline on Tailscale."
    fi

    if echo "$ts_status" | grep -q '"Relay"'; then
        local relay
        relay="$(echo "$ts_status" | grep -oP '"Relay":\s*"\K[^"]+')"
        info "Connection via relay: ${relay:-unknown}"
        box_line "Recommendation: If experiencing timeouts, try enabling DERP region pinning"
        box_line "or check if direct connections are available between peers."
    fi

    ok "Tailscale diagnosis complete."
}

# ------------------------------------------------------------------------------
# Tailscale crash fix (32-bit ARM mitigation)
# ------------------------------------------------------------------------------

detect_arch() {
    local arch
    arch="$(uname -m 2>/dev/null || true)"
    case "$arch" in
        aarch64|arm64) echo "64" ;;
        armv7l|armv7|arm) echo "32" ;;
        x86_64|amd64) echo "64" ;;
        *) echo "unknown" ;;
    esac
}

apply_tailscale_crash_fix() {
    if ! command -v tailscale >/dev/null 2>&1; then
        warn "Tailscale not installed; skipped crash fix."
        box_line "Run the Tailscale setup module (--tailscale-setup) first, then rerun this."
        return 0
    fi

    info "Applying 32-bit ARM Tailscale crash mitigations..."

    local arch
    arch="$(detect_arch)"
    if [ "$arch" = "64" ]; then
        info "64-bit architecture detected ($(uname -m)). Tailscale crash bug affects 32-bit ARM only."
        ok "No crash fix needed on this platform."
        return 0
    fi

    if [ "$arch" = "unknown" ]; then
        warn "Unknown architecture ($(uname -m)); skipping crash fix (only needed on 32-bit ARM)."
        return 0
    fi

    info "32-bit ARM detected. Tailscale/gVisor has a known 64-bit atomic alignment crash on this platform."
    ok "Applying mitigations for Tailscale crash cycle..."

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would disable IPv6 on tailscale0 (sysctl + persistent config)."
        ok "DRY RUN: would set systemd watchdog to 15s with 1s restart delay."
        ok "DRY RUN: would reload systemd daemon and restart tailscaled."
        return 0
    fi

    make_rw

    # --- IPv6 sysctl ---
    local sysctl_file="/etc/sysctl.d/60-tailscale0-ipv6.conf"
    if [ -f "$sysctl_file" ]; then
        CRASH_FIX_SYSCTL_BACKUP="${sysctl_file}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$sysctl_file" "$CRASH_FIX_SYSCTL_BACKUP"
        ok "Backed up existing sysctl config to $CRASH_FIX_SYSCTL_BACKUP"
    fi
    cat > "$sysctl_file" <<'EOF'
# Disable IPv6 on tailscale0 to avoid gVisor netstack code paths
# that trigger 64-bit atomic alignment crashes on 32-bit ARM.
net.ipv6.conf.tailscale0.disable_ipv6 = 1
EOF
    ok "Wrote $sysctl_file"

    # Apply immediately if interface exists
    if ip link show tailscale0 >/dev/null 2>&1; then
        sysctl -w net.ipv6.conf.tailscale0.disable_ipv6=1 >/dev/null 2>&1 || true
        ok "Applied sysctl to tailscale0 immediately."
    else
        info "tailscale0 not present yet; sysctl will apply when interface is created."
    fi

    # --- Systemd watchdog override ---
    local override_dir="/etc/systemd/system/tailscaled.service.d"
    local override_file="$override_dir/override.conf"
    mkdir -p "$override_dir"

    if [ -f "$override_file" ]; then
        CRASH_FIX_OVERRIDE_BACKUP="${override_file}.bak.$(date +%Y%m%d-%H%M%S)"
        cp "$override_file" "$CRASH_FIX_OVERRIDE_BACKUP"
        ok "Backed up existing override.conf to $CRASH_FIX_OVERRIDE_BACKUP"
    fi
    cat > "$override_file" <<'EOF'
[Service]
# Fast crash detection: 15s watchdog + 1s restart = ~23s total cycle
# The gVisor alignment bug on 32-bit ARM causes tailscaled to hang every ~30s.
# This reduces downtime from ~38s (with 30s watchdog) to ~23s.
WatchdogSec=15s
Restart=always
RestartSec=1s
EOF
    ok "Wrote $override_file (WatchdogSec=15s, RestartSec=1s)"

    systemctl daemon-reload 2>/dev/null || true

    if systemctl is-active tailscaled.service >/dev/null 2>&1; then
        systemctl restart tailscaled.service 2>/dev/null || true
        ok "Restarted tailscaled.service with new watchdog config."
    else
        info "tailscaled.service not active; will apply watchdog config on next start."
    fi

    ok "Tailscale crash fix applied."
    TAILSCALE_CRASH_FIX_EXECUTED=true
    warn "This is a mitigation, not a fix. The gVisor alignment bug is unfixable on 32-bit ARM."
    warn "Long-term: migrate to a 64-bit OS (aarch64) to eliminate this issue entirely."
}

uninstall_tailscale_crash_fix() {
    info "Removing Tailscale crash fix..."

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would remove /etc/sysctl.d/60-tailscale0-ipv6.conf."
        ok "DRY RUN: would remove /etc/systemd/system/tailscaled.service.d/override.conf (and restore backup)."
        return 0
    fi

    make_rw

    local sysctl_file="/etc/sysctl.d/60-tailscale0-ipv6.conf"
    if [ -f "$sysctl_file" ]; then
        rm -f "$sysctl_file"
        ok "Removed $sysctl_file"
        # Re-enable IPv6 on tailscale0 if interface exists (side effect of removal)
        if ip link show tailscale0 >/dev/null 2>&1; then
            sysctl -w net.ipv6.conf.tailscale0.disable_ipv6=0 >/dev/null 2>&1 || true
        fi
    else
        info "Sysctl config not found; nothing to remove."
    fi

    local override_file="/etc/systemd/system/tailscaled.service.d/override.conf"
    if [ -f "$override_file" ]; then
        local backup
        backup="$(ls -t "${override_file}.bak."* 2>/dev/null | head -1 || true)"
        if [ -n "$backup" ]; then
            cp "$backup" "$override_file"
            ok "Restored override.conf from backup: $backup"
        else
            rm -f "$override_file"
            ok "Removed $override_file (no backup found)"
        fi
    else
        info "override.conf not found; nothing to remove."
    fi

    systemctl daemon-reload 2>/dev/null || true
    ok "Tailscale crash fix removed."
}

generate_wifi_password() {
    tr -d '-' </proc/sys/kernel/random/uuid | cut -c1-16
}

wifi_interfaces() {
    iw dev 2>/dev/null | awk '$1 == "Interface" { print $2 }'
}

scan_wifi_ssids() {
    local iface="$1"
    ip link set "$iface" up >/dev/null 2>&1 || true
    iw dev "$iface" scan 2>/dev/null \
        | awk -F'SSID: ' '/SSID: / { if ($2 != "") print $2 }' \
        | awk '!seen[$0]++' \
        | head -20
}

apply_wifi() {
    info "Configuring WiFi client/AP fallback..."

    if ! command -v iw >/dev/null 2>&1; then
        warn "iw not installed; skipped WiFi setup."
        return 0
    fi
    if ! command -v wpa_passphrase >/dev/null 2>&1; then
        warn "wpa_passphrase not installed; skipped WiFi setup."
        return 0
    fi
    if ! command -v hostapd >/dev/null 2>&1; then
        warn "hostapd not installed; skipped WiFi AP setup."
        return 0
    fi
    if ! command -v dnsmasq >/dev/null 2>&1; then
        warn "dnsmasq not installed; skipped WiFi AP setup."
        return 0
    fi

    local ifaces=()
    local iface
    while IFS= read -r iface; do
        [ -n "$iface" ] && ifaces+=("$iface")
    done < <(wifi_interfaces)

    if [ "${#ifaces[@]}" -eq 0 ]; then
        warn "No WiFi interfaces found; plug in/enable WiFi and rerun."
        return 0
    fi

    local client_iface="${ifaces[0]}"
    local ap_iface="${ifaces[0]}"
    local simultaneous=false
    if [ "${#ifaces[@]}" -gt 1 ]; then
        ap_iface="${ifaces[1]}"
        simultaneous=true
    fi

    local client_ssid="$WIFI_SSID"
    local client_pass=""
    local country="${WIFI_COUNTRY:-US}"
    local ap_ssid="PiKVM-${HOSTNAME:-pikvm}"
    local ap_pass
    local ap_ssid_input=""
    local ap_pass_input=""
    ap_pass="$(generate_wifi_password)"
    ap_ssid="${WIFI_AP_SSID:-$ap_ssid}"

    if [ "$YES" = true ]; then
        if [ -n "$client_ssid" ]; then
            warn "Non-interactive WiFi setup cannot read the password for '$client_ssid'; client WiFi skipped."
            client_ssid=""
        else
            warn "Non-interactive WiFi setup: client WiFi skipped; AP fallback will be configured."
        fi
        warn "Generated AP credentials will be shown once; save them now."
    else
        local scanned_ssids=()
        local scanned_ssid=""
        while IFS= read -r scanned_ssid; do
            [ -n "$scanned_ssid" ] && scanned_ssids+=("$scanned_ssid")
        done < <(scan_wifi_ssids "$client_iface")

        if [ "${#scanned_ssids[@]}" -gt 0 ]; then
            printf "\nDetected WiFi networks on %s:\n" "$client_iface"
            local idx=1
            for scanned_ssid in "${scanned_ssids[@]}"; do
                printf "  %d) %s\n" "$idx" "$scanned_ssid"
                idx=$((idx + 1))
            done
            if [ -n "$client_ssid" ]; then
                printf "Choose network number, type SSID manually, Enter for '%s', or blank '-' to skip client mode: " "$client_ssid"
            else
                printf "Choose network number, type SSID manually, or leave blank to skip client mode: "
            fi
        else
            if [ -n "$client_ssid" ]; then
                printf "\nNo WiFi networks detected on %s. Type SSID manually, Enter for '%s', or blank '-' to skip client mode: " "$client_iface" "$client_ssid"
            else
                printf "\nNo WiFi networks detected on %s. Type SSID manually or leave blank to skip client mode: " "$client_iface"
            fi
        fi
        local client_ssid_input=""
        read -r client_ssid_input
        if [ "$client_ssid_input" = "-" ]; then
            client_ssid=""
        elif [ -n "$client_ssid_input" ]; then
            client_ssid="$client_ssid_input"
        fi
        if [ -n "$client_ssid" ] && printf "%s" "$client_ssid" | grep -qE '^[0-9]+$'; then
            local selected_index=$((client_ssid - 1))
            if [ "$selected_index" -ge 0 ] && [ "$selected_index" -lt "${#scanned_ssids[@]}" ]; then
                client_ssid="${scanned_ssids[$selected_index]}"
            fi
        fi
        if [ -n "$client_ssid" ]; then
            printf "Selected WiFi SSID: %s\n" "$client_ssid"
            printf "WiFi client password (min 8 chars; blank skips client WiFi): "
            stty -echo 2>/dev/null || true
            read -r client_pass
            stty echo 2>/dev/null || true
            printf "\n"
        fi
        printf "Country code [$country]: "
        local country_input=""
        read -r country_input
        country="${country_input:-$country}"
        printf "Fallback AP SSID (hotspot PiKVM creates when client WiFi is unavailable) [$ap_ssid]: "
        read -r ap_ssid_input
        ap_ssid="${ap_ssid_input:-$ap_ssid}"
        printf "Fallback AP password [generated]: "
        stty -echo 2>/dev/null || true
        read -r ap_pass_input
        stty echo 2>/dev/null || true
        printf "\n"
        ap_pass="${ap_pass_input:-$ap_pass}"
    fi

    if [ "${#ap_pass}" -lt 8 ] || [ "${#ap_pass}" -gt 63 ]; then
        warn "AP password must be 8-63 characters; skipped WiFi setup."
        return 0
    fi
    if [ -n "$client_ssid" ] && [ "${#client_pass}" -lt 8 ]; then
        warn "Client WiFi password must be at least 8 characters; skipped client config."
        client_ssid=""
        client_pass=""
    fi

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would configure client interface $client_iface and AP interface $ap_iface."
        ok "DRY RUN: AP SSID would be $ap_ssid."
        return 0
    fi

    make_rw
    mkdir -p /etc/systemd/network /etc/wpa_supplicant /etc/hostapd /etc/systemd/system

    cat > "/etc/systemd/network/25-${client_iface}.network" <<EOF
[Match]
Name=${client_iface}

[Network]
DHCP=yes
DNSSEC=no

[DHCP]
ClientIdentifier=mac
RouteMetric=50
EOF

    if [ -n "$client_ssid" ]; then
        {
            printf "country=%s\n" "$country"
            wpa_passphrase "$client_ssid" "$client_pass" | grep -v '^[[:space:]]*#psk='
        } > "/etc/wpa_supplicant/wpa_supplicant-${client_iface}.conf"
        chmod 640 "/etc/wpa_supplicant/wpa_supplicant-${client_iface}.conf"
        ok "Configured WiFi client network for $client_iface."
    fi

    cat > /usr/local/bin/pikvm-wifi-auto.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail

CLIENT_ENABLED="$( [ -n "$client_ssid" ] && printf true || printf false )"
AP_ADDR="10.77.77.1/24"
AP_IP="10.77.77.1"
DHCP_RANGE="10.77.77.50,10.77.77.150,12h"
COUNTRY="${country}"
AP_SSID="${ap_ssid}"
AP_PASS="${ap_pass}"

wifi_interfaces() {
    iw dev 2>/dev/null | awk '\$1 == "Interface" { print \$2 }'
}

choose_ifaces() {
    mapfile -t WIFI_IFACES < <(wifi_interfaces)
    if [ "\${#WIFI_IFACES[@]}" -eq 0 ]; then
        exit 0
    fi
    CLIENT_IFACE="\${WIFI_IFACES[0]}"
    AP_IFACE="\${WIFI_IFACES[0]}"
    SIMULTANEOUS=false
    if [ "\${#WIFI_IFACES[@]}" -gt 1 ]; then
        AP_IFACE="\${WIFI_IFACES[1]}"
        SIMULTANEOUS=true
    fi
}

has_default_route() {
    ip route show default 2>/dev/null | grep -q .
}

start_client() {
    [ "\$CLIENT_ENABLED" = true ] || return 0
    systemctl enable --now systemd-networkd.service >/dev/null 2>&1 || true
    systemctl enable --now "wpa_supplicant@\${CLIENT_IFACE}.service" >/dev/null 2>&1 || true
}

stop_ap() {
    systemctl stop "hostapd@\${AP_IFACE}.service" >/dev/null 2>&1 || true
    systemctl stop pikvm-wifi-ap-dnsmasq.service >/dev/null 2>&1 || true
}

start_ap() {
    if [ "\$SIMULTANEOUS" != true ]; then
        systemctl stop "wpa_supplicant@\${CLIENT_IFACE}.service" >/dev/null 2>&1 || true
    fi
    cat > "/etc/hostapd/\${AP_IFACE}.conf" <<APCONF
interface=\${AP_IFACE}
driver=nl80211
country_code=\${COUNTRY}
ssid=\${AP_SSID}
hw_mode=g
channel=6
ieee80211n=1
wmm_enabled=1
auth_algs=1
wpa=2
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
wpa_passphrase=\${AP_PASS}
APCONF
    chmod 640 "/etc/hostapd/\${AP_IFACE}.conf"
    cat > /run/pikvm-wifi-dnsmasq.conf <<DNSCONF
interface=\${AP_IFACE}
bind-interfaces
dhcp-range=\${DHCP_RANGE}
dhcp-option=3,\${AP_IP}
dhcp-option=6,\${AP_IP}
DNSCONF
    ip link set "\$AP_IFACE" up >/dev/null 2>&1 || true
    ip addr flush dev "\$AP_IFACE" >/dev/null 2>&1 || true
    ip addr add "\$AP_ADDR" dev "\$AP_IFACE" >/dev/null 2>&1 || true
    systemctl start "hostapd@\${AP_IFACE}.service" >/dev/null 2>&1 || true
    systemctl start pikvm-wifi-ap-dnsmasq.service >/dev/null 2>&1 || true
}

choose_ifaces

if [ "\$SIMULTANEOUS" = true ]; then
    start_client
    start_ap
    exit 0
fi

start_client
sleep 25
if has_default_route; then
    stop_ap
else
    start_ap
fi
EOF
    chmod 700 /usr/local/bin/pikvm-wifi-auto.sh

    cat > /etc/systemd/system/pikvm-wifi-ap-dnsmasq.service <<EOF
[Unit]
Description=PiKVM fallback WiFi AP DHCP/DNS
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/dnsmasq --no-daemon --conf-file=/run/pikvm-wifi-dnsmasq.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/pikvm-wifi-auto.service <<'EOF'
[Unit]
Description=PiKVM WiFi client/AP auto mode
After=network.target systemd-networkd.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/pikvm-wifi-auto.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/pikvm-wifi-auto.timer <<'EOF'
[Unit]
Description=Re-evaluate PiKVM WiFi client/AP mode

[Timer]
OnBootSec=30s
OnUnitActiveSec=2min
Unit=pikvm-wifi-auto.service

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl enable --now pikvm-wifi-auto.timer >/dev/null 2>&1 || true
    systemctl start pikvm-wifi-auto.service >/dev/null 2>&1 || true

    ok "WiFi auto mode configured."
    WIFI_EXECUTED=true
    box_line "Client iface: $client_iface"
    box_line "AP iface: $ap_iface"
    box_line "AP SSID: $ap_ssid"
    box_line "AP password: $ap_pass"
    box_line "AP URL after fallback: https://10.77.77.1/"
}

uninstall_wifi() {
    info "Removing WiFi auto configuration..."
    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would remove PiKVM WiFi auto services and generated configs."
        return 0
    fi
    make_rw
    systemctl disable --now pikvm-wifi-auto.timer pikvm-wifi-auto.service pikvm-wifi-ap-dnsmasq.service >/dev/null 2>&1 || true
    rm -f /usr/local/bin/pikvm-wifi-auto.sh
    rm -f /etc/systemd/system/pikvm-wifi-auto.service /etc/systemd/system/pikvm-wifi-auto.timer /etc/systemd/system/pikvm-wifi-ap-dnsmasq.service
    rm -f /etc/systemd/network/25-wlan*.network /etc/wpa_supplicant/wpa_supplicant-wlan*.conf /etc/hostapd/wlan*.conf
    systemctl daemon-reload >/dev/null 2>&1 || true
    ok "WiFi auto configuration removed."
}

apply_root_password() {
    info "Changing root password..."
    box_line "This changes the Linux root password used for SSH, serial console, and su -."
    box_line "It is separate from the Web/KVM admin password."
    if [ "$YES" = true ]; then
        warn "Root password change requires interactive input; skipped in non-interactive mode."
        return 0
    fi
    local pass1 pass2
    local attempts=0
    while [ "$attempts" -lt 3 ]; do
        printf "New root password: "
        stty -echo 2>/dev/null || true
        read -r pass1
        stty echo 2>/dev/null || true
        printf "\n"
        printf "Confirm root password: "
        stty -echo 2>/dev/null || true
        read -r pass2
        stty echo 2>/dev/null || true
        printf "\n"

        if [ -z "$pass1" ]; then
            warn "Password empty; skipped root password change."
            return 0
        fi
        if [ "$pass1" = "$pass2" ]; then
            break
        fi
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 3 ]; then
            err "Passwords did not match after 3 attempts; root password not changed."
            return 1
        fi
        warn "Passwords did not match. Try again (attempt $((attempts + 1))/3)."
    done
    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would change root password."
        return 0
    fi
    make_rw
    if printf 'root:%s\n' "$pass1" | chpasswd; then
        ok "Root password changed."
        ROOT_PASSWORD_EXECUTED=true
    else
        err "chpasswd reported failure; root password not changed."
        warn "Ensure this script runs as root on the PiKVM and disk is not full."
        return 1
    fi
}

apply_first_run() {
    info "Running first-run setup..."
    box_line "This changes the PiKVM Web UI/API/VNC admin password."
    box_line "It is separate from the Linux root password used for SSH."
    if [ "$YES" = true ]; then
        warn "First-run setup requires interactive password input; skipped in non-interactive mode."
        return 0
    fi
    if ! command -v kvmd-htpasswd >/dev/null 2>&1; then
        warn "kvmd-htpasswd not found; skipped Web UI password setup."
        return 0
    fi
    local pass1 pass2
    local attempts=0
    while [ "$attempts" -lt 3 ]; do
        printf "New Web/KVM admin password for user 'admin': "
        stty -echo 2>/dev/null || true
        read -r pass1
        stty echo 2>/dev/null || true
        printf "\n"
        printf "Confirm Web/KVM admin password: "
        stty -echo 2>/dev/null || true
        read -r pass2
        stty echo 2>/dev/null || true
        printf "\n"

        if [ -z "$pass1" ]; then
            warn "Password empty; skipped Web UI password change."
            return 0
        fi
        if [ "$pass1" = "$pass2" ]; then
            break
        fi
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 3 ]; then
            err "Passwords did not match after 3 attempts; Web UI password not changed."
            return 1
        fi
        warn "Passwords did not match. Try again (attempt $((attempts + 1))/3)."
    done
    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would change Web/KVM admin password."
        return 0
    fi
    make_rw
    if printf '%s\n%s\n' "$pass1" "$pass2" | kvmd-htpasswd set admin >/dev/null; then
        ok "Web/KVM admin password changed."
        ADMIN_PASSWORD_EXECUTED=true
    else
        err "kvmd-htpasswd reported failure; Web/KVM admin password not changed."
        warn "Verify kvmd-htpasswd is functional: kvmd-htpasswd set admin"
        return 1
    fi
}

apply_2fa() {
    info "Configuring PiKVM 2FA..."
    if ! command -v kvmd-totp >/dev/null 2>&1; then
        warn "kvmd-totp not found; skipped 2FA setup."
        return 0
    fi
    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would initialize or show PiKVM TOTP secret."
        return 0
    fi
    make_rw
    mkdir -p /etc/kvmd/override.d
    local totp_tmp
    totp_tmp="$(mktemp /tmp/pikvm-optimizer-totp.XXXXXXXXXX)"
    chmod 600 "$totp_tmp"
    local already_existing=false
    if kvmd-totp show >"$totp_tmp" 2>/dev/null; then
        warn "2FA already configured; showing existing QR/secret."
        already_existing=true
    else
        if kvmd-totp init >"$totp_tmp"; then
            ok "2FA initialized."
            TFA_EXECUTED=true
        else
            rm -f "$totp_tmp"
            err "kvmd-totp init returned an error; 2FA not configured."
            warn "Check that kvmd-totp is functional by running 'kvmd-totp init' directly on the PiKVM."
            return 1
        fi
    fi

    # Extract secret for later verification
    local secret
    secret=$(grep '^Secret: ' "$totp_tmp" | sed 's/^Secret: //')

    # Close the box section so the QR code renders without border corruption
    # (QR block characters are double-width and break box_line's padding math)
    box_sep
    while IFS= read -r line; do
        printf "%s\n" "$line"
    done <"$totp_tmp"
    printf "\n"
    rm -f "$totp_tmp"

    # Verify TOTP code for newly initialized secrets
    if [ "$already_existing" = false ] && [ "$YES" = false ] && [ -n "$secret" ]; then
        local attempts=0
        while [ "$attempts" -lt 3 ]; do
            printf "Enter a 6-digit code from your authenticator app to verify setup"
            [ "$attempts" -gt 0 ] && printf " (attempt $((attempts + 1))/3)"
            printf " [s=skip, d=disable]: "
            read -r verify_code

            case "$verify_code" in
                s|S)
                    warn "Verification skipped; you can retry with --2fa later."
                    break
                    ;;
                d|D)
                    make_rw
                    kvmd-totp del >/dev/null 2>&1 || true
                    warn "2FA disabled."
                    return 0
                    ;;
            esac

            if [ -n "$verify_code" ] && printf '%s' "$secret" | python3 -c "
import pyotp, sys
secret = sys.stdin.read().strip()
code = sys.argv[1]
sys.exit(0 if pyotp.TOTP(secret).verify(code) else 1)
" "$verify_code" 2>/dev/null; then
                box_line "${G}[OK]${RESET} TOTP code verified."
                break
            fi

            attempts=$((attempts + 1))
            if [ "$attempts" -ge 3 ]; then
                err "Verification failed after 3 attempts."
                warn "Run --2fa again to retry, or use 'kvmd-totp show' on the PiKVM."
                return 1
            fi
            [ -z "$verify_code" ] && warn "No code entered." || warn "That code didn't work."
            warn "Enter s to skip, d to disable, or try again:"
        done
    fi
    box_sep
}

uninstall_2fa() {
    info "Removing PiKVM 2FA..."
    if ! command -v kvmd-totp >/dev/null 2>&1; then
        warn "kvmd-totp not found; skipped 2FA removal."
        return 0
    fi
    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would remove PiKVM TOTP secret."
        return 0
    fi
    make_rw
    mkdir -p /etc/kvmd/override.d
    kvmd-totp del >/dev/null 2>&1 || true
    ok "2FA removed."
}

apply_msd_bios_fix() {
    info "Applying MSD BIOS compatibility mode..."

    if ! python_yaml_available; then
        warn "Python YAML module required; cannot apply MSD BIOS fix."
        return 0
    fi

    local patch="/tmp/pikvm-optimizer.msd-bios.yaml"

    cat > "$patch" <<'EOF'
otg:
    devices:
        msd:
            start: false
EOF

    if [ "$DRY_RUN" = true ]; then
        rm -f "$patch"
        ok "DRY RUN: would set otg.devices.msd.start: false via $patch."
        return 0
    fi

    merge_yaml_patch "$patch"
    rm -f "$patch"
    MSD_BIOS_FIX_CHANGED=true
    ok "MSD BIOS compatibility applied (otg.devices.msd.start: false)."
    box_line "This prevents UEFI boot-loop on Dell/HP systems (GitHub #1569)."
}

apply_usb_preset() {
    info "Configuring USB device preset..."

    if ! python_yaml_available; then
        warn "Python YAML module required; cannot configure USB preset."
        return 0
    fi

    local preset=""
    if [ "$YES" = true ]; then
        warn "Non-interactive mode: defaulting to BIOS-safe preset (keyboard + relative mouse)."
        preset="bios"
    else
        printf "\nSelect USB preset:\n"
        printf "  n) Normal - keyboard + absolute mouse + MSD + HID (default)\n"
        printf "  b) BIOS   - keyboard + relative mouse only (UEFI compatibility)\n"
        printf "Choice [n/b]: "
        read -r preset
        case "$preset" in
            b|B|bios|BIOS) preset="bios" ;;
            *) preset="normal" ;;
        esac
    fi

    local patch="/tmp/pikvm-optimizer.usb-preset.yaml"

    if [ "$preset" = "bios" ]; then
        cat > "$patch" <<'EOF'
otg:
    devices:
        keyboard:
            type: keyboard
            bind: 0
        mouse:
            type: mouse
            bind: 0
EOF
    else
        cat > "$patch" <<'EOF'
otg:
    devices:
        keyboard:
            type: keyboard
            bind: 0
        mouse:
            type: mouse
            bind: 0
        msd:
            type: msd
            bind: 0
        hid:
            type: hid
            bind: 0
EOF
    fi

    if [ "$DRY_RUN" = true ]; then
        rm -f "$patch"
        ok "DRY RUN: would apply USB preset: $preset"
        return 0
    fi

    merge_yaml_patch "$patch"
    rm -f "$patch"
    USB_PRESET_CHANGED=true
    ok "USB preset applied: $preset"
}

apply_usb_extra() {
    info "Configuring USB extras..."

    if ! python_yaml_available; then
        warn "Python YAML module required; cannot configure USB extras."
        return 0
    fi

    local do_eth=false
    local do_serial=false
    local do_audio=false

    if [ "$YES" = true ]; then
        warn "Non-interactive mode: enabling all USB extras."
        do_eth=true
        do_serial=true
        do_audio=true
    else
        printf "\nEnable USB extras (select all that apply):\n"
        printf "  e) USB Ethernet (RNDIS/ECM) - network-over-USB\n"
        printf "  s) USB Serial (ACM) - serial console access\n"
        printf "  a) USB Audio (UAC2) - audio over USB\n"
        printf "  x) All of the above\n"
        printf "  (blank to skip)\n"
        printf "Selection [e/s/a/x]: "
        read -r extras_choice
        case "$extras_choice" in
            e|E|eth|Ethernet) do_eth=true ;;
            s|S|serial|Serial) do_serial=true ;;
            a|A|audio|Audio) do_audio=true ;;
            x|X|all|All) do_eth=true; do_serial=true; do_audio=true ;;
            *) warn "No USB extras selected."; return 0 ;;
        esac
    fi

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would enable USB extras (eth=$do_eth serial=$do_serial audio=$do_audio)."
        return 0
    fi

    if [ "$do_eth" = true ] || [ "$do_serial" = true ] || [ "$do_audio" = true ]; then
        local patch="/tmp/pikvm-optimizer.usb-extra.yaml"
        {
            echo "otg:"
            echo "  devices:"
            [ "$do_eth" = true ] && echo "    ethernet:" && echo "      type: ethernet" && echo "      bind: 0"
            [ "$do_serial" = true ] && echo "    serial:" && echo "      type: serial" && echo "      bind: 0"
            [ "$do_audio" = true ] && echo "    audio:" && echo "      type: audio" && echo "      bind: 0"
        } > "$patch"

        if [ "$DRY_RUN" = true ]; then
            rm -f "$patch"
            ok "DRY RUN: would enable USB extras."
            return 0
        fi

        merge_yaml_patch "$patch"
        rm -f "$patch"
        USB_EXTRA_CHANGED=true
        ok "USB extras configuration applied."
    fi
}

apply_msd_storage() {
    info "Configuring network storage for MSD ISOs..."

    if [ "$YES" = true ]; then
        warn "Network storage setup requires interactive input; skipped in --yes mode."
        return 0
    fi

    printf "\nNetwork storage for MSD ISO images\n"
    printf "This permanently mounts an existing NFS/SMB share so PiKVM can browse ISOs from it.\n"
    printf "You need the storage server address/name and exported path/share now.\n"
    printf "If you have not created a network share yet, leave this blank and rerun --msd-storage later.\n\n"
    printf "Protocol (nfs/smb, blank to skip) [nfs]: "
    read -r proto
    if [ -z "$proto" ]; then
        warn "No protocol selected; skipping network storage."
        return 0
    fi

    case "$proto" in
        nfs|NFS)
            proto="nfs"
            printf "NFS server IP/hostname (e.g., 192.168.1.100 or nas.local; blank to skip): "
            read -r server
            [ -z "$server" ] && { warn "Server required; skipping."; return 0; }
            printf "NFS export path on that server (e.g., /volume1/iso; blank to skip): "
            read -r export_path
            [ -z "$export_path" ] && { warn "Export path required; skipping."; return 0; }
            local mount_opts="soft,noatime,nofail"
            local fstab_line="$server:$export_path"
            local pkg="nfs-utils"
            local svc_check="systemctl is-active nfs-client.target >/dev/null 2>&1"
            ;;
        smb|SMB|cifs|CIFS)
            proto="cifs"
            printf "SMB server IP/hostname (e.g., 192.168.1.100 or nas.local; blank to skip): "
            read -r server
            [ -z "$server" ] && { warn "Server required; skipping."; return 0; }
            printf "SMB share path on that server (e.g., /isos or /shares/iso; blank to skip): "
            read -r export_path
            [ -z "$export_path" ] && { warn "Share path required; skipping."; return 0; }
            printf "SMB username [guest]: "
            read -r smb_user
            smb_user="${smb_user:-guest}"
            printf "SMB password (leave blank for guest): "
            read -r -s smb_pass
            echo ""
            local mount_opts="soft,noatime,nofail,username=$smb_user"
            [ -n "$smb_pass" ] && mount_opts="$mount_opts,password=$smb_pass"
            local fstab_line="//$server$export_path"
            local pkg="cifs-utils"
            local svc_check="true"
            ;;
        *)
            warn "Unknown protocol '$proto'; skipping."
            return 0
            ;;
    esac

    printf "Local mount point [/mnt/msd-isos]: "
    read -r mount_point
    mount_point="${mount_point:-/mnt/msd-isos}"

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would install $pkg, create $mount_point, mount $fstab_line."
        return 0
    fi

    make_rw
    info "Installing $pkg if missing..."
    if ! command -v "${pkg%-utils}" >/dev/null 2>&1; then
        if command -v pacman >/dev/null 2>&1; then
            pacman -S --noconfirm "$pkg" >/dev/null 2>&1 && ok "Installed $pkg." || warn "Failed to install $pkg."
        elif command -v apt-get >/dev/null 2>&1; then
            apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq "$pkg" >/dev/null 2>&1 && ok "Installed $pkg." || warn "Failed to install $pkg."
        else
            warn "No package manager found; please install $pkg manually."
        fi
    else
        ok "$pkg already installed."
    fi

    mkdir -p "$mount_point"

    local fstab_marker="# pikvm-optimizer-msd-storage"

    if grep -qF -- " $mount_point " /etc/fstab 2>/dev/null; then
        warn "Mount point $mount_point already in fstab; not duplicating."
    else
        if [ -f /etc/fstab ]; then
            cp /etc/fstab /etc/fstab.bak.$(date +%Y%m%d-%H%M%S)
        fi
        if [ "$proto" = "nfs" ]; then
            echo "$server:$export_path  $mount_point  nfs  $mount_opts  0  0  $fstab_marker" >> /etc/fstab
        else
            echo "$fstab_line  $mount_point  cifs  $mount_opts  0  0  $fstab_marker" >> /etc/fstab
        fi
        ok "Added fstab entry for $mount_point."
    fi

    if mount "$mount_point" 2>/dev/null; then
        ok "Mounted $mount_point successfully."
    else
        warn "Mount failed; check server and path."
        box_line "You can rerun --msd-storage later after the share/server is ready."
    fi

    MSD_STORAGE_CHANGED=true
}

apply_msd_drives() {
    info "Configuring additional MSD drives..."

    if ! python_yaml_available; then
        warn "Python YAML module required; cannot configure MSD drives."
        return 0
    fi

    local num_drives=2
    if [ "$YES" = false ]; then
        printf "\nNumber of MSD drives (1-2, blank to skip) [2]: "
        read -r num_input
        if [ -z "$num_input" ]; then
            warn "No MSD drives configured; skipping."
            return 0
        fi
        num_drives="$num_input"
        case "$num_drives" in
            1) num_drives=1 ;;
            2) num_drives=2 ;;
            *) warn "Invalid number '$num_drives'; skipping MSD drives."; return 0 ;;
        esac
    fi

    local patch="/tmp/pikvm-optimizer.msd-drives.yaml"

    if [ "$num_drives" -ge 2 ]; then
        cat > "$patch" <<'EOF'
otg:
    devices:
        msd:
            type: msd
            bind: 0
        msd_data:
            type: msd
            bind: 0
EOF
    else
        cat > "$patch" <<'EOF'
otg:
    devices:
        msd:
            type: msd
            bind: 0
EOF
    fi

    if [ "$DRY_RUN" = true ]; then
        rm -f "$patch"
        ok "DRY RUN: would configure $num_drives MSD drive(s)."
        return 0
    fi

    merge_yaml_patch "$patch"
    rm -f "$patch"
    MSD_DRIVES_CHANGED=true
    ok "MSD drives configured: $num_drives drive(s)"
}

apply_override_d() {
    info "Enabling override.d YAML fragment support..."

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would create /etc/kvmd/override.d/ directory."
        return 0
    fi

    make_rw
    mkdir -p /etc/kvmd/override.d

    if [ -f /etc/kvmd/override.yaml ]; then
        local migrate_content
        migrate_content="$(grep -v '^[[:space:]]*#' /etc/kvmd/override.yaml | sed '/^[[:space:]]*$/d' 2>/dev/null || true)"
        if [ -n "$migrate_content" ] && [ "$migrate_content" != "kvmd: {}" ] && [ "$migrate_content" != "{}" ]; then
            if [ ! -f /etc/kvmd/override.d/00-custom.yaml ]; then
                cp /etc/kvmd/override.yaml /etc/kvmd/override.d/00-custom.yaml
                ok "Migrated current override.yaml to override.d/00-custom.yaml."
            else
                ok "override.d/00-custom.yaml already exists; not overwriting."
            fi
        fi
    fi

    # Embed documentation as YAML comments in the migrated file
    local doc_comment="# PiKVM override.d directory - YAML fragments loaded alphabetically after override.yaml
# Created by PiKVM Optimizer v1.3.0
# Use numbered prefixes to control load order (e.g., 00-base.yaml, 99-custom.yaml)"
    if [ -f /etc/kvmd/override.d/00-custom.yaml ]; then
        local first_line
        first_line="$(head -1 /etc/kvmd/override.d/00-custom.yaml 2>/dev/null || true)"
        if [ "$first_line" != "# PiKVM override.d directory - YAML fragments loaded alphabetically after override.yaml" ]; then
            {
                echo "$doc_comment"
                echo ""
                cat /etc/kvmd/override.d/00-custom.yaml
            } > /etc/kvmd/override.d/00-custom.yaml.tmp
            mv /etc/kvmd/override.d/00-custom.yaml.tmp /etc/kvmd/override.d/00-custom.yaml
        fi
    fi

    ok "override.d directory created at /etc/kvmd/override.d/"
    box_line "Place YAML fragment files in /etc/kvmd/override.d/ to override settings."
    OVERRIDE_D_CHANGED=true
}

# ------------------------------------------------------------------------------
# Uninstall / restore / health
# ------------------------------------------------------------------------------

uninstall_core_config() {
    info "Removing optimizer-managed core YAML keys..."
    delete_yaml_paths \
        kvmd.streamer.h264_gop \
        kvmd.streamer.quality \
        kvmd.streamer.h264_bitrate \
        vnc.auth.vncauth.enabled
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

uninstall_tcp_keepalive() {
    info "Removing TCP keepalive sysctl config..."

    local sysctl_file="/etc/sysctl.d/99-pikvm-tcp-keepalive.conf"

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would remove $sysctl_file."
        return 0
    fi

    make_rw
    rm -f "$sysctl_file"
    ok "Removed $sysctl_file."
    warn "Keepalive changes persist until reboot or 'sysctl -p' reload."
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

uninstall_quality_cap() {
    info "Restoring VNC quality cap from backup..."

    local server_py
    server_py="$(find /usr/lib -path '*/kvmd/apps/vnc/server.py' -print -quit 2>/dev/null || true)"

    if [ -z "$server_py" ]; then
        warn "kvmd-vnc server.py not found; quality cap restore skipped."
        return 0
    fi

    local latest_backup=""
    latest_backup="$(ls -t "${server_py}.bak."* 2>/dev/null | head -n 1 || true)"

    if [ -z "$latest_backup" ]; then
        warn "No VNC server.py backup found; quality cap may still be applied."
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would restore $server_py from $latest_backup."
        return 0
    fi

    make_rw
    cp "$latest_backup" "$server_py"
    ok "Restored $server_py from backup $latest_backup."
    restart_service_if_exists kvmd-vnc.service
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

    printf "Paste exact SSH public key to remove (same format as install):\n"
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

uninstall_on_device_optimizer() {
    info "Removing on-device optimizer command..."

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would remove $INSTALL_PATH."
        return 0
    fi

    make_rw
    rm -f "$INSTALL_PATH"
    ok "Removed $INSTALL_PATH."
}

uninstall_sudoers() {
    info "Removing optimizer-managed sudoers rules..."

    local files
    files="$(ls /etc/sudoers.d/pikvm-optimizer-* 2>/dev/null || true)"
    if [ -z "$files" ]; then
        info "No optimizer-managed sudoers rules found."
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would remove optimizer-managed sudoers rules."
        return 0
    fi

    make_rw
    rm -f /etc/sudoers.d/pikvm-optimizer-*
    ok "Removed optimizer-managed sudoers rules."
}

uninstall_msd_bios_fix() {
    info "Removing MSD BIOS config key..."
    delete_yaml_paths otg.devices.msd.start
}

uninstall_usb_preset() {
    info "Resetting USB device preset..."
    delete_yaml_paths otg.devices.keyboard otg.devices.mouse otg.devices.msd otg.devices.hid
}

uninstall_usb_extra() {
    info "Removing USB extras config keys..."
    delete_yaml_paths otg.devices.ethernet otg.devices.serial otg.devices.audio
}

uninstall_msd_storage() {
    info "Removing network storage configuration..."

    local mount_point=""
    if [ -f /etc/fstab ]; then
        mount_point="$(grep -F '# pikvm-optimizer-msd-storage' /etc/fstab 2>/dev/null | awk '{print $2}' | head -1 || true)"
    fi

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would unmount ${mount_point:-optimizer-managed MSD storage} and remove optimizer-marked fstab entry."
        return 0
    fi

    make_rw

    if [ -n "$mount_point" ] && mountpoint -q "$mount_point" 2>/dev/null; then
        umount "$mount_point" 2>/dev/null && ok "Unmounted $mount_point." || warn "Could not unmount $mount_point."
    fi

    if [ -f /etc/fstab ]; then
        local fstab_bak="/etc/fstab.bak.$(date +%Y%m%d-%H%M%S)"
        cp /etc/fstab "$fstab_bak"
        grep -v -F '# pikvm-optimizer-msd-storage' /etc/fstab > /etc/fstab.tmp && mv /etc/fstab.tmp /etc/fstab
        ok "Removed optimizer-managed network storage fstab entries."
    fi

    delete_yaml_paths kvmd.msd.otg_devices msd.storage
}

uninstall_msd_drives() {
    info "Resetting MSD drives to single drive..."
    delete_yaml_paths otg.devices.msd_data
}

uninstall_override_d() {
    info "Removing override.d directory..."

    if [ "$DRY_RUN" = true ]; then
        ok "DRY RUN: would remove /etc/kvmd/override.d/."
        return 0
    fi

    make_rw
    rm -rf /etc/kvmd/override.d
    ok "Removed /etc/kvmd/override.d/ directory."
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
        local b="${backups[$i]}"
        box_line "[$((i + 1))] ${b:0:70}"
    done

    box_line ""
    close_box

    if [ "$YES" = true ]; then
        warn "Restore requires interactive selection; skipped in --yes mode."
        return 0
    fi

    printf "Backup number to restore (or blank to cancel): "
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

    local qc_server_py
    qc_server_py="$(find /usr/lib -path '*/kvmd/apps/vnc/server.py' -print -quit 2>/dev/null || true)"
    if [ -n "$qc_server_py" ] && grep -q "tight_jpeg_quality, 15)" "$qc_server_py" 2>/dev/null; then
        ok "VNC quality cap applied (max JPEG quality 15)."
    else
        info "VNC quality cap not applied."
    fi

    if [ -f /etc/sysctl.d/99-pikvm-tcp-keepalive.conf ]; then
        ok "TCP keepalive tuning file exists."
    else
        info "TCP keepalive tuning not installed."
    fi

    if [ -f "$INSTALL_PATH" ]; then
        ok "On-device optimizer command exists: $INSTALL_PATH"
    else
        info "On-device optimizer command not present."
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

    if [ -d /etc/kvmd/override.d ]; then
        ok "override.d directory exists."
    else
        info "override.d directory not created."
    fi

    if grep -q -E 'nfs|cifs' /etc/fstab 2>/dev/null; then
        ok "Network storage (NFS/SMB) configured in /etc/fstab."
    else
        info "No network storage mount in /etc/fstab."
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
    restart_service_if_exists kvmd.service false

    if [ "${RUN_SSL:-false}" = true ]; then
        restart_service_if_exists kvmd-nginx.service false
    fi

    # Post-run reboot warning for modules that benefit from reboot
    if [ "${RUN_MTU:-false}" = true ] || [ "${RUN_EDID:-false}" = true ]; then
        warn "Some changes (MTU/EDID/keepalive) may require a reboot to take full effect."
    fi

    if [ "${REBOOT:-false}" = true ]; then
        info "Rebooting PiKVM as requested..."
        if [ "$DRY_RUN" = true ]; then
            ok "DRY RUN: would reboot system."
        else
            info "Rebooting in 5 seconds... (Ctrl+C to cancel)"
            sleep 5
            systemctl reboot
        fi
    else
        warn "Reboot recommended for MTU/EDID changes. Use --reboot flag to auto-reboot."
    fi

    ok "Service refresh complete."
}

rollback_hint() {
    if [ -n "$BACKUP_FILE" ]; then
        box_line "Rollback command:"
        local rb="rw && cp '$BACKUP_FILE' '$CONFIG_FILE' && systemctl restart kvmd && ro"
        box_line "  ${rb:0:74}"
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
[ "$PRESET" != "interactive" ] && info "Preset: $PRESET"
[ "$FLAGS_PROVIDED" = true ] && info "Flags provided: module flags active"

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
    if [ "$UN_QUALITY_CAP" = true ]; then uninstall_quality_cap; fi
    if [ "$UN_MTU" = true ]; then uninstall_mtu; fi
    if [ "$UN_KEEPALIVE" = true ]; then uninstall_tcp_keepalive; fi
    if [ "$UN_EDID" = true ]; then uninstall_edid; fi
    if [ "$UN_SSL" = true ]; then uninstall_ssl; fi
    if [ "$UN_FAN" = true ]; then uninstall_fan; fi
    if [ "$UN_WATCHDOG" = true ]; then uninstall_watchdog; fi
    if [ "$UN_KEY" = true ]; then uninstall_ssh_key; fi
    if [ "$UN_INSTALL" = true ]; then uninstall_on_device_optimizer; fi
    if [ "$UN_SUDO" = true ]; then uninstall_sudoers; fi
    if [ "$UN_MSD_BIOS_FIX" = true ]; then uninstall_msd_bios_fix; fi
    if [ "$UN_TAILSCALE_CRASH_FIX" = true ]; then uninstall_tailscale_crash_fix; fi
    if [ "$UN_WIFI" = true ]; then uninstall_wifi; fi
    if [ "$UN_2FA" = true ]; then uninstall_2fa; fi
    if [ "$UN_USB_PRESET" = true ]; then uninstall_usb_preset; fi
    if [ "$UN_USB_EXTRA" = true ]; then uninstall_usb_extra; fi
    if [ "$UN_MSD_STORAGE" = true ]; then uninstall_msd_storage; fi
    if [ "$UN_MSD_DRIVES" = true ]; then uninstall_msd_drives; fi
    if [ "$UN_OVERRIDE_D" = true ]; then uninstall_override_d; fi

    final_restart

    SUCCESS=true
    make_ro

    box_line ""
    box_line "${G}[DONE]${RESET} Uninstall/cleanup finished."
    rollback_hint
    close_box
    exit 0
fi

if [ "$YES" != true ] && [ "$FLAGS_PROVIDED" != true ]; then
    interactive_module_menu
fi

if [ "$MODE" = "uninstall" ]; then
    interactive_uninstall_menu
    draw "UNINSTALL / CLEANUP"

    # Confirm before executing destructive changes
    if [ "$YES" != true ]; then
        box_prefix; printf "Apply selected uninstall/cleanup operations? [y/N]: "
        read -r confirm
        case "$confirm" in
            y|Y) ;;
            *) warn "Uninstall cancelled."; close_box; SUCCESS=true; make_ro; exit 0 ;;
        esac
    fi

    if [ "$UN_CORE" = true ]; then uninstall_core_config; fi
    if [ "$UN_QUALITY_CAP" = true ]; then uninstall_quality_cap; fi
    if [ "$UN_MTU" = true ]; then uninstall_mtu; fi
    if [ "$UN_KEEPALIVE" = true ]; then uninstall_tcp_keepalive; fi
    if [ "$UN_EDID" = true ]; then uninstall_edid; fi
    if [ "$UN_SSL" = true ]; then uninstall_ssl; fi
    if [ "$UN_FAN" = true ]; then uninstall_fan; fi
    if [ "$UN_WATCHDOG" = true ]; then uninstall_watchdog; fi
    if [ "$UN_KEY" = true ]; then uninstall_ssh_key; fi
    if [ "$UN_INSTALL" = true ]; then uninstall_on_device_optimizer; fi
    if [ "$UN_SUDO" = true ]; then uninstall_sudoers; fi
    if [ "$UN_MSD_BIOS_FIX" = true ]; then uninstall_msd_bios_fix; fi
    if [ "$UN_TAILSCALE_CRASH_FIX" = true ]; then uninstall_tailscale_crash_fix; fi
    if [ "$UN_WIFI" = true ]; then uninstall_wifi; fi
    if [ "$UN_2FA" = true ]; then uninstall_2fa; fi
    if [ "$UN_USB_PRESET" = true ]; then uninstall_usb_preset; fi
    if [ "$UN_USB_EXTRA" = true ]; then uninstall_usb_extra; fi
    if [ "$UN_MSD_STORAGE" = true ]; then uninstall_msd_storage; fi
    if [ "$UN_MSD_DRIVES" = true ]; then uninstall_msd_drives; fi
    if [ "$UN_OVERRIDE_D" = true ]; then uninstall_override_d; fi

    final_restart || true

    SUCCESS=true
    make_ro

    box_line ""
    box_line "${G}[DONE]${RESET} Uninstall/cleanup finished."
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

if [ "$FLAGS_PROVIDED" = true ]; then
    box_line "Running with explicit flags/preset: ${PRESET:-custom}"
elif [ "$PRESET" != "interactive" ]; then
    box_line "Running preset: $PRESET"
fi
box_line ""

# --- Group 1: Foundation (base config, independent patches) ---
if [ "$RUN_CORE" = true ]; then apply_core_config; fi
if [ "$RUN_QUALITY_CAP" = true ]; then apply_vnc_quality_cap; fi

# --- Group 2: Dependency installations (must run before their dependents) ---
box_line ""; if [ "$RUN_TAILSCALE_SETUP" = true ]; then apply_tailscale_setup; fi
if [ "$RUN_TAILSCALE_CRASH_FIX" = true ]; then apply_tailscale_crash_fix; fi

# --- Group 3: Tailscale-dependent tuning (needs TS installed from Group 2) ---
if [ "$RUN_MTU" = true ]; then apply_tailscale_mtu; fi
if [ "$RUN_SSL" = true ]; then apply_tailscale_ssl; fi
if [ "$RUN_WATCHDOG" = true ]; then apply_tailscale_watchdog; fi
if [ "$RUN_TAILSCALE_DIAG" = true ]; then apply_tailscale_diag; fi

# --- Group 4: Independent config (no external deps, no YAML needed) ---
box_line ""; if [ "$RUN_KEEPALIVE" = true ]; then apply_tcp_keepalive; fi
if [ "$RUN_EDID" = true ]; then apply_edid; fi
if [ "$RUN_FAN" = true ]; then apply_fan_curve; fi
if [ "$RUN_WIFI" = true ]; then apply_wifi; fi

# --- Group 5: YAML-dependent hardware config (merge into override.yaml) ---
box_line ""; if [ "$RUN_MSD_BIOS_FIX" = true ]; then apply_msd_bios_fix; fi
if [ "$RUN_USB_PRESET" = true ]; then apply_usb_preset; fi
if [ "$RUN_USB_EXTRA" = true ]; then apply_usb_extra; fi
if [ "$RUN_MSD_STORAGE" = true ]; then apply_msd_storage; fi
if [ "$RUN_MSD_DRIVES" = true ]; then apply_msd_drives; fi
if [ "$RUN_OVERRIDE_D" = true ]; then apply_override_d; fi

# --- Group 6: Interactive security (user must be present) ---
box_line ""; if [ "$RUN_ROOT_PASSWORD" = true ]; then apply_root_password; fi
if [ "$RUN_FIRST_RUN" = true ]; then apply_first_run; fi       # admin password before 2FA
if [ "$RUN_2FA" = true ]; then apply_2fa; fi

# --- Group 7: Post-setup (no dependencies, run after config is settled) ---
box_line ""; enable_oled_if_present
if [ "$RUN_KEY" = true ]; then apply_ssh_key; fi
if [ "$RUN_INSTALL" = true ]; then install_on_device_optimizer; fi
# if [ "$RUN_SUDO" = true ]; then apply_restricted_sudo; fi (DISABLED — security risk)

final_restart || true
health_check || true

SUCCESS=true
make_ro

box_line ""

if [ "$DRY_RUN" = true ]; then
    box_line "${G}[DONE]${RESET} Dry run finished. No persistent changes were intentionally made."
else
    box_line "${G}[DONE]${RESET} Optimization routine finished."
fi

if [ -n "$BACKUP_FILE" ]; then
    box_line "Backup file: ${BACKUP_FILE:0:62}"
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
