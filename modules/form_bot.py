import time
from playwright.sync_api import sync_playwright
from config.settings import LOGIN_URL, LOGIN_USERNAME, LOGIN_PASSWORD

DEMO_URL = "https://practicetestautomation.com/practice-test-login/"
DEMO_USER = "student"
DEMO_PASS = "Password123"

USERNAME_SELECTORS = [
    "#username",
    "input[name='username']",
    "input[type='email']",
    "input[name='email']",
    "#email",
]
PASSWORD_SELECTORS = [
    "#password",
    "input[name='password']",
    "input[type='password']",
]
SUBMIT_SELECTORS = [
    "#submit",
    "button[type='submit']",
    "input[type='submit']",
    "button:has-text('Log in')",
    "button:has-text('Login')",
    "button:has-text('Sign in')",
]


def hover_fill(page, selectors: list, text: str) -> bool:
    for sel in selectors:
        loc = page.locator(sel)
        if loc.count() > 0:
            loc.scroll_into_view_if_needed()
            loc.hover()
            time.sleep(0.3)
            loc.fill(text)
            return True
    return False


def hover_click(page, selectors: list) -> bool:
    for sel in selectors:
        loc = page.locator(sel)
        if loc.count() > 0:
            loc.scroll_into_view_if_needed()
            loc.hover()
            time.sleep(0.4)
            loc.click()
            return True
    return False


def run():
    url = LOGIN_URL or DEMO_URL
    username = LOGIN_USERNAME or DEMO_USER
    password = LOGIN_PASSWORD or DEMO_PASS

    if not LOGIN_URL:
        print("\n  No .env credentials found — using demo site.")
        print(f"  Site     : {url}")
        print(f"  Username : {username}")

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False, slow_mo=500)
        page = browser.new_page(viewport={"width": 1280, "height": 800})

        print(f"\n  Opening login page...")
        page.goto(url)
        page.wait_for_load_state("networkidle")

        print("  Filling username field...")
        if not hover_fill(page, USERNAME_SELECTORS, username):
            print("  Could not find username field.")

        print("  Filling password field...")
        if not hover_fill(page, PASSWORD_SELECTORS, password):
            print("  Could not find password field.")

        print("  Clicking submit...")
        if not hover_click(page, SUBMIT_SELECTORS):
            print("  Could not find submit button.")

        page.wait_for_load_state("networkidle")

        current_url = page.url
        page_title = page.title()

        # Success detection
        if not LOGIN_URL:
            success = "logged-in" in current_url or "successfully" in current_url
        else:
            success = current_url != url and "login" not in current_url.lower()

        if success:
            print(f"\n  Login successful!")
            print(f"  Page  : {page_title}")
            print(f"  URL   : {current_url}")
        else:
            print(f"\n  Login may have failed or requires 2FA.")
            print(f"  URL   : {current_url}")

        time.sleep(5)
        browser.close()
