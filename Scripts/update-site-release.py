"""Bake current Releases metadata into HTML so download links work without JS."""
import html
import json
import re
from pathlib import Path
from urllib.parse import urlsplit

root = Path(__file__).resolve().parent.parent
release = json.loads((root / 'website/release.json').read_text())
assert not release['draft'] and not release['prerelease']
asset = next(a for a in release['assets'] if a['name'].endswith('-macos-arm64.dmg'))
url = urlsplit(asset['browser_download_url'])
assert url.scheme == 'https' and url.netloc == 'github.com'
assert url.path.startswith('/huangzhuangjia/halodock/releases/download/')
page = root / 'website/index.html'
text = page.read_text()
text, count = re.subn(r'(<a\b[^>]*class="[^"]*\bdownload-link\b[^"]*"[^>]*href=")[^"]*(")', lambda m: m[1]+html.escape(asset['browser_download_url'], quote=True)+m[2], text)
assert count == 3, f'Expected 3 download buttons, found {count}'
version = html.escape(release['tag_name'], quote=True)
text = re.sub(r'(<span id="release-version">)[^<]*(</span>)', lambda m: m[1]+version+m[2], text)
text = re.sub(r'(<meta name="halodock-release" content=")[^"]*(">)', lambda m: m[1]+version+m[2], text)
page.write_text(text)
print(f'Updated {count} direct download buttons to {release["tag_name"]}')
