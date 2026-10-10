"""Fetch checksum-verified official Xray releases and an official Mihomo test runtime."""
import gzip
import hashlib
import io
import json
import os
import platform
import re
import urllib.request
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1] / '.test-tools'
root.mkdir(exist_ok=True)
windows = platform.system() == 'Windows'

def get(url):
    headers = {'User-Agent': 'Xray-Script-config-tests'}
    token = os.environ.get('GITHUB_TOKEN') or os.environ.get('GH_TOKEN')
    if token and 'api.github.com' in url:
        headers['Authorization'] = f'Bearer {token}'
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=90) as response:
        return response.read()

def unpack(data, names, target):
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for name in names:
            path = target / name
            path.write_bytes(archive.read(name))
            path.chmod(0o755)

try:
    latest = json.loads(get('https://api.github.com/repos/XTLS/Xray-core/releases/latest'))['tag_name']
except Exception as exc:
    print(f'Warning: failed to query latest Xray release ({exc}); falling back to pinned version', flush=True)
    latest = 'v26.3.27'

versions = ['v26.3.27', latest]
for tag in dict.fromkeys(versions):
    target = root / tag
    target.mkdir(exist_ok=True)
    binary = 'xray.exe' if windows else 'xray'
    if (target / binary).exists():
        continue
    asset = 'Xray-windows-64.zip' if windows else 'Xray-linux-64.zip'
    url = f'https://github.com/XTLS/Xray-core/releases/download/{tag}/{asset}'
    digest = get(url + '.dgst').decode()
    expected = re.findall(r'(?im)^.*SHA(?:2-)?256.*?([0-9a-f]{64})\s*$', digest)
    data = get(url)
    assert expected and hashlib.sha256(data).hexdigest() == expected[0].lower()
    unpack(data, [binary, 'geoip.dat', 'geosite.dat'], target)
    print('Verified Xray:', tag, flush=True)

target = root / ('mihomo.exe' if windows else 'mihomo')
if not target.exists():
    try:
        release = json.loads(get('https://api.github.com/repos/MetaCubeX/mihomo/releases/latest'))
        prefix = 'mihomo-windows-amd64-compatible-' if windows else 'mihomo-linux-amd64-compatible-'
        asset = next(a for a in release['assets'] if a['name'].startswith(prefix) and a['name'].endswith(('.gz', '.zip')))
        download_url = asset['browser_download_url']
        digest = asset.get('digest')
        tag_name = release['tag_name']
    except Exception as exc:
        print(f'Warning: failed to query latest Mihomo release ({exc}); falling back to pinned version', flush=True)
        tag_name = 'v1.19.32'
        ext = 'zip' if windows else 'gz'
        asset_name = f'mihomo-{"windows" if windows else "linux"}-amd64-compatible-{tag_name}.{ext}'
        download_url = f'https://github.com/MetaCubeX/mihomo/releases/download/{tag_name}/{asset_name}'
        digest = None

    data = get(download_url)
    if digest:
        assert digest == 'sha256:' + hashlib.sha256(data).hexdigest()
    if download_url.endswith('.zip'):
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            name = next(n for n in archive.namelist() if n.endswith('.exe'))
            target.write_bytes(archive.read(name))
    else:
        target.write_bytes(gzip.decompress(data))
    target.chmod(0o755)
    print('Official Mihomo:', tag_name, flush=True)
