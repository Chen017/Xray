"""Validate the YAML fragments and run the actual Mihomo config parser when available."""
import os
from pathlib import Path
import subprocess
import sys

import yaml


def native(path):
    if os.name == 'nt' and len(path) > 3 and path[0] == '/' and path[2] == '/':
        return path[1].upper() + ':' + path[2:]
    return path


directory = Path(native(sys.argv[1]))
for mode in ('single', 'split', 'vision'):
    fragment = (directory / (mode + '.yaml')).read_text(encoding='utf-8')
    proxies = yaml.safe_load(fragment)
    primary, *dependencies = proxies
    if dependencies:
        assert len(dependencies) == 1 and primary['network'] == 'xhttp', proxies
        assert primary['dialer-proxy'] == dependencies[0]['name']
        assert dependencies[0]['tfo'] is False and 'flow' not in dependencies[0]
        if mode == 'split':
            assert primary['xhttp-opts']['download-settings']['dialer-proxy'] == ''
    if primary['tls']:
        assert isinstance(primary['reality-opts']['short-id'], str), primary
    if mode == 'split':
        assert primary['xhttp-opts']['download-settings']['server'] != primary['server']
    if os.environ.get('MIHOMO_TEST_BIN'):
        config = directory / (mode + '-mihomo.yaml')
        config.write_text('proxies:\n' + ''.join('  ' + line + '\n' for line in fragment.splitlines()) +
                          'rules: ["MATCH,DIRECT"]\n', encoding='utf-8')
        result = subprocess.run([native(os.environ['MIHOMO_TEST_BIN']), '-t', '-d', str(directory), '-f', str(config)], capture_output=True)
        assert result.returncode == 0, result.stdout.decode(errors='replace') + result.stderr.decode(errors='replace')
print('PASS: Mihomo YAML fragments are accepted')
