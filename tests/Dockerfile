FROM python:3.14-slim-bookworm AS builder

# Install build dependencies for kvmd
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install kvmd from PyPI
RUN pip install --no-cache-dir kvmd

# Download platform-specific main.yaml for V4 Plus HDMI (RPi4)
# This is needed so kvmd -M has a schema to validate against
RUN mkdir -p /usr/lib/kvmd /etc/kvmd/override.d
ADD https://raw.githubusercontent.com/pikvm/kvmd/master/configs/kvmd/main/v4plus-hdmi-rpi4.yaml /usr/lib/kvmd/main.yaml

# Copy the project for validation
WORKDIR /app
COPY . .

# Verify kvmd works in validate mode
RUN kvmd --help >/dev/null 2>&1 && echo "kvmd CLI OK"
RUN kvmd -M --override-config /dev/null >/dev/null 2>&1 && echo "kvmd validate OK"

# Default command: run patch validation
CMD ["bash", "tests/validate_patches.sh"]
