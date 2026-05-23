import random
import re
import time

USER_AGENTS = [
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (X11; Linux x86_64; rv:125.0) Gecko/20100101 Firefox/125.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0",
]

VIEWPORTS = [
    {"width": 1280, "height": 800},
    {"width": 1366, "height": 768},
    {"width": 1440, "height": 900},
]


def pick_ua() -> str:
    return random.choice(USER_AGENTS)


def delay(lo: float = 0.8, hi: float = 2.2) -> None:
    time.sleep(random.uniform(lo, hi))


def natural_move(page, tx: float, ty: float, steps: int = 28) -> None:
    """Bezier-curved cursor path from near viewport center to (tx, ty)."""
    vw = page.viewport_size["width"]
    vh = page.viewport_size["height"]
    sx = vw / 2 + random.uniform(-100, 100)
    sy = vh / 2 + random.uniform(-80, 80)
    # Control point curves the path
    cx = (sx + tx) / 2 + random.uniform(-70, 70)
    cy = (sy + ty) / 2 + random.uniform(-70, 70)
    for i in range(1, steps + 1):
        t = i / steps
        x = (1 - t) ** 2 * sx + 2 * (1 - t) * t * cx + t ** 2 * tx
        y = (1 - t) ** 2 * sy + 2 * (1 - t) * t * cy + t ** 2 * ty
        page.mouse.move(x, y)
        time.sleep(random.uniform(0.006, 0.022))


def move_to(page, locator) -> None:
    """Natural cursor move to an element's bounding box center."""
    try:
        box = locator.bounding_box()
        if box:
            tx = box["x"] + box["width"] / 2 + random.uniform(-4, 4)
            ty = box["y"] + box["height"] / 2 + random.uniform(-4, 4)
            natural_move(page, tx, ty)
    except Exception:
        pass


def smart_click(page, locator) -> None:
    locator.scroll_into_view_if_needed()
    move_to(page, locator)
    delay(0.1, 0.35)
    locator.click()


def smart_fill(page, locator, text: str) -> None:
    locator.scroll_into_view_if_needed()
    move_to(page, locator)
    delay(0.1, 0.25)
    locator.click()
    delay(0.05, 0.15)
    locator.fill("")
    for ch in text:
        locator.type(ch, delay=random.randint(45, 130))


def parse_price(text: str) -> float:
    """Extract first price-like number, stripping currency symbols and thousand commas."""
    cleaned = re.sub(r"(\d),(\d{3})", r"\1\2", text)
    m = re.search(r"\d+\.?\d*", cleaned)
    return float(m.group()) if m else 0.0


def new_context(playwright, headless: bool = False):
    """Launch a stealth Chromium browser + context with randomised fingerprint."""
    browser = playwright.chromium.launch(
        headless=headless,
        slow_mo=random.randint(180, 380),
    )
    ctx = browser.new_context(
        user_agent=pick_ua(),
        viewport=random.choice(VIEWPORTS),
        locale="en-CA",
        timezone_id="America/Toronto",
        extra_http_headers={
            "Accept-Language": "en-CA,en;q=0.9",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "DNT": "1",
        },
    )
    return browser, ctx
