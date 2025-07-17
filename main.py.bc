from flask import Flask, send_file
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
import time, os

app = Flask(__name__)
SCREENSHOT_PATH = "screenshot.png"

def take_screenshot():
    options = Options()
    options.binary_location = os.getenv("CHROME_BIN", "/usr/bin/google-chrome")
    options.add_argument("--headless")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--use-gl=swiftshader")
    options.add_argument("--enable-webgl")
    options.add_argument("--enable-webgl2")
    options.add_argument("--ignore-gpu-blocklist")
    options.add_argument("--window-size=1920,1080")

    service = Service(os.getenv("CHROMEDRIVER_PATH", "/usr/local/bin/chromedriver"))
    driver = webdriver.Chrome(service=service, options=options)

    driver.get("https://www.flightradar24.com/32.0,50.0/5")
    time.sleep(10)
    driver.save_screenshot(SCREENSHOT_PATH)
    driver.quit()

@app.route("/screenshot")
def screenshot():
    take_screenshot()
    return send_file(SCREENSHOT_PATH, mimetype='image/png')

@app.route("/")
def home():
    return "✅ Flightradar screenshot service is running!"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)

