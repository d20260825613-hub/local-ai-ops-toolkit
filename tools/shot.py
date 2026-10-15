import os
import sys

from playwright.sync_api import sync_playwright

url = sys.argv[1] if len(sys.argv) > 1 else 'http://127.0.0.1:3080'
out = sys.argv[2] if len(sys.argv) > 2 else r'D:\ai\tools\gui-shot.png'

with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page(viewport={'width': 1440, 'height': 900})
    page.goto(url, wait_until='networkidle', timeout=60000)
    page.wait_for_timeout(3000)
    page.screenshot(path=out, full_page=False)
    print('title:', page.title())
    print('saved:', out, os.path.getsize(out), 'bytes')
    browser.close()
