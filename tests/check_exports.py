"""Validate decoded sharing links with the real Xray core; parse YAML with real Mihomo."""
import json, os, subprocess, sys
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

directory = Path(sys.argv[1])
def native(path):
    if os.name == 'nt' and len(path) > 3 and path[0] == '/' and path[2] == '/':
        return path[1].upper() + ':' + path[2:]
    return path
xray = native(os.environ['XRAY_TEST_BIN'])
for mode in ['single', 'split', 'vision']:
    link = urlsplit((directory / (mode + '.link')).read_text().strip())
    query = parse_qs(link.query, keep_blank_values=True)
    outbound = {'protocol': 'vless', 'settings': {'vnext': [{'address':link.hostname, 'port':link.port,
        'users':[{'id':link.username, 'encryption':'none'}]}]},
        'streamSettings': {'network': query['type'][0], 'security':'reality',
            'realitySettings': {'fingerprint': query['fp'][0], 'serverName':query['sni'][0],
                'publicKey':query['pbk'][0], 'shortId':query['sid'][0]}}}
    if mode == 'vision':
        outbound['settings']['vnext'][0]['users'][0]['flow'] = query['flow'][0]
    else:
        extra = json.loads(query['extra'][0])
        assert extra['noSSEHeader'] is True and extra['scStreamUpServerSecs'] == '20-80'
        assert extra['xmux']['maxConcurrency'] == '16-32'
        outbound['streamSettings']['xhttpSettings'] = {
            'host':query['host'][0], 'path':query['path'][0], 'mode':query['mode'][0], 'extra':extra}
    config = directory / (mode + '-xray.json')
    config.write_text(json.dumps({'log': {'loglevel':'none'}, 'outbounds':[outbound]}))
    result = subprocess.run([xray,'run','-test','-config',str(config)], capture_output=True)
    assert result.returncode == 0, result.stdout.decode(errors='replace') + result.stderr.decode(errors='replace')
    if os.environ.get('MIHOMO_TEST_BIN'):
        config = directory / (mode + '-mihomo.yaml')
        fragment = (directory / (mode + '.yaml')).read_text()
        config.write_text('mode: rule\nproxies:\n' + ''.join('  '+line+'\n' for line in fragment.splitlines()) + '\nrules: ["MATCH,DIRECT"]\n')
        result = subprocess.run([native(os.environ['MIHOMO_TEST_BIN']),'-t','-d',str(directory),'-f',str(config)], capture_output=True)
        assert result.returncode == 0, result.stdout.decode(errors='replace') + result.stderr.decode(errors='replace')
print('PASS: actual Xray client configurations and Mihomo exports are accepted')
