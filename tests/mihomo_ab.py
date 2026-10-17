#!/usr/bin/env python3
"""Temporary one-node A/B session through Mihomo's API; restore in finally.

Requires PyYAML. No speedtest website automation or server modifications.
The supplied config must be the effective running config, including UI overlays.
"""
import argparse
import copy
import http.client
import json
from pathlib import Path
import urllib.parse
import urllib.request

import yaml


def load_runtime(text):
    cfg = yaml.safe_load(text)
    raw = yaml.load(text, Loader=yaml.BaseLoader)
    # Short IDs are byte strings. A numeric-only unquoted ID must keep its
    # original spelling, including leading zeroes, during YAML re-emission.
    for node, original in zip(cfg.get('proxies', []), raw.get('proxies', [])):
        pairs = [(node, original)]
        if isinstance(node.get('xhttp-opts', {}).get('download-settings'), dict):
            pairs.append((node['xhttp-opts']['download-settings'], original['xhttp-opts']['download-settings']))
        for current, source in pairs:
            if 'short-id' in source.get('reality-opts', {}):
                current['reality-opts']['short-id'] = source['reality-opts']['short-id']
    return cfg


class Controller:
    def __init__(self, endpoint, secret):
        self.endpoint = endpoint
        self.secret = secret

    def request(self, method, path, body=None):
        data = json.dumps(body, ensure_ascii=False).encode() if body is not None else b''
        headers = {'Authorization': f'Bearer {self.secret}', 'Content-Type': 'application/json'}
        if self.endpoint.startswith('http://127.0.0.1:') or self.endpoint.startswith('http://localhost:'):
            req = urllib.request.Request(self.endpoint.rstrip('/') + path, data=data if method != 'GET' else None,
                                         headers=headers, method=method)
            # Do not route control traffic through an environment proxy.
            opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
            with opener.open(req, timeout=30) as response:
                result = response.read()
        elif self.endpoint.startswith('\\\\.\\pipe\\'):
            with open(self.endpoint, 'r+b', buffering=0) as pipe:
                text = f'{method} {path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n'
                text += ''.join(f'{k}: {v}\r\n' for k, v in headers.items())
                pipe.write((text + f'Content-Length: {len(data)}\r\n\r\n').encode() + data)

                class Socket:
                    def makefile(self, *args, **kwargs):
                        return pipe

                response = http.client.HTTPResponse(Socket())
                response.begin()
                result = response.read()
                if response.status >= 300:
                    raise RuntimeError(f'Mihomo API returned HTTP {response.status}')
        else:
            raise ValueError('Use an existing localhost HTTP controller or Windows named pipe')
        return json.loads(result) if result else None


def variant_config(original, node_name, mode):
    cfg = copy.deepcopy(original)
    matches = [node for node in cfg['proxies'] if node['name'] == node_name]
    if len(matches) != 1 or matches[0].get('type') != 'vless':
        raise ValueError('Select one exact VLESS node name')
    node = matches[0]
    if node.get('network') != 'xhttp':
        raise ValueError('The baseline node must use XHTTP')
    if mode == 'vision':
        node['network'] = 'tcp'
        node['flow'] = 'xtls-rprx-vision'
        node.pop('xhttp-opts')
        node.pop('alpn', None)
    elif mode in ('single', 'stream-one'):
        node['xhttp-opts'].pop('download-settings', None)
        if mode == 'stream-one':
            node['xhttp-opts']['mode'] = mode
    elif mode != 'baseline':
        raise ValueError(mode)
    return cfg


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path)
    parser.add_argument('--controller', required=True, help='Existing localhost URL or Windows pipe')
    parser.add_argument('--node', help='Exact name; no other nodes are edited')
    parser.add_argument('--group', help='One select group used for test traffic')
    parser.add_argument('--variants', default='baseline,vision', help='baseline,vision,single,stream-one')
    parser.add_argument('--state-dir', type=Path, default=Path('.test-tools/mihomo-ab'))
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--restore-only', action='store_true', help='Recover a forcibly interrupted session')
    args = parser.parse_args()
    if args.restore_only:
        original_text = (args.state_dir / 'original.yaml').read_text(encoding='utf-8')
        original = load_runtime(original_text)
        controller = Controller(args.controller, original.get('secret', ''))
        selectors = json.loads((args.state_dir / 'selectors.json').read_text(encoding='utf-8'))
        controller.request('PUT', '/configs', {'payload': original_text})
        for name, value in selectors.items():
            controller.request('PUT', '/proxies/' + urllib.parse.quote(name, safe=''), {'name': value})
        current = controller.request('GET', '/proxies')['proxies']
        if any(current[name]['now'] != value for name, value in selectors.items()):
            raise RuntimeError('Recovery selector verification failed')
        print('Saved runtime configuration and all select groups restored.')
        return
    if not args.config or not args.node or not args.group:
        parser.error('--config, --node and --group are required for a test session')
    original_text = args.config.read_text(encoding='utf-8-sig')
    original = load_runtime(original_text)
    modes = args.variants.split(',')
    variants = [variant_config(original, args.node, mode) for mode in modes]
    if args.dry_run:
        print(json.dumps({'variants': modes, 'only_node_edited': args.node}, ensure_ascii=False))
        return
    controller = Controller(args.controller, original.get('secret', ''))
    proxies = controller.request('GET', '/proxies')['proxies']
    selectors = {key: value['now'] for key, value in proxies.items() if value['type'] == 'Selector'}
    if args.group not in selectors or args.node not in proxies[args.group].get('all', []):
        raise ValueError('Test node must already belong to the selected group')
    args.state_dir.mkdir(parents=True, exist_ok=False)
    (args.state_dir / 'original.yaml').write_text(original_text, encoding='utf-8')
    (args.state_dir / 'selectors.json').write_text(json.dumps(selectors, ensure_ascii=False), encoding='utf-8')

    def select(testing):
        for name, value in selectors.items():
            chosen = args.node if testing and name == args.group else value
            controller.request('PUT', '/proxies/' + urllib.parse.quote(name, safe=''), {'name': chosen})
        current = controller.request('GET', '/proxies')['proxies']
        if any(current[name]['now'] != (args.node if testing and name == args.group else value)
               for name, value in selectors.items()):
            raise RuntimeError('Selector verification failed')

    try:
        for mode, cfg in zip(modes, variants):
            controller.request('PUT', '/configs', {'payload': yaml.safe_dump(cfg, allow_unicode=True, sort_keys=False)})
            select(True)
            print(f'{mode}: ready. Run your chosen test; other select groups are preserved.', flush=True)
            input('Press Enter after the test completes (Ctrl+C restores the original configuration): ')
    finally:
        controller.request('PUT', '/configs', {'payload': original_text})
        select(False)
        print('Original runtime configuration and all select groups restored.', flush=True)


if __name__ == '__main__':
    main()
