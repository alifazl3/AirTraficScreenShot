FROM python:3.12-slim

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl unzip wget \
    fonts-liberation \
    libasound2 libatk-bridge2.0-0 libatk1.0-0 libc6 libdrm2 \
    libgtk-3-0 libnspr4 libnss3 libxcb1 libxcomposite1 libxdamage1 libxfixes3 \
    libxrandr2 libxkbcommon0 libx11-6 libx11-xcb1 libxext6 libxi6 libxrender1 \
    libgbm1 libpango-1.0-0 libpangocairo-1.0-0 libatspi2.0-0 xdg-utils \
    libgl1-mesa-dri libglx-mesa0 libgles2 libegl1 \
    xserver-xorg-core xserver-xorg-video-dummy mesa-utils \
    x11-utils \
  && rm -rf /var/lib/apt/lists/*

# Chrome for Testing + Chromedriver (هم‌نسخه)
RUN set -eux; \
  curl -fsSL -o /tmp/versions.json https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json; \
  VERSION="$(python3 -c "import json; print(json.load(open('/tmp/versions.json'))['channels']['Stable']['version'])")"; \
  BASE="https://storage.googleapis.com/chrome-for-testing-public"; \
  curl -fsSL -o /tmp/chromedriver.zip "$BASE/${VERSION}/linux64/chromedriver-linux64.zip"; \
  curl -fsSL -o /tmp/chrome.zip       "$BASE/${VERSION}/linux64/chrome-linux64.zip"; \
  unzip -q /tmp/chromedriver.zip -d /opt/; \
  unzip -q /tmp/chrome.zip -d /opt/; \
  mv /opt/chromedriver-linux64/chromedriver /usr/local/bin/chromedriver; \
  ln -s /opt/chrome-linux64/chrome /usr/local/bin/google-chrome; \
  ln -s /opt/chrome-linux64/chrome /usr/bin/google-chrome || true; \
  chmod +x /usr/local/bin/chromedriver /usr/local/bin/google-chrome; \
  rm -rf /opt/chromedriver-linux64 /tmp/*.zip /tmp/versions.json

ENV DISPLAY=:99 \
    LIBGL_ALWAYS_SOFTWARE=1 \
    CHROME_BIN=/usr/local/bin/google-chrome \
    CHROMEDRIVER=/usr/local/bin/chromedriver \
    XDG_RUNTIME_DIR=/tmp \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

COPY 10-headless.conf /etc/X11/xorg.conf.d/10-headless.conf
COPY . /app
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]