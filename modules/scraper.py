import csv
import time
from datetime import datetime
from playwright.sync_api import sync_playwright
from config.settings import CSV_DIR

DEFAULT_URL = "https://books.toscrape.com"


def hover_then_act(locator, action="click", text=None):
    """Scroll into view, hover (visible cursor move), then act."""
    locator.scroll_into_view_if_needed()
    locator.hover()
    time.sleep(0.3)
    if action == "click":
        locator.click()
    elif action == "fill" and text is not None:
        locator.fill(text)


def scrape(url: str) -> dict:
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False, slow_mo=400)
        page = browser.new_page(viewport={"width": 1280, "height": 800})

        print(f"\n  Navigating to {url} ...")
        page.goto(url)
        page.wait_for_load_state("networkidle")

        title = page.title()

        headings = [
            h.strip()
            for h in page.locator("h1, h2, h3").all_text_contents()
            if h.strip()
        ]

        prices = [
            p.strip()
            for p in page.locator(
                ".price_color, [class*='price'], [class*='Price']"
            ).all_text_contents()
            if p.strip()
        ]
        if not prices:
            prices = [
                t.strip()
                for t in page.locator("*").all_text_contents()
                if any(sym in t for sym in ["£", "$", "€"]) and len(t.strip()) < 20
            ]

        # Hover over the first few links so the cursor visibly moves around
        print("  Scanning links...")
        all_links_loc = page.locator("a[href]")
        link_count = all_links_loc.count()
        for i in range(min(6, link_count)):
            try:
                lnk = all_links_loc.nth(i)
                lnk.scroll_into_view_if_needed()
                lnk.hover()
                time.sleep(0.2)
            except Exception:
                pass

        links = page.eval_on_selector_all(
            "a[href]",
            "els => els.map(e => ({text: e.textContent.trim(), href: e.href}))",
        )

        browser.close()

    return {"title": title, "headings": headings, "prices": prices, "links": links}


def save_to_csv(data: dict, url: str) -> str:
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filepath = CSV_DIR / f"scrape_{timestamp}.csv"

    with open(filepath, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["type", "content", "source_url"])
        writer.writerow(["page_title", data["title"], url])
        for h in data["headings"]:
            writer.writerow(["heading", h, url])
        for price in data["prices"]:
            writer.writerow(["price", price, url])
        for link in data["links"][:100]:
            writer.writerow(["link", link["text"], link["href"]])

    return str(filepath)


def run():
    url = input(f"\n  URL to scrape [{DEFAULT_URL}]: ").strip() or DEFAULT_URL
    data = scrape(url)

    print(f"\n  Results:")
    print(f"    Page title : {data['title']}")
    print(f"    Headings   : {len(data['headings'])}")
    print(f"    Prices     : {len(data['prices'])}")
    print(f"    Links      : {len(data['links'])}")

    path = save_to_csv(data, url)
    print(f"\n  Saved to {path}")
