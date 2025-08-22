#!/usr/bin/env bash
set -euo pipefail

export DISPLAY="${DISPLAY:-:99}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"

# Ensure required directories exist
mkdir -p /var/log /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix || true

# Remove previous lock/socket files if they remain
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 || true

# Start Xorg with dummy driver and required extensions
Xorg "$DISPLAY" \
  -config /etc/X11/xorg.conf.d/10-headless.conf \
  -noreset \
  +extension GLX +extension RANDR +extension RENDER \
  -logfile /var/log/Xorg.99.log \
  &

XORG_PID=$!

# Wait until the display comes up
tries=20
until xdpyinfo >/dev/null 2>&1; do
  sleep 0.3
  tries=$((tries-1))
  if [ "$tries" -le 0 ]; then
    echo "Xorg failed to start. Last 100 lines of log:"
    tail -n 100 /var/log/Xorg.99.log || true
    exit 1
  fi
done

# Show GLX info (for debugging)
echo "---- GLX Info (renderer/version) ----"
glxinfo | grep -E "OpenGL renderer|OpenGL version" || true
echo "-------------------------------------"

# Run the program
exec python main.py
