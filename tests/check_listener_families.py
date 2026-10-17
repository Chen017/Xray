#!/usr/bin/env python3
"""Linux integration: run real Xray and reject IPv4 through the IPv6 listener."""
import copy
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time


def connect(host, port):
    try:
        with socket.create_connection((host, port), timeout=0.2):
            return True
    except OSError:
        return False


def main():
    binary, source = sys.argv[1:]
    config = json.loads(Path(source).read_text())
    inbounds = [copy.deepcopy(n) for n in config['inbounds'] if n['streamSettings'].get('security') == 'reality']
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        port = probe.getsockname()[1]
    for node in inbounds:
        node['port'] = port
        if node['tag'].endswith('_v4'):
            node['listen'] = '127.0.0.1'
        node['settings'].pop('fallbacks', None)
    with tempfile.TemporaryDirectory(prefix='xray-listener-test-') as directory:
        root = Path(directory)
        path = root / 'config.json'
        path.write_text(json.dumps({'log': {'loglevel': 'none'}, 'inbounds': inbounds,
                                    'outbounds': [{'protocol': 'freedom'}]}))
        with (root / 'core.log').open('wb') as log:
            child = subprocess.Popen([binary, 'run', '-config', str(path)], stdout=log, stderr=subprocess.STDOUT)
            try:
                for _ in range(100):
                    if connect('127.0.0.1', port) and connect('::1', port):
                        break
                    if child.poll() is not None:
                        raise RuntimeError('Xray listener startup failed')
                    time.sleep(0.05)
                else:
                    raise RuntimeError('IPv4/IPv6 listeners did not start')
                inodes = set()
                for entry in Path(f'/proc/{child.pid}/fd').iterdir():
                    try:
                        inodes.add(os.readlink(entry))
                    except FileNotFoundError:
                        pass
                families = []
                for family, table in [('v4', '/proc/net/tcp'), ('v6', '/proc/net/tcp6')]:
                    for line in Path(table).read_text().splitlines()[1:]:
                        fields = line.split()
                        if int(fields[1].split(':')[1], 16) == port and fields[3] == '0A' and f'socket:[{fields[9]}]' in inodes:
                            families.append(family)
                if sorted(families) != ['v4', 'v6']:
                    raise RuntimeError(f'Expected separate families, got {families}')
                if connect('127.0.0.2', port):
                    raise RuntimeError('IPv6 wildcard incorrectly accepts IPv4 traffic')
                print('PASS: real Xray has separate IPv4/IPv6 listeners; IPv6 does not accept IPv4')
            finally:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()


if __name__ == '__main__':
    main()
