import csv
import random
import time
from datetime import datetime
from playwright.sync_api import sync_playwright
from config.settings import CSV_DIR
from modules.utils import new_context, move_to, smart_click, delay, parse_price

# ndl=1 tells Steam not to filter by display language — required for full specials list
DEFAULT_URL = "https://store.steampowered.com/search/?specials=1&ndl=1"

# Maps user's lowercase input → the display name Steam shows in its tag sidebar.
# Steam's sidebar search is case-insensitive but matching the exact label is safest.
TAG_DISPLAY_NAMES: dict[str, str] = {
    # Multiplayer / social
    "multiplayer":           "Multiplayer",
    "singleplayer":          "Singleplayer",
    "co-op":                 "Co-op",
    "coop":                  "Co-op",
    "pvp":                   "PvP",
    "local multiplayer":     "Local Multiplayer",
    "online co-op":          "Online Co-Op",
    "massively multiplayer": "Massively Multiplayer",
    "mmo":                   "Massively Multiplayer",
    # Genre
    "action":                "Action",
    "adventure":             "Adventure",
    "rpg":                   "RPG",
    "simulation":            "Simulation",
    "sports":                "Sports",
    "racing":                "Racing",
    "horror":                "Horror",
    "puzzle":                "Puzzle",
    "platformer":            "Platformer",
    "fighting":              "Fighting",
    "indie":                 "Indie",
    "casual":                "Casual",
    "strategy":              "Strategy",
    # Sub-genre / play style
    "fps":                   "FPS",
    "shooter":               "Shooter",
    "open world":            "Open World",
    "openworld":             "Open World",
    "survival":              "Survival",
    "roguelike":             "Roguelike",
    "roguelite":             "Roguelite",
    "sandbox":               "Sandbox",
    "battle royale":         "Battle Royale",
    "br":                    "Battle Royale",
    "tower defense":         "Tower Defense",
    "turn-based":            "Turn-Based",
    "turn based":            "Turn-Based",
    "rts":                   "RTS",
    "card game":             "Card Game",
    "cards":                 "Card Game",
    "stealth":               "Stealth",
    "metroidvania":          "Metroidvania",
    # Theme / aesthetic
    "anime":                 "Anime",
    "cyberpunk":             "Cyberpunk",
    "fantasy":               "Fantasy",
    "sci-fi":                "Sci-fi",
    "scifi":                 "Sci-fi",
    "pixel art":             "Pixel Art",
    "2d":                    "2D",
    "3d":                    "3D",
    "visual novel":          "Visual Novel",
    "vn":                    "Visual Novel",
    "atmospheric":           "Atmospheric",
    "story rich":            "Story Rich",
    "early access":          "Early Access",
}


def _parse_tag_input(raw: str) -> list[str]:
    """Convert comma-separated user input into a deduplicated list of Steam display names."""
    tokens  = [t.strip().lower() for t in raw.split(",") if t.strip()]
    result:  list[str] = []
    unknown: list[str] = []
    seen:    set[str]  = set()

    for token in tokens:
        if token in TAG_DISPLAY_NAMES:
            display = TAG_DISPLAY_NAMES[token]
            if display not in seen:
                result.append(display)
                seen.add(display)
        else:
            unknown.append(token)

    if unknown:
        print(f"  Unrecognized tag(s), skipped : {', '.join(unknown)}")
        print(f"  Supported: {', '.join(sorted(TAG_DISPLAY_NAMES))}\n")

    return result


