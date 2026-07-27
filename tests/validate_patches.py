#!/usr/bin/env python3
"""
PiKVM Optimizer — kvmd Config Validation Test Suite

Tests every YAML patch the optimizer generates against kvmd's real config
engine, to catch schema mismatches between modules and the target PiKVM version.

Two kinds of assertion:

  * validity     — the patch merges and passes kvmd's validators.
  * effectiveness— the patch actually CHANGES the effective config.

The second kind matters because kvmd's make_config() iterates over its schema
and reads override.get(key), so an override key that is not in the schema is
silently ignored: no error, and validation passes. Optimizer 1.4.3 shipped
`vnc.vencrypt.enabled` that way (the real path is `vnc.auth.vencrypt.enabled`)
and nothing caught it. See the "REGRESSION" case below, which pins that bug.

Usage
-----
  Anywhere kvmd's Python package is importable (CI, container, or a PiKVM):

      python3 tests/validate_patches.py

  On a PiKVM the device's own /usr/lib/kvmd/main.yaml is used automatically.
  Elsewhere, point KVMD_MAIN_YAML at a platform config, e.g.
  configs/kvmd/main/v4plus-hdmi-rpi4.yaml from the kvmd repo.

  From the launcher, to test against a real device:

      scp tests/validate_patches.py root@pikvm:/tmp/
      ssh root@pikvm "python3 /tmp/validate_patches.py"

Exit code is 0 if all patches pass, 1 otherwise.

Note: this imports kvmd.apps._init_config, a private API. It is the only
entrypoint that performs the real override merge *and* the dynamic plugin
schema patching (which is what makes keys like kvmd.msd.type resolve) without
pulling in the daemon itself. The public `kvmd` CLI cannot be used off-device:
it imports the whole daemon stack and needs ustreamer, which is not on PyPI.
"""

import os
import sys
import tempfile
from pathlib import Path

from kvmd.apps import ConfigPaths, _init_config
from kvmd.yamlconf import ConfigError

MAIN_YAML = os.environ.get("KVMD_MAIN_YAML", "/usr/lib/kvmd/main.yaml")
OVERRIDE_DIR = os.environ.get("KVMD_OVERRIDE_DIR", "/etc/kvmd/override.d")
LEGACY_AUTH = os.environ.get("KVMD_LEGACY_AUTH", "/etc/kvmd/auth.yaml")

UNSET = object()


def load_config(patch_text: str):
    """Merge a patch over main.yaml and return kvmd's effective config.

    load_all is left at its default (False) on purpose: passing True makes kvmd
    instantiate hardware plugins and fail with "Unknown plugin 'atx/gpio'" on
    anything that is not a real PiKVM.
    """
    with tempfile.NamedTemporaryFile("w", suffix=".yaml", delete=False) as handle:
        handle.write(patch_text)
        override_path = handle.name
    try:
        cps = ConfigPaths(
            main=MAIN_YAML,
            legacy_auth=LEGACY_AUTH,
            override_dir=OVERRIDE_DIR,
            override=override_path,
        )
        return _init_config(cps=cps, test_override=None)
    finally:
        os.unlink(override_path)


def resolve(config, dotted: str):
    node = config
    for key in dotted.split("."):
        try:
            node = node[key]
        except (KeyError, TypeError):
            return UNSET
    return node


class Suite:
    def __init__(self) -> None:
        self.passed = 0
        self.failed: list[str] = []

    def section(self, title: str) -> None:
        print(f"\n[ Module: {title} ]")

    def _ok(self, name: str) -> None:
        print(f"  {name:<38} PASS")
        self.passed += 1

    def _fail(self, name: str, detail: str) -> None:
        print(f"  {name:<38} FAIL")
        for line in detail.splitlines():
            print(f"      {line}")
        self.failed.append(name)

    def check(self, name: str, patch: str, expect=(), expect_unchanged=()) -> None:
        """Assert `patch` validates, and that each (path, value) in `expect` holds.

        `expect_unchanged` asserts a path is NOT set to the given value — used to
        pin known-bad config paths that kvmd silently ignores.
        """
        try:
            config = load_config(patch)
        except (ConfigError, SystemExit) as ex:
            self._fail(name, f"kvmd rejected the patch:\n{ex}")
            return

        problems = []
        for (path, want) in expect:
            got = resolve(config, path)
            if got is UNSET:
                problems.append(f"{path} is absent from the effective config")
            elif got != want:
                problems.append(f"{path} == {got!r}, expected {want!r}")
        for (path, unwanted) in expect_unchanged:
            got = resolve(config, path)
            if got == unwanted:
                problems.append(f"{path} == {unwanted!r}, but it should NOT have been applied")

        if problems:
            self._fail(name, "\n".join(problems))
        else:
            self._ok(name)


