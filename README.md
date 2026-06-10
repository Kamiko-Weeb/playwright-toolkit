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

### 7. Virus Scanner (`modules/scanner.py`)
A real, working file scanner with four detection layers (cheapest → most expensive):

1. **Hash signatures** — SHA-256/MD5 of each file is compared against a known-bad
   hash database (`config/signatures.json`).
2. **Pattern signatures** — the file body is scanned for documented byte/regex
   indicators (embedded PE headers, `eval(base64_decode(...))`, `curl … | bash`
   droppers, encoded PowerShell, etc.).
3. **Entropy heuristic** — Shannon entropy ≥ 7.2 bits/byte on a risky file type
   (`.exe`, `.dll`, `.ps1`, `.js` …) flags likely packed/encrypted payloads.
4. **YARA rules** *(optional)* — if `yara-python` is installed, every `*.yar`
   file in `rules/` becomes an extra detection layer. YARA is the format most
   real threat-intel feeds ship in, so you can drop in community rules. A sample
   `rules/example.yar` is included. Skipped cleanly when the library is absent.
5. **VirusTotal lookup** *(optional)* — if `VT_API_KEY` is set in `.env`, file
   hashes are checked against VirusTotal's reputation API. Works fully offline
   without a key.

**File-type analysis** — every file's true type is read from its magic bytes, so
**extension spoofing** is caught: a `statement.pdf` that's actually a Windows
executable is flagged as malicious regardless of its name.

**Archive inspection** — `.zip`, `.jar` and `.tar(.gz)` files are opened in
memory and each member is scanned individually, so malware hidden inside an
archive is caught even though on-disk scanning would never see it. Nested
archives (a zip inside a zip) are scanned **recursively** up to a depth limit.
Extraction is bomb-guarded: oversized members, an over-budget total, or
excessive nesting are flagged as suspicious instead of being expanded.

Detected files can be copied into an isolated quarantine folder. **Nothing is
ever executed** — files are only read, hashed and pattern-matched.

**Prove it works:** at the prompt, choose *generate EICAR test file*. EICAR is the
industry-standard harmless 68-byte string every antivirus is built to detect — the
scanner flags it by both hash and pattern, so you can verify detection without
touching real malware.

Prompts for: whether to drop an EICAR sample, path to scan (file or folder),
whether to use VirusTotal, and whether to quarantine hits.
Saves a CSV + JSON report. Extend detection by editing `config/signatures.json`.

**Non-interactive CLI** (no Playwright needed, scriptable, CI-friendly):
```bash
python main.py scan ~/Downloads               # scan a folder
python main.py scan suspect.exe --quarantine   # scan + isolate hits
python main.py scan ~/Downloads --vt           # also query VirusTotal
```
Exit code is `1` when anything malicious is found, `0` when clean, `2` on a bad
path — so you can wire it into scripts or a CI job.

**Evaluation harness** (`modules/evaluate.py`, menu option 8):
```bash
python main.py eval
```
Builds a labeled corpus of known-bad and known-good files, scans it, and reports
a confusion matrix with **precision, recall, accuracy and F1** — the honest way
to quantify a detector. All samples are harmless (EICAR + benign heuristic
triggers). Great material for a project writeup, and it demonstrates the
false-positive control (a high-entropy file with a safe extension stays clean).

**Tests:**
```bash
python -m unittest discover -s tests -v
```
`tests/test_scanner.py` covers every detection layer, the directory walk,
quarantine, report writing and the CLI exit codes — all using temp dirs and the
harmless EICAR string, no real malware.

---

## Output

| Folder | Contents |
|---|---|
| `output/csv/` | Scraper results, scan reports |
| `output/screenshots/` | Monitor captures |
| `output/logs/` | Crawler reports, scan JSON |
| `output/quarantine/` | Isolated copies of flagged files |

All output is gitignored.

## Notes

- `slow_mo` in each module adds a delay between actions — lower it to speed up, raise it to slow down.
- `.env` is gitignored — never commit credentials.
- Tested on M1 Mac with Python 3.11+.
