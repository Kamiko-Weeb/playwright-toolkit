import csv
import random
from datetime import datetime
from playwright.sync_api import sync_playwright
from config.settings import CSV_DIR
from modules.utils import new_context, move_to, smart_click, delay, parse_price, natural_move

DEFAULT_URL = "https://store.steampowered.com/search/?specials=1"


def _dismiss_dialogs(page) -> None:
    """Bypass age gates and cookie banners."""
    # Age gate
    if page.locator("#ageYear").count() > 0:
        page.select_option("#ageYear", "1990")
        for sel in ["#view_product_page_btn", "a.btnv6_blue_hoverfade"]:
            btn = page.locator(sel)
            if btn.count() > 0:
                smart_click(page, btn)
                page.wait_for_load_state("networkidle")
                break

    # Cookie / preference banners
    for sel in [
        "button[id*='cookie']",
        "button:has-text('Accept all')",
        "button:has-text('OK')",
    ]:
        try:
            loc = page.locator(sel)
            if loc.count() > 0 and loc.first.is_visible():
                smart_click(page, loc.first)
                delay(0.3, 0.6)
                break
        except Exception:
            pass


def _scrape_search(page, limit: int = 20) -> list:
    """Extract games from a Steam search results page."""
    print("  Waiting for search results to load...")
    try:
        page.wait_for_selector("a.search_result_row", timeout=20000)
    except Exception:
        print("  Search results did not appear.")
        return []

    delay(1.0, 2.0)

    # Scroll naturally through the list
    for _ in range(4):
        page.mouse.wheel(0, random.randint(250, 550))
        delay(0.5, 1.0)

    rows = page.locator("a.search_result_row")
    total = min(rows.count(), limit)
    print(f"  Found {total} result(s).")

    results = []
    for i in range(total):
        try:
            row = rows.nth(i)
            move_to(page, row)
            delay(0.2, 0.5)

            name_loc = row.locator(".title")
            name = name_loc.text_content(timeout=3000).strip() if name_loc.count() > 0 else "Unknown"
            href = row.get_attribute("href") or ""

            if row.locator(".discount_pct").count() > 0:
                discount  = row.locator(".discount_pct").text_content().strip()
                current   = row.locator(".discount_final_price").text_content().strip()
                original  = row.locator(".discount_original_price").text_content().strip()
            else:
                discount = "0%"
                pl = row.locator(".search_price")
                current  = pl.text_content().strip() if pl.count() > 0 else "N/A"
                original = current

            results.append({
                "name": name,
                "current_price": current,
                "original_price": original,
                "discount_pct": discount,
                "url": href,
            })
        except Exception as e:
            print(f"  Row {i} skipped: {e}")

    return results


def _scrape_app(page, url: str) -> list:
    """Scrape a single Steam store app page."""
    page.goto(url)
    page.wait_for_load_state("networkidle")
    _dismiss_dialogs(page)
    delay(0.5, 1.2)

    # Scroll down to reveal the purchase section
    for _ in range(2):
        page.mouse.wheel(0, random.randint(300, 500))
        delay(0.4, 0.8)

    name_loc = page.locator("#appHubAppName")
    name = name_loc.text_content().strip() if name_loc.count() > 0 else "Unknown"

    if page.locator(".discount_pct").count() > 0:
        discount  = page.locator(".discount_pct").first.text_content().strip()
        current   = page.locator(".discount_final_price").first.text_content().strip()
        original  = page.locator(".discount_original_price").first.text_content().strip()
    elif page.locator(".game_purchase_price").count() > 0:
        current  = page.locator(".game_purchase_price").first.text_content().strip()
        original = current
        discount = "0%"
    else:
        current = original = "Free to Play"
        discount = "N/A"

    return [{"name": name, "current_price": current, "original_price": original,
              "discount_pct": discount, "url": url}]


def get_price(url: str) -> dict | None:
    """Fetch current price for one Steam URL. Returns dict for the price monitor."""
    with sync_playwright() as p:
        browser, ctx = new_context(p)
        page = ctx.new_page()
        try:
            if "/app/" in url:
                results = _scrape_app(page, url)
            else:
                page.goto(url)
                page.wait_for_load_state("networkidle")
                _dismiss_dialogs(page)
                results = _scrape_search(page, limit=1)

            if not results:
                return None
            r = results[0]
            price_str = r["current_price"]
            in_stock  = bool(price_str) and "unavailable" not in price_str.lower() and price_str != "N/A"
            price_val = 0.0 if price_str in ("Free to Play", "N/A", "") else parse_price(price_str)
            return {
                "name":      r["name"],
                "price":     price_val,
                "price_str": price_str,
                "discount":  r["discount_pct"],
                "in_stock":  in_stock,
            }
        except Exception as e:
            print(f"  Steam get_price error: {e}")
            return None
        finally:
            browser.close()


def _save_csv(results: list) -> str:
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    path = CSV_DIR / f"steam_{ts}.csv"
    fields = ["timestamp", "name", "current_price", "original_price", "discount_pct", "url"]
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in results:
            w.writerow({"timestamp": ts, **r})
    return str(path)


def run():
    url = input(f"\n  Steam URL (search or app page) [{DEFAULT_URL}]: ").strip() or DEFAULT_URL

    with sync_playwright() as p:
        browser, ctx = new_context(p)
        page = ctx.new_page()

        print(f"\n  Navigating to {url} ...")
        page.goto(url)
        page.wait_for_load_state("networkidle")
        _dismiss_dialogs(page)

        if "/app/" in url:
            results = _scrape_app(page, url)
        else:
            results = _scrape_search(page)

        browser.close()

    if not results:
        print("  Nothing scraped.")
        return

    print(f"\n  {len(results)} game(s) found:")
    for r in results[:8]:
        print(f"    {r['name']:<40} {r['current_price']:<12} ({r['discount_pct']})")
    if len(results) > 8:
        print(f"    ... and {len(results) - 8} more")

    path = _save_csv(results)
    print(f"\n  Saved to {path}")