def _apply_tag_via_sidebar(page, display_name: str) -> bool:
    """
    Interactively apply one tag via Steam's 'Narrow by Tag' sidebar.
    Prints a step-by-step trace so failures are immediately visible.
    Returns True if the tag was successfully clicked.
    """
    # ── 1. Scroll the sidebar into view ──────────────────────────────
    print(f"    Scrolling sidebar into view...")
    page.mouse.wheel(0, 500)
    delay(0.5, 0.9)

    # ── 2. Find the tag filter container ─────────────────────────────
    print(f"    Looking for tag filter container...", end=" ", flush=True)
    container = None
    container_sel = None
    for sel in ["#TagFilter_Container", "[id*='TagFilter']", "div.tag_filter_container"]:
        loc = page.locator(sel)
        if loc.count() > 0:
            container    = loc.first
            container_sel = sel
            break

    if container is None:
        print("NOT FOUND")
        # Dump every id= in the page so we can see what's actually there
        ids = page.eval_on_selector_all("[id]", "els => els.map(e => e.id).filter(Boolean)")
        sidebar_ids = [i for i in ids if any(k in i.lower() for k in ("tag", "filter", "narrow"))]
        print(f"    Tag-related IDs on page: {sidebar_ids or '(none)'}")
        return False
    print(f"found  →  {container_sel}")

    container.scroll_into_view_if_needed()
    delay(0.3, 0.5)

    # ── 3. Find the text input ────────────────────────────────────────
    print(f"    Looking for tag input...", end=" ", flush=True)
    tag_input   = None
    input_sel_used = None
    for sel in ["input[type='text']", "input:not([type='hidden'])", "input"]:
        loc = container.locator(sel)
        if loc.count() > 0:
            tag_input     = loc.first
            input_sel_used = sel
            break

    if tag_input is None:
        print("NOT FOUND")
        print(f"    Container inner HTML (first 400 chars): {container.inner_html()[:400]}")
        return False
    print(f"found  →  {input_sel_used}")

    # ── 4. Wait for input to be visible and enabled ───────────────────
    print(f"    Waiting for input to be interactable...", end=" ", flush=True)
    try:
        tag_input.wait_for(state="visible", timeout=5000)
        print("ready")
    except Exception as e:
        print(f"TIMEOUT — {e}")
        return False

    # ── 5. Type the display name ──────────────────────────────────────
    print(f"    Typing '{display_name}'...")
    move_to(page, tag_input)
    delay(0.2, 0.4)
    tag_input.click()
    tag_input.fill("")
    delay(0.15, 0.25)
    for ch in display_name:
        tag_input.type(ch, delay=random.randint(55, 120))

    # ── 6. Poll for suggestion items (up to 5 s) ─────────────────────
    print(f"    Waiting for suggestion items (up to 5 s)...", end=" ", flush=True)
    suggestion_el  = None
    deadline       = 5.0
    poll_start     = time.time()
    suggestion_sels = [
        f"a:has-text('{display_name}')",
        f"label:has-text('{display_name}')",
        f"div:has-text('{display_name}')",
        f"span:has-text('{display_name}')",
    ]

    while time.time() - poll_start < deadline:
        for sel in suggestion_sels:
            try:
                el = container.locator(sel).first
                if el.count() > 0 and el.is_visible(timeout=300):
                    suggestion_el = el
                    break
            except Exception:
                pass
        if suggestion_el is not None:
            break
        time.sleep(0.3)

    if suggestion_el is None:
        elapsed = f"{time.time() - poll_start:.1f}s"
        print(f"NONE appeared after {elapsed}")
        # Dump container text so we know what Steam actually rendered
        try:
            visible = container.inner_text().strip().replace("\n", " | ")[:300]
            print(f"    Container text: {visible}")
        except Exception:
            pass
        return False

    elapsed = f"{time.time() - poll_start:.1f}s"
    print(f"found  ({elapsed})")

    # ── 7. Click the suggestion ───────────────────────────────────────
    print(f"    Clicking '{display_name}' tag...", end=" ", flush=True)
    try:
        move_to(page, suggestion_el)
        delay(0.15, 0.35)
        suggestion_el.click()
        print("done")
    except Exception as e:
        print(f"FAILED — {e}")
        return False

    # ── 8. Wait for results pane to update ───────────────────────────
    try:
        page.wait_for_load_state("networkidle", timeout=8000)
    except Exception:
        delay(1.5, 2.5)

    # Clear input ready for next tag
    try:
        tag_input.fill("")
    except Exception:
        pass

    return True


def _print_result_count(page) -> None:
    """Print how many results Steam is showing before we start scraping."""
    for sel in [".search_results_count", "#search_results_header"]:
        loc = page.locator(sel)
        if loc.count() > 0:
            try:
                print(f"  Steam result count: {loc.first.text_content().strip()}")
                return
            except Exception:
                pass
    # Fallback: count visible rows
    count = page.locator("a.search_result_row").count()
    print(f"  Visible result rows: {count}")


def _has_results(page) -> bool:
    """Return True if the search results pane contains at least one game row."""
    try:
        page.wait_for_selector("a.search_result_row", timeout=8000)
        return page.locator("a.search_result_row").count() > 0
    except Exception:
        return False


# ── Internal scrape helpers ───────────────────────────────────────────────────

def _dismiss_dialogs(page) -> None:
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
                "name":           name,
                "current_price":  current,
                "original_price": original,
                "discount_pct":   discount,
                "tags":           "",   # stamped by run()
                "url":            href,
            })
        except Exception as e:
            print(f"  Row {i} skipped: {e}")

    return results


def _scrape_app(page, url: str) -> list:
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


# ── Price monitor helper ──────────────────────────────────────────────────────

def get_price(url: str) -> dict | None:
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

    tag_raw = input(
        "  Filter by tags (e.g. fps, rpg, multiplayer) or Enter to skip: "
    ).strip()

    # Resolve user's input into Steam display names
    tag_display_names: list[str] = []
    active_tags = ""

    if tag_raw:
        if "/app/" in url:
            active_tags = tag_raw
            print("  Note: tag filtering only works on search pages — tags recorded in CSV only.")
        else:
            tag_display_names = _parse_tag_input(tag_raw)

    with sync_playwright() as p:
        browser, ctx = new_context(p)
        page = ctx.new_page()

        print(f"\n  Navigating to {url} ...")
        page.goto(url)
        page.wait_for_load_state("networkidle")
        _dismiss_dialogs(page)

        # Apply tags one at a time via the sidebar
        if tag_display_names:
            print(f"\n  Applying {len(tag_display_names)} tag filter(s) via sidebar...")
            applied: list[str] = []
            for name in tag_display_names:
                print(f"    → {name} ...", end=" ", flush=True)
                ok = _apply_tag_via_sidebar(page, name)
                if ok:
                    applied.append(name)
                    print("done")
                else:
                    print("skipped")
            active_tags = ", ".join(applied)

            # Verify results exist before committing to a full scrape
            if applied:
                print(f"\n  Checking results for: {active_tags}")
                if not _has_results(page):
                    print("  0 results after applying tags — try a broader filter.")
                    browser.close()
                    return
                _print_result_count(page)
                print("  Results confirmed — starting scrape...")

        if "/app/" in url:
            results = _scrape_app(page, url)
        else:
            results = _scrape_search(page)

        browser.close()

    if not results:
        print("  Nothing scraped.")
        return

    for r in results:
        r["tags"] = active_tags

    print(f"\n  {len(results)} game(s):")
    for r in results[:8]:
        print(f"    {r['name']:<42} {r['current_price']:<12} ({r['discount_pct']})")
    if len(results) > 8:
        print(f"    ... and {len(results) - 8} more")

    path = _save_csv(results)
    print(f"\n  Saved to {path}")
