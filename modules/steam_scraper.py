import csv
import random
import re
from datetime import datetime
from playwright.sync_api import sync_playwright
from config.settings import CSV_DIR
from modules.utils import new_context, move_to, smart_click, delay, parse_price, natural_move

DEFAULT_URL = "https://store.steampowered.com/search/?specials=1"

# Steam internal tag IDs. Find more at store.steampowered.com/tag/browse/
STEAM_TAGS: dict[str, int] = {
    # ── Multiplayer / social ─────────────────────────────────────────
    "multiplayer":              3,
    "co-op":                    9,
    "coop":                     9,
    "singleplayer":          4182,
    "pvp":                   4187,
    "massively multiplayer":  128,
    "local multiplayer":     7368,
    "online co-op":          3843,

    # ── Genre ────────────────────────────────────────────────────────
    "action":                  19,
    "adventure":               25,
    "rpg":                    122,
    "simulation":              28,
    "sports":                 701,
    "racing":                 699,
    "horror":                  87,
    "puzzle":                1664,
    "platformer":            1625,
    "fighting":               788,
    "indie":                  492,
    "casual":                 597,

    # ── Sub-genre / play style ───────────────────────────────────────
    "fps":                      1,
    "shooter":               1746,
    "open world":            1774,
    "openworld":             1774,
    "survival":              1656,
    "roguelike":             1716,
    "roguelite":             1716,
    "sandbox":               3716,
    "battle royale":         4231,
    "br":                    4231,
    "tower defense":         1757,
    "turn-based":            1668,
    "turn based":            1668,
    "rts":                   1693,
    "card game":             2048,
    "cards":                 2048,
    "stealth":               1695,
    "strategy":              9,

    # ── Theme / aesthetic ────────────────────────────────────────────
    "anime":                 4085,
    "cyberpunk":             3942,
    "fantasy":               1684,
    "sci-fi":                3839,
    "scifi":                 3839,
    "pixel art":             1890,
    "2d":                    3871,
    "visual novel":          1688,
    "vn":                    1688,
    "early access":           493,
}


def _build_tag_url(base_url: str, tag_ids: list[str]) -> str:
    """Inject tags=id1,id2,... into a Steam search URL, replacing any prior tags param."""
    cleaned = re.sub(r"(&?tags=[^&]*)", "", base_url).rstrip("&").rstrip("?")
    sep = "&" if "?" in cleaned else "?"
    return f"{cleaned}{sep}tags={','.join(tag_ids)}"


def _resolve_tags(raw_input: str) -> tuple[str, str]:
    """
    Parse the user's tag string into (active_tag_names, filter_url_fragment).
    Returns (label, comma-joined IDs) — or ("", "") if nothing matched.
    """
    tokens = [t.strip().lower() for t in raw_input.split(",") if t.strip()]
    matched: dict[str, int] = {}
    unknown: list[str] = []

    for token in tokens:
        if token in STEAM_TAGS:
            matched[token] = STEAM_TAGS[token]
        else:
            unknown.append(token)

    if unknown:
        print(f"  Unrecognized tag(s), skipped: {', '.join(unknown)}")
        print(f"  Supported: {', '.join(sorted(STEAM_TAGS))}\n")

    if not matched:
        return "", ""

    label   = ", ".join(matched.keys())
    id_list = [str(v) for v in dict.fromkeys(matched.values())]  # dedup, preserve order
    return label, ",".join(id_list)


# ── Internal scrape helpers ───────────────────────────────────────────────────

