import sys
from modules import scraper, form_bot, monitor, crawler

MENU = """
╔══════════════════════════════════════════════╗
║       Playwright Automation Toolkit          ║
╠══════════════════════════════════════════════╣
║  1.  Scraper   — extract text, prices, links ║
║  2.  Form Bot  — login with .env credentials ║
║  3.  Monitor   — scheduled screenshots       ║
║  4.  Crawler   — multi-page link crawler     ║
║  0.  Exit                                    ║
╚══════════════════════════════════════════════╝"""

MODULES = {
    "1": ("Scraper", scraper.run),
    "2": ("Form Bot", form_bot.run),
    "3": ("Monitor", monitor.run),
    "4": ("Crawler", crawler.run),
}


def main():
    while True:
        print(MENU)
        choice = input("  Pick a module: ").strip()

        if choice == "0":
            print("\n  Bye.\n")
            sys.exit(0)

        if choice not in MODULES:
            print("  Invalid choice — try again.")
            continue

        name, fn = MODULES[choice]
        print(f"\n  Running {name}...\n" + "─" * 48)
        try:
            fn()
        except KeyboardInterrupt:
            print(f"\n  {name} interrupted.")
        print("─" * 48)


if __name__ == "__main__":
    main()
