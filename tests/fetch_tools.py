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
    request = urllib.request.Request(url, headers={'User-Agent': 'Xray-Script-config-tests'})
    with urllib.request.urlopen(request, timeout=90) as response:
        return response.read()

def unpack(data, names, target):
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        for name in names:
            path = target / name
            path.write_bytes(archive.read(name))
            path.chmod(0o755)

latest = json.loads(get('https://api.github.com/repos/XTLS/Xray-core/releases/latest'))['tag_name']
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

release = json.loads(get('https://api.github.com/repos/MetaCubeX/mihomo/releases/latest'))
prefix = 'mihomo-windows-amd64-compatible-' if windows else 'mihomo-linux-amd64-compatible-'
asset = next(a for a in release['assets'] if a['name'].startswith(prefix) and a['name'].endswith(('.gz', '.zip')))
target = root / ('mihomo.exe' if windows else 'mihomo')
if not target.exists():
    data = get(asset['browser_download_url'])
    if asset.get('digest'):
        assert asset['digest'] == 'sha256:' + hashlib.sha256(data).hexdigest()
    if asset['name'].endswith('.zip'):
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            name = next(n for n in archive.namelist() if n.endswith('.exe'))
            target.write_bytes(archive.read(name))
    else:
        target.write_bytes(gzip.decompress(data))
    target.chmod(0o755)
    print('Official Mihomo:', release['tag_name'], flush=True)
