import time
from datetime import datetime
from collections import deque
from urllib.parse import urlparse
from playwright.sync_api import sync_playwright
from config.settings import LOGS_DIR

DEFAULT_URL = "https://en.wikipedia.org/wiki/Web_scraping"
DEFAULT_MAX_PAGES = 8
DEFAULT_MAX_DEPTH = 2


def same_domain(base: str, link: str) -> bool:
    base_host = urlparse(base).netloc
    link_host = urlparse(link).netloc
    return link_host == "" or link_host == base_host


def hover_links(page, count: int = 4):
    """Move cursor over the first few visible links so you can see activity."""
    links_loc = page.locator("a[href]")
    total = links_loc.count()
    for i in range(min(count, total)):
        try:
            lnk = links_loc.nth(i)
            lnk.scroll_into_view_if_needed()
            lnk.hover()
            time.sleep(0.2)
        except Exception:
            pass


def crawl(start_url: str, max_pages: int, max_depth: int) -> list:
    results = []
    visited = set()
    queue = deque([(start_url, 0)])

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False, slow_mo=300)
        page = browser.new_page(viewport={"width": 1280, "height": 800})

        while queue and len(results) < max_pages:
            url, depth = queue.popleft()

            if url in visited or depth > max_depth:
                continue
            visited.add(url)

            label = f"[{len(results) + 1}/{max_pages}] depth={depth}"
            print(f"  {label}  {url[:70]}")

            try:
                page.goto(url, timeout=15000)
                page.wait_for_load_state("domcontentloaded", timeout=10000)

                # Visibly hover over links before collecting them
                hover_links(page, count=4)

                title = page.title()
                raw_links = page.eval_on_selector_all(
                    "a[href]",
                    "els => els.map(e => e.href).filter(h => h.startsWith('http'))",
                )

                internal = [l for l in raw_links if same_domain(start_url, l)]

                results.append(
                    {
                        "url": url,
                        "title": title,
                        "depth": depth,
                        "internal_links": len(internal),
                    }
                )

                if depth < max_depth:
                    for link in internal[:5]:
                        if link not in visited:
                            queue.append((link, depth + 1))

                time.sleep(0.4)

            except Exception as e:
                print(f"    Error: {e}")
                results.append(
                    {"url": url, "title": "ERROR", "depth": depth, "internal_links": 0}
                )

        browser.close()

    return results


def save_log(results: list, start_url: str) -> str:
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filepath = LOGS_DIR / f"crawl_{timestamp}.log"

    with open(filepath, "w", encoding="utf-8") as f:
        f.write(f"Crawl report\n")
        f.write(f"Started : {datetime.now().isoformat()}\n")
        f.write(f"Origin  : {start_url}\n")
        f.write(f"Pages   : {len(results)}\n")
        f.write("=" * 60 + "\n\n")

        for i, r in enumerate(results, 1):
            f.write(f"[{i}] {r['url']}\n")
            f.write(f"    Title          : {r['title']}\n")
            f.write(f"    Depth          : {r['depth']}\n")
            f.write(f"    Internal links : {r['internal_links']}\n\n")

    return str(filepath)


def run():
    url = input(f"\n  Start URL [{DEFAULT_URL}]: ").strip() or DEFAULT_URL

    try:
        max_pages = int(
            input(f"  Max pages [{DEFAULT_MAX_PAGES}]: ").strip() or DEFAULT_MAX_PAGES
        )
        max_depth = int(
            input(f"  Max depth [{DEFAULT_MAX_DEPTH}]: ").strip() or DEFAULT_MAX_DEPTH
        )
    except ValueError:
        max_pages, max_depth = DEFAULT_MAX_PAGES, DEFAULT_MAX_DEPTH

    print(f"\n  Starting crawl...")
    results = crawl(url, max_pages, max_depth)

    print(f"\n  Crawled {len(results)} page(s).")
    path = save_log(results, url)
    print(f"  Log saved to {path}")
