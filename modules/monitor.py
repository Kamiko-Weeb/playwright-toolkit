import json
import time
from datetime import datetime
from playwright.sync_api import sync_playwright
from config.settings import SCREENSHOTS_DIR, WATCHLIST_FILE
from modules import steam_scraper, amazon_scraper

DEFAULT_SCREENSHOT_URL = "https://news.ycombinator.com"
DEFAULT_INTERVAL = 10
DEFAULT_COUNT = 3


# ── Screenshots ───────────────────────────────────────────────────────────────

def _capture(page, url: str) -> str:
    page.goto(url)
    page.wait_for_load_state("networkidle")

    width  = page.viewport_size["width"]
    height = page.viewport_size["height"]
    steps  = 6
    for i in range(steps + 1):
        y = int((height / steps) * i)
        x = width // 2 + (50 if i % 2 == 0 else -50)
        page.mouse.move(x, y)
        time.sleep(0.15)

    ts       = datetime.now().strftime("%Y%m%d_%H%M%S")
    filepath = SCREENSHOTS_DIR / f"monitor_{ts}.png"
    page.screenshot(path=str(filepath), full_page=True)
    return str(filepath)


def _run_screenshots() -> None:
    url = input(f"\n  URL to screenshot [{DEFAULT_SCREENSHOT_URL}]: ").strip() or DEFAULT_SCREENSHOT_URL

    try:
        interval = int(input(f"  Interval in seconds [{DEFAULT_INTERVAL}]: ").strip() or DEFAULT_INTERVAL)
        count    = int(input(f"  Number of screenshots [{DEFAULT_COUNT}]: ").strip() or DEFAULT_COUNT)
    except ValueError:
        interval, count = DEFAULT_INTERVAL, DEFAULT_COUNT

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False, slow_mo=300)
        page    = browser.new_page(viewport={"width": 1280, "height": 800})

        for i in range(1, count + 1):
            print(f"\n  [{i}/{count}] Capturing {url} ...")
            path = _capture(page, url)
            print(f"  Saved: {path}")
            if i < count:
                print(f"  Waiting {interval}s...")
                time.sleep(interval)

        print(f"\n  Done. {count} screenshot(s) in output/screenshots/")
        time.sleep(2)
        browser.close()


# ── Price watchlist ───────────────────────────────────────────────────────────

def _load() -> dict:
    if WATCHLIST_FILE.exists():
        with open(WATCHLIST_FILE) as f:
            return json.load(f)
    return {"items": []}


def _save(data: dict) -> None:
    with open(WATCHLIST_FILE, "w") as f:
        json.dump(data, f, indent=2)


def _detect_site(url: str) -> str:
    if "steampowered.com" in url:
        return "steam"
    if "amazon." in url:
        return "amazon"
    return "unknown"


def _add_to_watchlist() -> None:
    url = input("\n  Product/game URL to watch: ").strip()
    if not url:
        print("  No URL entered.")
        return

    site = _detect_site(url)
    if site == "unknown":
        print("  Only Steam and Amazon URLs are supported.")
        return

    data = _load()
    if any(item["url"] == url for item in data["items"]):
        print("  Already in watchlist.")
        return

    label = input("  Label (press Enter to use URL): ").strip() or url[:50]
    data["items"].append({
        "url":           url,
        "site":          site,
        "name":          label,
        "last_price":    0.0,
        "last_in_stock": True,
        "last_checked":  None,
    })
    _save(data)
    print(f"  Added: {label} ({site})")


def _list_watchlist() -> None:
    data = _load()
    if not data["items"]:
        print("\n  Watchlist is empty.")
        return
    print(f"\n  Watchlist ({len(data['items'])} item(s)):")
    for i, item in enumerate(data["items"], 1):
        checked = item["last_checked"] or "never"
        price   = f"${item['last_price']:.2f}" if item["last_price"] else "—"
        print(f"  {i:>2}. [{item['site']:6}] {item['name'][:45]:<45} last: {price} @ {checked[:16]}")


def _run_price_watch() -> None:
    data = _load()
    if not data["items"]:
        print("\n  Watchlist is empty — add items first (option 3).")
        return

    print(f"\n  Checking {len(data['items'])} item(s)...\n")
    alerts = []

    for item in data["items"]:
        print(f"  {item['name']}")

        current = None
        if item["site"] == "steam":
            current = steam_scraper.get_price(item["url"])
        elif item["site"] == "amazon":
            current = amazon_scraper.get_price(item["url"])

        if not current:
            print("    Could not fetch — skipping.\n")
            continue

        now_price    = current["price"]
        now_in_stock = current["in_stock"]
        was_price    = item["last_price"]
        was_in_stock = item["last_in_stock"]

        print(f"    Price    : {current['price_str']}  (prev: {'${:.2f}'.format(was_price) if was_price else 'n/a'})")
        print(f"    In stock : {now_in_stock}\n")

        if was_price > 0 and now_price < was_price:
            saved = was_price - now_price
            alerts.append(
                f"PRICE DROP   {item['name']}\n"
                f"             ${now_price:.2f}  (was ${was_price:.2f}, save ${saved:.2f})"
            )

        if not was_in_stock and now_in_stock:
            alerts.append(
                f"BACK IN STOCK  {item['name']}\n"
                f"               now {current['price_str']}"
            )

        item["last_price"]    = now_price
        item["last_in_stock"] = now_in_stock
        item["last_checked"]  = datetime.now().isoformat()
        if current.get("name") and current["name"] != "Unknown":
            item["name"] = current["name"]

    _save(data)

    if alerts:
        print("\n" + "!" * 54)
        for a in alerts:
            for line in a.splitlines():
                print(f"  {line}")
            print()
        print("!" * 54)
    else:
        print("  No changes detected.")


# ── Entry point ───────────────────────────────────────────────────────────────

def run() -> None:
    print("\n  Monitor")
    print("  ─────────────────────────────────")
    print("  1. Screenshots")
    print("  2. Check price watchlist")
    print("  3. Add item to watchlist")
    print("  4. List watchlist")

    choice = input("\n  Pick: ").strip()

    if choice == "1":
        _run_screenshots()
    elif choice == "2":
        _run_price_watch()
    elif choice == "3":
        _add_to_watchlist()
    elif choice == "4":
        _list_watchlist()
    else:
        print("  Invalid choice.")
