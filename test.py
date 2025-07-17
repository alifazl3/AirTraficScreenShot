import time
from main import take_screenshot

for i in range(1000):
    print(f"▶️ Test #{i+1}")
    try:
        take_screenshot()
    except Exception as e:
        print("❌ Error:", e)
    time.sleep(30)  # هر 30 ثانیه یک بار
