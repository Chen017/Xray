"""Fetch fixed Xray and latest stable Mihomo; record the exact tested runtimes."""
import datetime
import gzip
import hashlib
import io
import json
import os
import platform
import re
import subprocess
import urllib.request
import zipfile
from pathlib import Path

XRAY_VERSION = 'v26.3.27'


def get(url):
    headers = {'User-Agent': 'Xray-Script-config-tests'}
    token = os.environ.get('GITHUB_TOKEN') or os.environ.get('GH_TOKEN')
    if token and 'api.github.com' in url:
        headers['Authorization'] = f'Bearer {token}'
    request = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(request, timeout=90) as response:
        return response.read()


def version_of(binary, core):
    try:
        result = subprocess.run(
            [str(binary.resolve()), 'version' if core == 'xray' else '-v'],
            check=True, capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return None
    pattern = r'^Xray v?(\d+\.\d+\.\d+)\b' if core == 'xray' else r'\bMihomo.*?\bv?(\d+\.\d+\.\d+)\b'
    match = re.search(pattern, result.stdout)
    return 'v' + match[1] if match else None


def fetch_xray(root, windows):
    target = root / XRAY_VERSION
    target.mkdir(exist_ok=True)
    binary = target / ('xray.exe' if windows else 'xray')
    if version_of(binary, 'xray') != XRAY_VERSION or any(
            not (target / name).is_file() for name in ('geoip.dat', 'geosite.dat')):
        asset = 'Xray-windows-64.zip' if windows else 'Xray-linux-64.zip'
        url = f'https://github.com/XTLS/Xray-core/releases/download/{XRAY_VERSION}/{asset}'
        digest = get(url + '.dgst').decode()
        expected = re.findall(r'(?im)^.*SHA(?:2-)?256.*?([0-9a-f]{64})\s*$', digest)
        data = get(url)
        if not expected or hashlib.sha256(data).hexdigest() != expected[0].lower():
            raise RuntimeError('Xray SHA256 mismatch')
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            for name in (binary.name, 'geoip.dat', 'geosite.dat'):
                path = target / name
                path.write_bytes(archive.read(name))
                path.chmod(0o755)
        if version_of(binary, 'xray') != XRAY_VERSION:
            raise RuntimeError('Xray binary version does not match the fixed version')
    return binary, XRAY_VERSION


def fetch_mihomo(root, windows):
    # Always resolve latest stable, even when a cached runtime is present.
    # Failure is explicit: an old cache must never be reported as latest.
    release = json.loads(get('https://api.github.com/repos/MetaCubeX/mihomo/releases/latest'))
    tag = release['tag_name']
    if release.get('prerelease') is not False or release.get('draft') is not False or not re.fullmatch(r'v\d+\.\d+\.\d+', tag):
        raise RuntimeError('Mihomo latest endpoint did not return a stable release')
    prefix = 'mihomo-windows-amd64-compatible-' if windows else 'mihomo-linux-amd64-compatible-'
    asset = next(a for a in release['assets'] if a['name'].startswith(prefix) and a['name'].endswith(('.gz', '.zip')))
    target = root / ('mihomo.exe' if windows else 'mihomo')
    if version_of(target, 'mihomo') != tag:
        data = get(asset['browser_download_url'])
        digest = asset.get('digest')
        if not digest or digest != 'sha256:' + hashlib.sha256(data).hexdigest():
            raise RuntimeError('Mihomo release asset SHA256 missing or mismatched')
        if asset['name'].endswith('.zip'):
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                name = next(n for n in archive.namelist() if n.endswith('.exe'))
                payload = archive.read(name)
        else:
            payload = gzip.decompress(data)
        candidate = target.with_name(target.stem + '.candidate' + target.suffix)
        try:
            candidate.write_bytes(payload)
            candidate.chmod(0o755)
            if version_of(candidate, 'mihomo') != tag:
                raise RuntimeError('Mihomo binary version does not match latest stable')
            candidate.replace(target)
        finally:
            candidate.unlink(missing_ok=True)
    return target, tag


def main():
    root = Path(__file__).resolve().parents[1] / '.test-tools'
    root.mkdir(exist_ok=True)
    windows = platform.system() == 'Windows'
    runtimes = {}
    for core, fetch in (('xray', fetch_xray), ('mihomo', fetch_mihomo)):
        binary, version = fetch(root, windows)
        runtimes[core] = {
            'version': version,
            'binary': str(binary.relative_to(root)),
            'sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
        }
        print(f'Official {core}: {version} ({binary.name})', flush=True)
    runtimes['checked_at_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    (root / 'runtimes.json').write_text(json.dumps(runtimes, indent=2) + '\n', encoding='utf-8')


if __name__ == '__main__':
    main()
