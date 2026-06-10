import sys

MENU = """
╔════════════════════════════════════════════════════════╗
║           Playwright Automation Toolkit                ║
╠════════════════════════════════════════════════════════╣
║  1.  Scraper   — extract text, prices & links          ║
║  2.  Form Bot  — login with .env credentials           ║
║  3.  Monitor   — screenshots & price watchlist         ║
║  4.  Crawler   — multi-page link crawler               ║
║  5.  Steam     — scrape game prices & discounts        ║
║  6.  Amazon.ca — scrape product prices & stock         ║
║  7.  Scanner   — signature & heuristic virus scanner   ║
║  0.  Exit                                              ║
╚════════════════════════════════════════════════════════╝"""

def load_modules():
    # Imported lazily so the `scan` shortcut doesn't require Playwright.
    from modules import (
        scraper, form_bot, monitor, crawler,
        steam_scraper, amazon_scraper, scanner,
    )
    return {
        "1": ("Scraper",          scraper.run),
        "2": ("Form Bot",         form_bot.run),
        "3": ("Monitor",          monitor.run),
        "4": ("Crawler",          crawler.run),
        "5": ("Steam Scraper",    steam_scraper.run),
        "6": ("Amazon Scraper",   amazon_scraper.run),
        "7": ("Virus Scanner",    scanner.run),
    }


def main():
    modules = load_modules()
    while True:
        print(MENU)
        choice = input("  Pick a module: ").strip()

        if choice == "0":
            print("\n  Bye.\n")
            sys.exit(0)

        if choice not in modules:
            print("  Invalid — try again.")
            continue

        name, fn = modules[choice]
        print(f"\n  Running {name}...\n" + "─" * 56)
        try:
            fn()
        except KeyboardInterrupt:
            print(f"\n  {name} interrupted.")
        print("─" * 56)


if __name__ == "__main__":
    # Non-interactive shortcut: `python main.py scan <path> [--quarantine] [--vt]`
    if len(sys.argv) > 1 and sys.argv[1] == "scan":
        from modules import scanner
        sys.exit(scanner.cli(sys.argv[2:]))
    main()
