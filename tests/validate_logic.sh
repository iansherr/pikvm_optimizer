#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Control-flow regression tests for the embedded remote optimizer.
#
# validate_patches.py covers the YAML the modules write. This covers the shell
# logic around it -- specifically the two places where a wrong branch is a
# security or data-loss bug rather than a cosmetic one:
#
#   * final_restart must never START kvmd-vnc. enable_vnc_service refuses to
#     bring it up while /etc/kvmd/vncpasswd holds kvmd's shipped password, and
#     up to 1.4.4 final_restart's `systemctl restart` started it anyway, putting
#     a VNC listener on :5900 with the public password "admin".
#   * backing out of the uninstall menu must not run the uninstall.
#
# Function bodies are pulled out of the shipped script with sed, so these tests
# exercise real code rather than a copy of it. No PiKVM and no root needed.
#
# Usage: bash tests/validate_logic.sh
# ---------------------------------------------------------------------------
# Most globals here look unused to shellcheck because the only readers are the
# function bodies pulled in via eval further down. A file-level directive has to
# precede the first command, so it lives above `set`.
# shellcheck disable=SC2034

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

REMOTE="$(mktemp "${TMPDIR:-/tmp}/pikvm-remote.XXXXXX")"
trap 'rm -f "$REMOTE"' EXIT
bash "$REPO_DIR/pikvm_optimizer.sh" --print-remote > "$REMOTE"

if [ ! -s "$REMOTE" ]; then
    echo "FATAL: --print-remote produced nothing" >&2
    exit 1
fi

PASS=0
FAIL=0
ok_t()   { PASS=$((PASS+1)); printf '  %-42s PASS\n' "$1"; }
fail_t() { FAIL=$((FAIL+1)); printf '  %-42s FAIL  %s\n' "$1" "${2:-}"; }
assert() { if [ "$2" = "$3" ]; then ok_t "$1"; else fail_t "$1" "want '$3', got '$2'"; fi; }

extract() { sed -n "/^$1() {\$/,/^}\$/p" "$REMOTE"; }
# Comments explaining what a function deliberately does NOT do would otherwise
# match the same greps the assertions use.
extract_code() { extract "$1" | sed 's/[[:space:]]*#.*$//'; }

# Several checks below are "this string is absent", which an empty extraction
# would satisfy for the wrong reason. Fail loudly if a function goes missing or
# gets renamed instead of quietly reporting a pass.
require_extract() {
    local body
    body="$(extract_code "$1")"
    if [ -z "$body" ]; then
        echo "FATAL: could not extract $1() from the remote script" >&2
        exit 1
    fi
    printf '%s\n' "$body"
}

# --- stubs for the script's own helpers ------------------------------------
info() { :; }; ok() { :; }; warn() { :; }; err() { :; }
box_line() { :; }; box_prefix() { :; }; draw() { :; }; close_box() { :; }
make_rw() { :; }; make_ro() { :; }
DRY_RUN=false; SUCCESS=false; YES=false; FLAGS_PROVIDED=false
G=""; Y=""; RESET=""

SYSTEMCTL_LOG=""
VNC_ACTIVE=false      # is kvmd-vnc.service running? every other unit is "up"
systemctl() {
    local verb="$1"; shift
    local unit=""
    case "${1:-}" in --*) unit="${2:-}" ;; *) unit="${1:-}" ;; esac

    case "$verb" in
        is-active)
            if [ "$unit" = "kvmd-vnc.service" ]; then
                [ "$VNC_ACTIVE" = true ]
                return
            fi
            return 0
            ;;
        list-unit-files|status|daemon-reload) return 0 ;;
        restart|start|enable)
            SYSTEMCTL_LOG="${SYSTEMCTL_LOG}${verb} ${unit};"
            [ "$unit" = "kvmd-vnc.service" ] && VNC_ACTIVE=true
            return 0
            ;;
    esac
    return 0
}

eval "$(extract service_exists)"
eval "$(extract service_is_active)"
eval "$(extract restart_service_if_exists)"
eval "$(extract restart_service_if_active)"
eval "$(extract final_restart)"

run_final_restart() {
    SYSTEMCTL_LOG=""
    RUN_SSL=false RUN_MTU=false RUN_EDID=false REBOOT=false \
        RUN_CORE="$1" RUN_VNC_LEGACY="$2" RUN_QUALITY_CAP="$3" \
        final_restart >/dev/null 2>&1
}

