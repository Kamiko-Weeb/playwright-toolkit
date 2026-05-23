import sys
from modules import scraper, form_bot, monitor, crawler, steam_scraper, amazon_scraper

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
║  0.  Exit                                              ║
╚════════════════════════════════════════════════════════╝"""

MODULES = {
    "1": ("Scraper",          scraper.run),
    "2": ("Form Bot",         form_bot.run),
    "3": ("Monitor",          monitor.run),
    "4": ("Crawler",          crawler.run),
    "5": ("Steam Scraper",    steam_scraper.run),
    "6": ("Amazon Scraper",   amazon_scraper.run),
}


def main():
    while True:
        print(MENU)
        choice = input("  Pick a module: ").strip()

        if choice == "0":
            print("\n  Bye.\n")
            sys.exit(0)

        if choice not in MODULES:
            print("  Invalid — try again.")
            continue

        name, fn = MODULES[choice]
        print(f"\n  Running {name}...\n" + "─" * 56)
        try:
            fn()
        except KeyboardInterrupt:
            print(f"\n  {name} interrupted.")
        print("─" * 56)


if __name__ == "__main__":
    main()
