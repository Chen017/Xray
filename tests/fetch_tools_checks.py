"""Offline checks for latest-stable refresh, stale-cache safety and fixed Xray."""
import gzip
import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import fetch_tools


class RuntimePolicyChecks(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name)
        self.binary = self.root / 'mihomo'
        self.binary.write_text('v1.19.31')
        self.payload = b'v1.19.32'
        self.asset = gzip.compress(self.payload)
        self.release = {
            'tag_name': 'v1.19.32', 'draft': False, 'prerelease': False,
            'assets': [{
                'name': 'mihomo-linux-amd64-compatible-v1.19.32.gz',
                'browser_download_url': 'https://github.com/MetaCubeX/mihomo/test.gz',
                'digest': 'sha256:' + hashlib.sha256(self.asset).hexdigest(),
            }],
        }
        self.requests = []

    def get(self, url):
        self.requests.append(url)
        return json.dumps(self.release).encode() if url.endswith('/latest') else self.asset

    @staticmethod
    def version(binary, core):
        return binary.read_text() if binary.exists() else None

    def test_stale_mihomo_is_replaced_and_next_run_still_checks_latest(self):
        with patch.object(fetch_tools, 'get', self.get), patch.object(fetch_tools, 'version_of', self.version):
            self.assertEqual(fetch_tools.fetch_mihomo(self.root, False)[1], 'v1.19.32')
            self.assertEqual(self.binary.read_bytes(), self.payload)
            self.assertEqual(fetch_tools.fetch_mihomo(self.root, False)[1], 'v1.19.32')
        self.assertEqual(sum(url.endswith('/latest') for url in self.requests), 2)
        self.assertEqual(len(self.requests), 3)

    def test_failed_latest_lookup_does_not_silently_use_cached_mihomo(self):
        with patch.object(fetch_tools, 'get', side_effect=OSError('offline')):
            with self.assertRaises(OSError):
                fetch_tools.fetch_mihomo(self.root, False)
        self.assertEqual(self.binary.read_text(), 'v1.19.31')

    def test_prerelease_and_bad_digest_preserve_existing_runtime(self):
        for failure in ('prerelease', 'digest'):
            with self.subTest(failure=failure):
                self.release['prerelease'] = failure == 'prerelease'
                if failure == 'digest':
                    self.release['assets'][0]['digest'] = 'sha256:' + '0' * 64
                with patch.object(fetch_tools, 'get', self.get), patch.object(fetch_tools, 'version_of', self.version):
                    with self.assertRaises(RuntimeError):
                        fetch_tools.fetch_mihomo(self.root, False)
                self.assertEqual(self.binary.read_text(), 'v1.19.31')

    def test_xray_cache_is_fixed_without_querying_latest(self):
        target = self.root / 'v26.3.27'
        target.mkdir()
        for name in ('xray', 'geoip.dat', 'geosite.dat'):
            (target / name).write_text('v26.3.27')
        with patch.object(fetch_tools, 'get', side_effect=AssertionError('unexpected request')), patch.object(fetch_tools, 'version_of', self.version):
            binary, tag = fetch_tools.fetch_xray(self.root, False)
        self.assertEqual(tag, 'v26.3.27')
        self.assertEqual(binary.parent.name, 'v26.3.27')


if __name__ == '__main__':
    unittest.main()