echo
echo "[ final_restart: kvmd-vnc gate ]"

# The 1.4.4 regression: RUN_CORE defaults to true, so this is what a plain
# `--host ... --yes` run does on a fresh PiKVM.
VNC_ACTIVE=false; run_final_restart true false false
case "$SYSTEMCTL_LOG" in
    *kvmd-vnc*) fail_t "core run leaves stopped kvmd-vnc alone" "$SYSTEMCTL_LOG" ;;
    *)          ok_t   "core run leaves stopped kvmd-vnc alone" ;;
esac

VNC_ACTIVE=true; run_final_restart true false false
case "$SYSTEMCTL_LOG" in
    *"restart kvmd-vnc.service"*) ok_t "running kvmd-vnc is restarted" ;;
    *) fail_t "running kvmd-vnc is restarted" "$SYSTEMCTL_LOG" ;;
esac

# --quality-cap patches an already-deployed server.py; it must not turn VNC on.
VNC_ACTIVE=false; run_final_restart false false true
case "$SYSTEMCTL_LOG" in
    *kvmd-vnc*) fail_t "quality-cap leaves stopped kvmd-vnc alone" "$SYSTEMCTL_LOG" ;;
    *)          ok_t   "quality-cap leaves stopped kvmd-vnc alone" ;;
esac

VNC_ACTIVE=false; run_final_restart true false false
case "$SYSTEMCTL_LOG" in
    *"restart kvmd.service"*) ok_t "kvmd.service still restarted" ;;
    *) fail_t "kvmd.service still restarted" "$SYSTEMCTL_LOG" ;;
esac

echo
echo "[ VNC password gate ]"

ADMIN_PASSWORD="test-not-the-default"
VNC_PASSWORD_SYNCED=false
eval "$(extract vncpasswd_is_default)"
eval "$(extract enable_service_if_exists)"
eval "$(extract sync_vnc_password)"
eval "$(extract enable_vnc_service)"

# /etc/kvmd/vncpasswd does not exist on the test host, which vncpasswd_is_default
# treats as "still the default" -- the same state a fresh PiKVM presents.
DRY_RUN=true VNC_PASSWORD_SYNCED=false
sync_vnc_password >/dev/null 2>&1
assert "dry run marks the password as synced" "$VNC_PASSWORD_SYNCED" "true"

warn() { echo "WARN:$*"; }
GATE_DRY="$(RUN_CORE=true DRY_RUN=true VNC_PASSWORD_SYNCED=true enable_vnc_service 2>&1)"
GATE_REAL="$(RUN_CORE=true DRY_RUN=false VNC_PASSWORD_SYNCED=false enable_vnc_service 2>&1)"
GATE_OFF="$(RUN_CORE=false RUN_VNC_LEGACY=false DRY_RUN=false \
    VNC_PASSWORD_SYNCED=false enable_vnc_service 2>&1)"
warn() { :; }
DRY_RUN=false

case "$GATE_DRY" in
    *"left stopped"*) fail_t "dry run does not preview a bogus refusal" ;;
    *)                ok_t   "dry run does not preview a bogus refusal" ;;
esac
case "$GATE_REAL" in
    *"left stopped"*) ok_t   "real run refuses on the default password" ;;
    *) fail_t "real run refuses on the default password" "$GATE_REAL" ;;
esac
assert "no VNC module means no VNC decision" "$GATE_OFF" ""

echo
echo "[ uninstall menu: backing out ]"

# The real top-level dispatch block, lifted verbatim from the script and run
# with the menus and the uninstall dispatch stubbed out. Extracting rather than
# duplicating is the whole point: a copy would keep passing after someone edits
# the real flow, which is exactly the bug class these tests exist to catch.
MAIN_FLOW="$(sed -n '/^# BEGIN uninstall-dispatch-flow$/,/^# END uninstall-dispatch-flow$/p' "$REMOTE")"
if [ -z "$MAIN_FLOW" ]; then
    echo "FATAL: uninstall-dispatch-flow markers not found in the remote script" >&2
    echo "       (did someone drop the BEGIN/END comments?)" >&2
    exit 1
fi
# Sanity-check that we grabbed the real thing and not just the marker pair.
case "$MAIN_FLOW" in
    *run_uninstall_dispatch*) ;;
    *) echo "FATAL: extracted block does not call run_uninstall_dispatch" >&2; exit 1 ;;
