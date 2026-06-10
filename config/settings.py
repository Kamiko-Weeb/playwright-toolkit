from pathlib import Path
from dotenv import load_dotenv
import os

load_dotenv()

BASE_DIR = Path(__file__).parent.parent
OUTPUT_DIR = BASE_DIR / "output"
SCREENSHOTS_DIR = OUTPUT_DIR / "screenshots"
CSV_DIR = OUTPUT_DIR / "csv"
LOGS_DIR = OUTPUT_DIR / "logs"
DATA_DIR = OUTPUT_DIR / "data"
QUARANTINE_DIR = OUTPUT_DIR / "quarantine"

for _dir in [SCREENSHOTS_DIR, CSV_DIR, LOGS_DIR, DATA_DIR, QUARANTINE_DIR]:
    _dir.mkdir(parents=True, exist_ok=True)

WATCHLIST_FILE = DATA_DIR / "watchlist.json"
SIGNATURES_FILE = BASE_DIR / "config" / "signatures.json"

LOGIN_URL = os.getenv("LOGIN_URL", "")
LOGIN_USERNAME = os.getenv("LOGIN_USERNAME", "")
LOGIN_PASSWORD = os.getenv("LOGIN_PASSWORD", "")

# Optional: free key from https://www.virustotal.com/gui/my-apikey enables
# online hash reputation lookups. Scanner works fully offline without it.
VT_API_KEY = os.getenv("VT_API_KEY", "")
