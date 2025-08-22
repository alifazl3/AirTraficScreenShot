import os, time, threading, traceback, shutil, tempfile
from datetime import datetime, timedelta
from flask import Flask, send_file, jsonify
from selenium import webdriver
from selenium.webdriver.chrome.service import Service
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.common.by import By
from selenium.webdriver.support import expected_conditions as EC

app = Flask(__name__)

# ====== Settings ======
SCREENSHOT_PATH = os.getenv("SHOT_PATH", "screenshot.png")
TARGET_URL = os.getenv("TARGET_URL", "https://www.flightradar24.com/32.0,50.0/5")
REFRESH_EVERY = int(os.getenv("REFRESH_EVERY", "60"))   # seconds
SHOT_TTL = int(os.getenv("SHOT_TTL", "180"))            # maximum file age
NAV_TIMEOUT = int(os.getenv("NAV_TIMEOUT", "25"))       # max navigation time (to avoid 524)
WINDOW = os.getenv("WINDOW", "1440,900")                # 1920,1080 if you want higher resolution

_last_ok = None                   # datetime of the last successful shot
_state_lock = threading.Lock()    # for reading/writing _last_ok
_shot_lock = threading.Lock()     # prevent concurrent Chrome runs


def _env(name, default=None, alts=()):
    v = os.getenv(name)
    if v: return v
    for a in alts:
        v = os.getenv(a)
        if v: return v
    return default


def _build_driver(user_data_dir: str):
    chrome_bin = _env("CHROME_BIN", "/usr/local/bin/google-chrome", ("GOOGLE_CHROME_BIN",))
    chromedriver_path = _env("CHROMEDRIVER", "/usr/local/bin/chromedriver", ("CHROMEDRIVER_PATH",))

    opts = Options()
    opts.binary_location = chrome_bin

    # Important: ANGLE → SwiftShader (software WebGL2, but stable inside container)
    flags = [
        "--no-sandbox",
        "--disable-dev-shm-usage",
        f"--window-size={WINDOW}",
        "--user-agent=Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36",
        "--use-angle=swiftshader",
        "--enable-webgl",
        "--enable-webgl2",
        "--ignore-gpu-blocklist",
        # Note: we intentionally do not add --disable-gpu or --use-gl=desktop
        "--no-first-run",
        "--no-default-browser-check",
        f"--user-data-dir={user_data_dir}",  # unique profile
        "--profile-directory=Default",
    ]
    extra = os.getenv("CHROME_FLAGS", "").split()
    for f in flags + extra:
        if f: opts.add_argument(f)

    service = Service(chromedriver_path)
    return webdriver.Chrome(service=service, options=opts)


def _click_consent(driver, max_wait=8):
    wait = WebDriverWait(driver, max_wait)
    sels = [
        (By.CSS_SELECTOR, "#onetrust-accept-btn-handler"),
        (By.CSS_SELECTOR, "button#didomi-notice-agree-button"),
        (By.XPATH, "//button[contains(translate(.,'AGREE','agree'),'agree')]"),
        (By.XPATH, "//button[contains(., 'Accept')]"),
        (By.XPATH, "//button[contains(., 'I agree')]"),
    ]
    for by, s in sels:
        try:
            btn = wait.until(EC.element_to_be_clickable((by, s)))
            driver.execute_script("arguments[0].click();", btn)
            return True
        except Exception:
            pass
    for fr in driver.find_elements(By.CSS_SELECTOR, "iframe"):
        try:
            driver.switch_to.frame(fr)
            for by, s in sels:
                try:
                    btn = wait.until(EC.element_to_be_clickable((by, s)))
                    driver.execute_script("arguments[0].click();", btn)
                    driver.switch_to.default_content()
                    return True
                except Exception:
                    pass
        finally:
            driver.switch_to.default_content()
    try:
        driver.execute_script("""
            const texts=['agree and close','agree','accept','i agree'];
            const btns=[...document.querySelectorAll('button,[role="button"]')];
            const t=btns.find(b=>texts.some(x=>(b.innerText||'').toLowerCase().includes(x)));
            if(t) t.click();
        """)
    except Exception:
        pass
    return False


def _has_webgl2(driver):
    try:
        return driver.execute_script(
            "try{var c=document.createElement('canvas');"
            "return !!(c.getContext('webgl2')||c.getContext('experimental-webgl2'));}"
            "catch(e){return false;}"
        )
    except Exception:
        return False


def take_screenshot_once():
    """Single run with temporary profile + lock; suitable for Cloudflare and stable inside container."""
    global _last_ok
    with _shot_lock:  # only one Chrome at a time
        start = time.time()
        user_dir = tempfile.mkdtemp(prefix="chrome-profile-")
        driver = None
        try:
            driver = _build_driver(user_dir)
            driver.set_page_load_timeout(NAV_TIMEOUT)
            driver.get(TARGET_URL)

            WebDriverWait(driver, min(10, NAV_TIMEOUT)).until(
                lambda d: d.execute_script("return document.readyState") == "complete"
            )
            _click_consent(driver, max_wait=5)

            supported = _has_webgl2(driver)
            app.logger.info("WebGL2 supported (swiftshader): %s", supported)

            time.sleep(2)  # a little time for rendering
            driver.save_screenshot(SCREENSHOT_PATH)
            with _state_lock:
                _last_ok = datetime.utcnow()
            return True
        except Exception as e:
            app.logger.error("Screenshot failed: %s\n%s", e, traceback.format_exc())
            return False
        finally:
            try:
                if driver:
                    driver.quit()
            finally:
                shutil.rmtree(user_dir, ignore_errors=True)
                app.logger.info("shot took %.1fs", time.time() - start)


def _refresher_loop():
    while True:
        ok = take_screenshot_once()
        time.sleep(REFRESH_EVERY if ok else 10)


@app.route("/")
def home():
    with _state_lock:
        stamp = _last_ok.isoformat() if _last_ok else "—"
    return f"✅ Flightradar screenshot service (last_ok: {stamp})"


@app.route("/screenshot")
def screenshot():
    with _state_lock:
        fresh = _last_ok and (datetime.utcnow() - _last_ok) <= timedelta(seconds=SHOT_TTL)
    if not fresh or not os.path.exists(SCREENSHOT_PATH):
        take_screenshot_once()  # quick attempt
    if os.path.exists(SCREENSHOT_PATH):
        return send_file(SCREENSHOT_PATH, mimetype="image/png")
    return jsonify(error="no screenshot available yet"), 503


@app.route("/refresh")
def refresh():
    ok = take_screenshot_once()
    return jsonify(ok=ok, ts=datetime.utcnow().isoformat()), (200 if ok else 500)


def _maybe_start_bg():
    t = threading.Thread(target=_refresher_loop, daemon=True)
    t.start()


if __name__ == "__main__":
    _maybe_start_bg()
    app.run(host="0.0.0.0", port=5000)
else:
    _maybe_start_bg()
