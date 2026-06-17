#!/bin/bash
# ---------------------------------------------------------------------------
# PiKVM Optimizer — kvmd Config Validation Test Suite
#
# Tests every YAML patch the optimizer generates against `kvmd -M` to catch
# config schema mismatches between modules and the target PiKVM version.
#
# Usage:
#   On a PiKVM (or container with kvmd installed):
#     bash tests/validate_patches.sh
#
#   From the launcher (copies remote script and tests on target PiKVM):
#     ./pikvm_optimizer.sh --print-remote > /tmp/pikvm-optimizer-remote.sh
#     scp /tmp/pikvm-optimizer-remote.sh root@pikvm:/tmp/
#     scp tests/validate_patches.sh root@pikvm:/tmp/
#     ssh root@pikvm "bash /tmp/validate_patches.sh"
#
# Returns 0 if all patches pass, 1 if any fail.
# ---------------------------------------------------------------------------
set -euo pipefail

PASS=0
FAIL=0
FAILED_NAMES=""

# Ensure kvmd is installed
if ! command -v kvmd >/dev/null 2>&1; then
    echo "ERROR: kvmd not found. Install it: pip install kvmd"
    exit 1
fi

# Ensure override.d exists (kvmd requires it)
mkdir -p /etc/kvmd/override.d

test_patch() {
    local name="$1"
    local yaml="$2"
    local file
    file="$(mktemp /tmp/pikvm-test-XXXXXX.yaml)"

    # Write YAML (preserve literal content with embedded newlines)
    cat > "$file" <<< "$yaml"

    printf "  %-35s " "$name"
    if kvmd -M --override-config="$file" >/dev/null 2>&1; then
        echo "PASS"
        PASS=$((PASS + 1))
    else
        echo "FAIL"
        kvmd -M --override-config="$file" 2>&1
        FAIL=$((FAIL + 1))
        FAILED_NAMES="$FAILED_NAMES  - $name"$'\n'
    fi
    rm -f "$file"
}

echo "=========================================="
echo " PiKVM Optimizer — Config Validation Suite"
echo " kvmd version: $(kvmd --version 2>&1 | tail -1)"
echo " Date: $(date -u '+%Y-%m-%d %H:%M UTC')"
echo "=========================================="
echo ""

# ── Core streamer/VNC ────────────────────────────────────────────────────────
echo "[ Module: core ]"

test_patch "core: streamer quality"             '
kvmd:
    streamer:
        quality: 15
'

test_patch "core: h264 bitrate"                 '
kvmd:
    streamer:
        h264_bitrate:
            default: 1500
            min: 25
            max: 20000
'

test_patch "core: h264 gop"                     '
kvmd:
    streamer:
        h264_gop:
            default: 0
            min: 0
            max: 60
'

test_patch "core: vnc auth"                     '
vnc:
    auth:
        vncauth:
            enabled: true
'

test_patch "core: combined"                     '
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
'

# ── EDID ─────────────────────────────────────────────────────────────────────
echo ""
echo "[ Module: edid ]"

test_patch "edid: tc358743 path"                '
kvmd:
    tc358743:
        edid: "/etc/kvmd/tc358743-edid.hex"
'

# ── SSL ──────────────────────────────────────────────────────────────────────
echo ""
echo "[ Module: ssl ]"

test_patch "ssl: nginx cert/key"                '
kvmd:
    nginx:
        https:
            certificate: /etc/kvmd/nginx/ssl/cert.pem
            private_key: /etc/kvmd/nginx/ssl/key.pem
'

# ── MSD BIOS fix ─────────────────────────────────────────────────────────────
echo ""
echo "[ Module: msd-bios ]"

test_patch "msd-bios: type disk + cdrom"        '
kvmd:
    msd:
        type: disk
        bios: cdrom
'

test_patch "msd-bios: bios only (no type)"      '
kvmd:
    msd:
        bios: cdrom
'

# ── USB preset ───────────────────────────────────────────────────────────────
echo ""
echo "[ Module: usb-preset ]"

test_patch "usb-preset: keyboard + mouse"       '
kvmd:
    hid:
        keyboard:
            type: keyboard
        mouse:
            type: mouse
'

test_patch "usb-preset: BIOS mode (keyboard)"   '
kvmd:
    hid:
        keyboard:
            type: keyboard
        mouse:
            type: mouse
        tablet:
            type: off
'

test_patch "usb-preset: normal mode (tablet)"   '
kvmd:
    hid:
        keyboard:
            type: keyboard
        mouse:
            type: mouse
        tablet:
            type: on
'

# ── USB extras ───────────────────────────────────────────────────────────────
echo ""
echo "[ Module: usb-extras ]"

test_patch "usb-extras: ethernet+serial+audio"  '
kvmd:
    hid:
        keyboard:
            type: keyboard
        mouse:
            type: mouse
        usb:
            ethernet: true
            serial: true
            audio: true
'

# ── MSD storage ──────────────────────────────────────────────────────────────
echo ""
echo "[ Module: msd-storage ]"

test_patch "msd-storage: NFS"                   '
kvmd:
    msd:
        storage:
            nfs:
                server: example.local
                export: /srv/nfs
                options: nfsvers=4.2,soft,timeo=30,retrans=3
'

test_patch "msd-storage: SMB"                   '
kvmd:
    msd:
        storage:
            smb:
                server: example.local
                share: sharename
                options: vers=3.0,sec=ntlmssp
'

# ── MSD drives ───────────────────────────────────────────────────────────────
echo ""
echo "[ Module: msd-drives ]"

test_patch "msd-drives: extra image"            '
kvmd:
    msd:
        drives:
            image_1:
                path: /var/lib/kvmd/msd/images/virtio-win.iso
'

# ── Watchdog ─────────────────────────────────────────────────────────────────
echo ""
echo "[ Module: watchdog ]"

test_patch "watchdog: TCP config"               '
kvmd:
    watchdog:
        tcp:
            host: 127.0.0.1
            port: 22
            interval: 60
            timeout: 10
'

# ── Override.d ───────────────────────────────────────────────────────────────
echo ""
echo "[ Module: override-d ]"

test_patch "override.d: kvmd keys"              '
kvmd: {}
'

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
if [ "$FAIL" -eq 0 ]; then
    echo " ALL $PASS PATCHES PASSED"
    echo "=========================================="
    exit 0
else
    echo " $PASS passed, $FAIL failed"
    echo " Failed patches:"
    echo "$FAILED_NAMES"
    echo ""
    echo " Failures may be version-specific if the target PiKVM does not"
    echo " support certain config keys (e.g., msd.type on kvmd < 4.150)."
    echo " See ci/docker-test.sh for version-pinned validation."
    echo "=========================================="
    exit 1
fi