def main() -> int:
    if not Path(MAIN_YAML).is_file():
        print(f"ERROR: main config not found at {MAIN_YAML}")
        print("Set KVMD_MAIN_YAML to a platform config from the kvmd repo, e.g.")
        print("  configs/kvmd/main/v4plus-hdmi-rpi4.yaml")
        return 1
    # kvmd requires the override.d directory to exist.
    Path(OVERRIDE_DIR).mkdir(parents=True, exist_ok=True)

    import kvmd

    print("==========================================")
    print(" PiKVM Optimizer — Config Validation Suite")
    print(f" kvmd version: {getattr(kvmd, '__version__', 'unknown')}")
    print(f" main.yaml:    {MAIN_YAML}")
    print("==========================================")

    s = Suite()

    s.section("core")
    s.check("core: streamer quality", """
kvmd:
    streamer:
        quality: 15
""", expect=[("kvmd.streamer.quality", 15)])

    s.check("core: h264 bitrate", """
kvmd:
    streamer:
        h264_bitrate:
            default: 1500
            min: 25
            max: 20000
""")

    s.check("core: h264 gop", """
kvmd:
    streamer:
        h264_gop:
            default: 0
            min: 0
            max: 60
""")

    s.check("core: vnc auth", """
vnc:
    auth:
        vncauth:
            enabled: true
""", expect=[("vnc.auth.vncauth.enabled", True)])

    s.check("core: combined", """
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
""", expect=[
        ("kvmd.streamer.quality", 15),
        ("vnc.auth.vncauth.enabled", True),
    ])

    s.section("vnc-legacy-client")
    s.check("vnc-legacy: vencrypt disabled", """
vnc:
    auth:
        vencrypt:
            enabled: false
""", expect=[("vnc.auth.vencrypt.enabled", False)])

    # REGRESSION (optimizer 1.4.3): vnc.vencrypt.enabled is not a kvmd path.
    # kvmd ignores unknown override keys without erroring, so this patch
    # "validates" while doing nothing. If this case ever starts failing, either
    # kvmd grew a real vnc.vencrypt key or someone reintroduced the bad path.
    s.check("vnc-legacy: 1.4.3 bad path is inert", """
vnc:
    vencrypt:
        enabled: false
""", expect_unchanged=[("vnc.auth.vencrypt.enabled", False)])

    s.section("edid")
    s.check("edid: tc358743 path", """
kvmd:
    tc358743:
        edid: "/etc/kvmd/tc358743-edid.hex"
""")

    s.section("ssl")
    s.check("ssl: nginx cert/key", """
kvmd:
    nginx:
        https:
            certificate: /etc/kvmd/nginx/ssl/cert.pem
            private_key: /etc/kvmd/nginx/ssl/key.pem
""")

    s.section("msd-bios")
    s.check("msd-bios: type disk + cdrom", """
kvmd:
    msd:
        type: disk
        bios: cdrom
""", expect=[("kvmd.msd.type", "disk")])

    s.check("msd-bios: bios only (no type)", """
kvmd:
    msd:
        bios: cdrom
""")

    s.section("usb-preset")
    s.check("usb-preset: keyboard + mouse", """
kvmd:
    hid:
        keyboard:
            type: keyboard
        mouse:
            type: mouse
""")

    s.check("usb-preset: BIOS mode (keyboard)", """
kvmd:
    hid:
        keyboard:
            type: keyboard
        mouse:
            type: mouse
        tablet:
            type: off
""")

    s.check("usb-preset: normal mode (tablet)", """
kvmd:
    hid:
        keyboard:
            type: keyboard
        mouse:
            type: mouse
        tablet:
            type: on
""")

    s.section("usb-extras")
    s.check("usb-extras: ethernet+serial+audio", """
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
""")

    s.section("msd-storage")
    s.check("msd-storage: NFS", """
kvmd:
    msd:
        storage:
            nfs:
                server: example.local
                export: /srv/nfs
                options: nfsvers=4.2,soft,timeo=30,retrans=3
""")

    s.check("msd-storage: SMB", """
kvmd:
    msd:
        storage:
            smb:
                server: example.local
                share: sharename
                options: vers=3.0,sec=ntlmssp
""")

    s.section("msd-drives")
    s.check("msd-drives: extra image", """
kvmd:
    msd:
        drives:
            image_1:
                path: /var/lib/kvmd/msd/images/virtio-win.iso
""")

    s.section("watchdog")
    s.check("watchdog: TCP config", """
kvmd:
    watchdog:
        tcp:
            host: 127.0.0.1
            port: 22
            interval: 60
            timeout: 10
""")

    s.section("override-d")
    s.check("override.d: kvmd keys", """
kvmd: {}
""")

    print("\n==========================================")
    if not s.failed:
        print(f" ALL {s.passed} PATCHES PASSED")
        print("==========================================")
        return 0
    print(f" {s.passed} passed, {len(s.failed)} failed")
    print(" Failed patches:")
    for name in s.failed:
        print(f"  - {name}")
    print("")
    print(" Failures may be version-specific if the target PiKVM does not")
    print(" support certain config keys (e.g. msd.type on kvmd < 4.150).")
    print("==========================================")
    return 1


if __name__ == "__main__":
    sys.exit(main())
