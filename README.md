# Playwright Automation Toolkit

A modular browser automation toolkit built with Python + Playwright. Every module opens a real visible browser window and moves the cursor so you can watch exactly what it's doing.

## Setup

```bash
cd playwright-toolkit
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
playwright install chromium
```

## Run

```bash
source .venv/bin/activate
python main.py
```

You'll get an interactive menu to pick a module.

---

## Modules

### 1. Scraper (`modules/scraper.py`)
Visits a URL and extracts:
- Page title
- All headings (h1, h2, h3)
- Prices (elements containing £, $, €)
- All links (up to 100)

Saves everything to a timestamped CSV in `output/csv/`.
Default target: `https://books.toscrape.com` (a scraping sandbox with real prices).

---

### 2. Form Bot (`modules/form_bot.py`)
Automates a login form. Hover-fills each field and clicks submit, then reports success or failure.

**Demo mode** (default): uses `https://practicetestautomation.com/practice-test-login/` with credentials `student` / `Password123` — no setup needed.

**Custom site**: fill in your credentials in `.env`:
```
LOGIN_URL=https://yoursite.com/login
LOGIN_USERNAME=you@example.com
LOGIN_PASSWORD=yourpassword
```

---

### 3. Monitor (`modules/monitor.py`)
Takes screenshots of a URL on a schedule. Before each capture, the cursor sweeps down the page so you can see it's live.

Saves PNG files with timestamps to `output/screenshots/`.
Prompts for: URL, interval (seconds), number of shots.

---

### 4. Crawler (`modules/crawler.py`)
Crawls a site breadth-first, following only internal links. On each page, hovers over the first few links so you can see it scanning.

Collects per page: URL, title, depth, internal link count.
Saves a full report to `output/logs/`.
Prompts for: start URL, max pages, max depth.

---

## Output

| Folder | Contents |
|---|---|
| `output/csv/` | Scraper results |
| `output/screenshots/` | Monitor captures |
| `output/logs/` | Crawler reports |

All output is gitignored.

## Notes

- `slow_mo` in each module adds a delay between actions — lower it to speed up, raise it to slow down.
- `.env` is gitignored — never commit credentials.
- Tested on M1 Mac with Python 3.11+.
