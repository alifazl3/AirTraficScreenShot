FROM python:3.12-slim

LABEL maintainer="Ali Fazlollahi"

# نصب ابزارهای مورد نیاز و Chrome وابسته‌ها
RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    gnupg \
    curl \
    fonts-liberation \
    libglib2.0-0 \
    libnss3 \
    libgconf-2-4 \
    libxss1 \
    libasound2 \
    libxtst6 \
    libx11-xcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxi6 \
    libgbm1 \
    libxrandr2 \
    libatk1.0-0 \
    libgtk-3-0 \
    mesa-utils \
    xvfb \
    x11-utils \
    && rm -rf /var/lib/apt/lists/*

# نصب Google Chrome (نسخه Stable)
RUN wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | apt-key add - && \
    echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list && \
    apt-get update && apt-get install -y google-chrome-stable && \
    rm -rf /var/lib/apt/lists/*

# نصب ChromeDriver هماهنگ با نسخه‌ی مرورگر
RUN CHROME_VERSION=$(google-chrome-stable --version | grep -oP '\d+\.\d+\.\d+') && \
    DRIVER_VERSION=$(curl -s "https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json" | \
      python3 -c "import sys, json; print(json.load(sys.stdin)['channels']['Stable']['version'])") && \
    wget -O /tmp/chromedriver.zip https://edgedl.me.gvt1.com/edgedl/chrome/chrome-for-testing/${DRIVER_VERSION}/linux64/chromedriver-linux64.zip && \
    unzip /tmp/chromedriver.zip -d /tmp/ && \
    mv /tmp/chromedriver-linux64/chromedriver /usr/local/bin/chromedriver && \
    chmod +x /usr/local/bin/chromedriver

# نصب پکیج‌های پایتون مورد نیاز
RUN pip install --no-cache-dir \
    flask \
    selenium \
    webdriver-manager \
    requests \
    pandas

# متغیرهای محیطی برای Chrome و Chromedriver
ENV CHROME_BIN="/usr/bin/google-chrome"
ENV CHROMEDRIVER_PATH="/usr/local/bin/chromedriver"

# باز کردن پورت Flask
EXPOSE 5000

RUN pip install --no-cache-dir flask selenium gunicorn

# اجرای برنامه‌ی Flask با Xvfb برای فعال‌سازی WebGL
CMD xvfb-run --auto-servernum --server-args="-screen 0 1920x1080x24" gunicorn -b 0.0.0.0:5000 main:app