def _dismiss_dialogs(page) -> None:
    """Bypass age gates and cookie banners."""
    if page.locator("#ageYear").count() > 0:
        page.select_option("#ageYear", "1990")
        for sel in ["#view_product_page_btn", "a.btnv6_blue_hoverfade"]:
            btn = page.locator(sel)
            if btn.count() > 0:
                smart_click(page, btn)
                page.wait_for_load_state("networkidle")
                break

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

    for _ in range(4):
        page.mouse.wheel(0, random.randint(250, 550))
        delay(0.5, 1.0)

    rows  = page.locator("a.search_result_row")
    total = min(rows.count(), limit)
    print(f"  Found {total} result(s).")

    results = []
    for i in range(total):
        try:
            row = rows.nth(i)
            move_to(page, row)
            delay(0.2, 0.5)

            name_loc = row.locator(".title")
            name     = name_loc.text_content(timeout=3000).strip() if name_loc.count() > 0 else "Unknown"
            href     = row.get_attribute("href") or ""

            if row.locator(".discount_pct").count() > 0:
                discount = row.locator(".discount_pct").text_content().strip()
                current  = row.locator(".discount_final_price").text_content().strip()
                original = row.locator(".discount_original_price").text_content().strip()
            else:
                discount = "0%"
                pl       = row.locator(".search_price")
                current  = pl.text_content().strip() if pl.count() > 0 else "N/A"
                original = current

            results.append({
                "name":          name,
                "current_price": current,
                "original_price": original,
                "discount_pct":  discount,
                "tags":          "",   # filled in by run()
                "url":           href,
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

    for _ in range(2):
        page.mouse.wheel(0, random.randint(300, 500))
        delay(0.4, 0.8)

    name_loc = page.locator("#appHubAppName")
    name     = name_loc.text_content().strip() if name_loc.count() > 0 else "Unknown"

    if page.locator(".discount_pct").count() > 0:
        discount = page.locator(".discount_pct").first.text_content().strip()
        current  = page.locator(".discount_final_price").first.text_content().strip()
        original = page.locator(".discount_original_price").first.text_content().strip()
    elif page.locator(".game_purchase_price").count() > 0:
        current  = page.locator(".game_purchase_price").first.text_content().strip()
        original = current
        discount = "0%"
    else:
        current = original = "Free to Play"
        discount = "N/A"

    return [{"name": name, "current_price": current, "original_price": original,
              "discount_pct": discount, "tags": "", "url": url}]


# ── Price monitor helper (no tag filtering needed) ────────────────────────────

def get_price(url: str) -> dict | None:
    """Fetch current price for one Steam URL. Used by the price monitor."""
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
            r         = results[0]
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


# ── CSV output ────────────────────────────────────────────────────────────────

def _save_csv(results: list) -> str:
    ts     = datetime.now().strftime("%Y%m%d_%H%M%S")
    path   = CSV_DIR / f"steam_{ts}.csv"
    fields = ["timestamp", "name", "current_price", "original_price", "discount_pct", "tags", "url"]
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for r in results:
            w.writerow({"timestamp": ts, **r})
    return str(path)


# ── Entry point ───────────────────────────────────────────────────────────────

def run() -> None:
    url = input(f"\n  Steam URL (search or app page) [{DEFAULT_URL}]: ").strip() or DEFAULT_URL

    # Tag filter — only meaningful for search/specials pages, not individual app pages
    active_tags = ""
    tag_raw = input("  Filter by tags (e.g. fps, rpg, multiplayer) or Enter to skip: ").strip()

    if tag_raw:
        if "/app/" in url:
            active_tags = tag_raw
            print("  Note: tag filtering only works on search pages — tags recorded in CSV only.")
        else:
            label, id_csv = _resolve_tags(tag_raw)
            if id_csv:
                active_tags = label
                url = _build_tag_url(url, id_csv.split(","))
                print(f"  Tags applied : {label}")
                print(f"  Filter URL   : {url}")
            else:
                print("  No valid tags matched — scraping without tag filter.")

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

    # Stamp every row with the active tag filter
    for r in results:
        r["tags"] = active_tags

    print(f"\n  {len(results)} game(s) found:")
    for r in results[:8]:
        print(f"    {r['name']:<42} {r['current_price']:<12} ({r['discount_pct']})")
    if len(results) > 8:
        print(f"    ... and {len(results) - 8} more")

    path = _save_csv(results)
    print(f"\n  Saved to {path}")
