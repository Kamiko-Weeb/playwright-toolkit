import time
from datetime import datetime
from playwright.sync_api import sync_playwright
from config.settings import SCREENSHOTS_DIR

DEFAULT_URL = "https://news.ycombinator.com"
DEFAULT_INTERVAL = 10
DEFAULT_COUNT = 3


def capture(page, url: str) -> str:
    page.goto(url)
    page.wait_for_load_state("networkidle")

    # Visibly sweep the cursor down the page before capturing
    width = page.viewport_size["width"]
    height = page.viewport_size["height"]
    steps = 6
    for i in range(steps + 1):
        y = int((height / steps) * i)
        x = width // 2 + (50 if i % 2 == 0 else -50)  # slight zigzag
        page.mouse.move(x, y)
        time.sleep(0.15)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filepath = SCREENSHOTS_DIR / f"monitor_{timestamp}.png"
    page.screenshot(path=str(filepath), full_page=True)
    return str(filepath)


def run():
    url = input(f"\n  URL to monitor [{DEFAULT_URL}]: ").strip() or DEFAULT_URL

    try:
        interval = int(
            input(f"  Interval between shots in seconds [{DEFAULT_INTERVAL}]: ").strip()
            or DEFAULT_INTERVAL
        )
        count = int(
            input(f"  Number of screenshots [{DEFAULT_COUNT}]: ").strip()
            or DEFAULT_COUNT
        )
    except ValueError:
        interval, count = DEFAULT_INTERVAL, DEFAULT_COUNT

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False, slow_mo=300)
        page = browser.new_page(viewport={"width": 1280, "height": 800})

        for i in range(1, count + 1):
            print(f"\n  [{i}/{count}] Capturing screenshot of {url} ...")
            path = capture(page, url)
            print(f"  Saved: {path}")

            if i < count:
                print(f"  Waiting {interval}s before next capture...")
                time.sleep(interval)

        print(f"\n  Done. {count} screenshot(s) saved to output/screenshots/")
        time.sleep(2)
        browser.close()
