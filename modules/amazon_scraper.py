import csv
import random
from datetime import datetime
from playwright.sync_api import sync_playwright
from config.settings import CSV_DIR
from modules.utils import new_context, natural_move, move_to, delay, parse_price

PRICE_SELECTORS = [
    ".apexPriceToPay .a-offscreen",
    "#corePrice_feature_div .a-price .a-offscreen",
    "#corePriceDisplay_desktop_feature_div .a-offscreen",
    ".a-price[data-a-color='price'] .a-offscreen",
    "#priceblock_ourprice",
    "#priceblock_saleprice",
    "#priceblock_dealprice",
    ".a-price .a-offscreen",
]

AVAILABILITY_SELECTORS = [
    "#availability span",
    "#outOfStock",
    "#availabilityInsideBuyBox_feature_div span",
    "#buy-now-button",  # if present, usually in stock
]


def _bot_blocked(page) -> bool:
    title = page.title().lower()
    url   = page.url.lower()
    return (
        "robot" in title
        or "captcha" in title
        or "robot" in url
        or "captcha" in url
        or page.locator("form[action*='validateCaptcha']").count() > 0
    )


def _human_browse(page) -> None:
    """Scroll and move cursor naturally before extracting data."""
    vw = page.viewport_size["width"]
    vh = page.viewport_size["height"]

    page.mouse.wheel(0, random.randint(200, 400))
    delay(0.6, 1.2)

    for _ in range(3):
        x = random.uniform(vw * 0.15, vw * 0.85)
        y = random.uniform(vh * 0.15, vh * 0.75)
        natural_move(page, x, y)
        delay(0.3, 0.7)

    page.mouse.wheel(0, random.randint(150, 350))
    delay(0.4, 0.9)


def _scrape_product(page, url: str) -> dict | None:
    page.goto(url, wait_until="domcontentloaded", timeout=30000)
    delay(1.5, 3.0)

    if _bot_blocked(page):
        print("  Amazon blocked this request (bot detection).")
        return None

    _human_browse(page)

    # Product name
    for sel in ["#productTitle", "h1.product-title-word-break", "h1"]:
        loc = page.locator(sel).first
        if loc.count() > 0:
            name = loc.text_content(timeout=5000).strip()
            if name:
                break
    else:
        name = "Unknown"

    # Price — try selectors in priority order
    price_str = ""
    for sel in PRICE_SELECTORS:
        try:
            loc = page.locator(sel).first
            if loc.count() > 0:
                val = loc.text_content(timeout=2000).strip()
                if val and any(c.isdigit() for c in val):
                    price_str = val
                    # Hover over it so you can see the cursor land on the price
                    move_to(page, loc)
                    delay(0.2, 0.4)
                    break
        except Exception:
            continue

    # Availability
    avail = "Unknown"
    for sel in AVAILABILITY_SELECTORS:
        try:
            loc = page.locator(sel).first
            if loc.count() > 0:
                val = loc.text_content(timeout=2000).strip()
                if val:
                    avail = val
                    break
        except Exception:
            continue

    in_stock = (
        "in stock" in avail.lower()
        or ("unavailable" not in avail.lower() and "out of stock" not in avail.lower() and bool(price_str))
    )

    return {
        "name":         name,
        "price":        price_str,
        "availability": avail,
        "in_stock":     in_stock,
        "url":          url,
    }


def get_price(url: str) -> dict | None:
    """Fetch current price for one Amazon URL. Returns dict for the price monitor."""
    with sync_playwright() as p:
        browser, ctx = new_context(p)
        page = ctx.new_page()
        try:
            result = _scrape_product(page, url)
            if not result:
                return None
            return {
                "name":      result["name"],
                "price":     parse_price(result["price"]) if result["price"] else 0.0,
                "price_str": result["price"],
                "in_stock":  result["in_stock"],
            }
        except Exception as e:
            print(f"  Amazon get_price error: {e}")
            return None
        finally:
            browser.close()


def _save_csv(results: list) -> str:
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = CSV_DIR / f"amazon_{ts}.csv"
    fields = ["timestamp", "name", "price", "availability", "url"]
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in results:
            w.writerow({
                "timestamp":    ts,
                "name":         r["name"],
                "price":        r["price"],
                "availability": r["availability"],
                "url":          r["url"],
            })
    return str(path)


def run():
    print("\n  Enter Amazon.ca product URLs, one per line.")
    print("  Press Enter on a blank line when done.\n")

    urls = []
    while True:
        u = input("  URL: ").strip()
        if not u:
            break
        if "amazon" not in u:
            print("  That doesn't look like an Amazon URL — skipping.")
            continue
        urls.append(u)

    if not urls:
        print("  No URLs entered.")
        return

    results = []
    with sync_playwright() as p:
        browser, ctx = new_context(p)
        page = ctx.new_page()

        for i, url in enumerate(urls, 1):
            print(f"\n  [{i}/{len(urls)}] {url[:65]}...")
            delay(2.0, 4.0)
            r = _scrape_product(page, url)
            if r:
                results.append(r)
                print(f"    Name         : {r['name'][:60]}")
                print(f"    Price        : {r['price'] or 'not found'}")
                print(f"    Availability : {r['availability']}")
            else:
                print("    Skipped (no data).")

        browser.close()

    if not results:
        print("\n  Nothing saved.")
        return

    path = _save_csv(results)
    print(f"\n  Saved {len(results)} product(s) to {path}")
