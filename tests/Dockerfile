# Container for running the kvmd config validation suite without a PiKVM.
#
# IMPORTANT: do not "simplify" this to `pip install kvmd`. The PyPI name "kvmd"
# is Maxim Devaev's abandoned 2018 mdevaev/pi-kvm daemon (v0.10), not PiKVM's
# kvmd 4.x. It raises "This module can only be run on a Raspberry Pi!" on import,
# which is why the Config Validation job failed on every run until 1.4.4.
#
# The real kvmd only ships as an Arch package / on GitHub, and its `kvmd` CLI
# cannot run off-device (it imports the daemon and needs ustreamer, not on PyPI).
# We therefore install the package and drive its config engine directly from
# Python -- see tests/validate_patches.py.
FROM python:3.13-slim-bookworm

# gcc/headers are required: evdev builds a C extension and has no wheel.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    gcc \
    libc6-dev \
    curl \
    && rm -rf /var/lib/apt/lists/*

# kvmd's setup.py under-declares its runtime imports, so the modules the config
# scheme pulls in have to be listed explicitly. This is the minimal set that
# makes make_config_scheme() import -- do not add the rest of kvmd's runtime
# deps (pillow, hidapi, spidev, xlib, ...): they are not needed here and several
# have no arm64 wheels, so they compile from source and stall the build.
RUN pip install --no-cache-dir \
    git+https://github.com/pikvm/kvmd \
    pyyaml \
    ruamel.yaml \
    pygments \
    evdev \
    aiofiles \
    aiohttp

# Platform-specific main.yaml for V4 Plus HDMI (RPi4), so the scheme has a
# concrete platform config to merge patches over.
RUN mkdir -p /usr/lib/kvmd /etc/kvmd/override.d
ADD https://raw.githubusercontent.com/pikvm/kvmd/master/configs/kvmd/main/v4plus-hdmi-rpi4.yaml /usr/lib/kvmd/main.yaml

WORKDIR /app
COPY . .

# Fail the build early if the config engine is not importable.
RUN python -c "from kvmd.apps._scheme import make_config_scheme; make_config_scheme(); print('kvmd config scheme OK')"

CMD ["python", "tests/validate_patches.py"]
