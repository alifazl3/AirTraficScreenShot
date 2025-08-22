#!/usr/bin/env bash
set -euo pipefail

export DISPLAY="${DISPLAY:-:99}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"

# اطمینان از وجود دایرکتوری‌های لازم
mkdir -p /var/log /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix || true

# پاک کردن لاک/سوکت‌های قبلی اگر باقی مانده‌اند
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 || true

# استارت Xorg با درایور dummy و اکستنشن‌های لازم
Xorg "$DISPLAY" \
  -config /etc/X11/xorg.conf.d/10-headless.conf \
  -noreset \
  +extension GLX +extension RANDR +extension RENDER \
  -logfile /var/log/Xorg.99.log \
  &

XORG_PID=$!

# صبر تا بالا آمدن نمایشگر
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

# نمایش اطلاعات GLX (برای دیباگ)
echo "---- GLX Info (renderer/version) ----"
glxinfo | grep -E "OpenGL renderer|OpenGL version" || true
echo "-------------------------------------"

# اجرای برنامه
exec python main.py