esac

# The real run_uninstall_dispatch ends in `exit 0`, so the flow never continues
# past it. Modelling that matters: without it the block runs on and reaches
# branches the script cannot actually reach, and the tests pass for the wrong
# reason. The flow therefore runs in a subshell that the stub is free to exit,
# and the stubs record what happened to a file instead of to shell variables.
EVENTS="$(mktemp "${TMPDIR:-/tmp}/pikvm-events.XXXXXX")"
trap 'rm -f "$REMOTE" "$EVENTS"' EXIT

run_uninstall_dispatch() { echo dispatch >> "$EVENTS"; exit 0; }

run_flow() {
    : > "$EVENTS"
    MODE="$1"
    ( eval "$MAIN_FLOW" ) >/dev/null 2>&1
}
count() { awk -v p="$1" '$0==p{n++} END{print n+0}' "$EVENTS"; }

# a) --uninstall on the command line, then "q" to back out
interactive_uninstall_menu() { echo un_menu >> "$EVENTS"; MODE="optimize"; }
interactive_module_menu() { echo mod_menu >> "$EVENTS"; MODE="optimize"; }
run_flow uninstall
assert "q backing out runs no uninstall" "$(count dispatch)" "0"
assert "q backing out opens the module menu once" "$(count mod_menu)" "1"

# b) --uninstall carried through
interactive_uninstall_menu() { echo un_menu >> "$EVENTS"; }
run_flow uninstall
assert "confirmed uninstall dispatches once" "$(count dispatch)" "1"
assert "confirmed uninstall skips the module menu" "$(count mod_menu)" "0"

# c) "u" from the module menu, then "q" back out of the uninstall menu
interactive_module_menu() {
    echo mod_menu >> "$EVENTS"
    if [ "$(count mod_menu)" = "1" ]; then MODE="uninstall"; else MODE="optimize"; fi
}
interactive_uninstall_menu() { echo un_menu >> "$EVENTS"; MODE="optimize"; }
run_flow optimize
assert "u-then-q runs no uninstall" "$(count dispatch)" "0"
assert "u-then-q returns to the module menu" "$(count mod_menu)" "2"

# d) --uninstall --yes: no menus at all, straight to the dispatch
interactive_uninstall_menu() { echo un_menu >> "$EVENTS"; }
interactive_module_menu() { echo mod_menu >> "$EVENTS"; MODE="optimize"; }
YES=true
run_flow uninstall
YES=false
assert "--uninstall --yes dispatches once" "$(count dispatch)" "1"
assert "--uninstall --yes shows no menu" \
    "$(( $(count un_menu) + $(count mod_menu) ))" "0"

Q_BODY="$(require_extract interactive_uninstall_menu | sed -n '/q|Q)/,/;;/p')"
if [ -z "$Q_BODY" ]; then
    echo "FATAL: no q|Q handler found in interactive_uninstall_menu()" >&2
    exit 1
fi
case "$Q_BODY" in
    *interactive_module_menu*) fail_t "q handler leaves the menu to the caller" ;;
    *)                         ok_t   "q handler leaves the menu to the caller" ;;
esac

echo
echo "[ vencrypt key ownership ]"

CORE_BODY="$(require_extract uninstall_core_config)"
LEGACY_BODY="$(require_extract uninstall_vnc_legacy_client)"

case "$CORE_BODY" in
    *vnc.auth.vencrypt.enabled*) fail_t "core uninstall leaves vencrypt alone" ;;
    *)                           ok_t   "core uninstall leaves vencrypt alone" ;;
esac
case "$LEGACY_BODY" in
    *vnc.auth.vencrypt.enabled*) ok_t "vnc-legacy uninstall owns vencrypt" ;;
    *) fail_t "vnc-legacy uninstall owns vencrypt" ;;
esac
case "$CORE_BODY" in
    *vnc.vencrypt*) ok_t "core still clears the stray 1.4.3 key" ;;
    *) fail_t "core still clears the stray 1.4.3 key" ;;
esac

echo
echo "=========================================="
if [ "$FAIL" -eq 0 ]; then
    echo " ALL $PASS LOGIC CHECKS PASSED"
    echo "=========================================="
    exit 0
fi
echo " $FAIL of $((PASS + FAIL)) LOGIC CHECKS FAILED"
echo "=========================================="
exit 1
