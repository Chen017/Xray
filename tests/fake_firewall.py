"""Persistent iptables model for verifying ownership, guards and chain replacement."""
import json, os, sys
from pathlib import Path

root = Path(os.environ['TEST_STATE'])
family, *args = sys.argv[1:]
if args[:2] == ['-w', '5']:
    args = args[2:]
path = root / (family + '.json')
initial = {'INPUT': [['-p', 'tcp', '--dport', '22', '-j', 'ACCEPT']],
           'FORWARD': [['-j', 'EXISTING-FORWARD']], 'OUTPUT': [], 'OTHER-APP': [['-j', 'RETURN']]}
state = json.loads(path.read_text()) if path.exists() else initial
with (root / 'firewall.commands').open('a') as output:
    output.write(family + ' ' + ' '.join(args) + '\n')
op, *rest = args
chain = rest[0] if rest else None
rule = rest[1:]
code = 0
if op == '-N':
    if chain in state: code = 1
    else: state[chain] = []
elif op == '-S':
    if chain not in state: code = 1
    else:
        for item in state[chain]: print('-A', chain, *item)
elif op == '-F':
    assert chain.startswith('XRAY-'), 'attempted to flush another chain'
    if chain not in state: code = 1
    else: state[chain] = []
elif op == '-X':
    assert chain.startswith('XRAY-'), 'attempted to delete another chain'
    if chain not in state or state[chain]: code = 1
    else: del state[chain]
elif op in ['-A', '-I', '-R', '-C', '-D']:
    if chain not in state: code = 1
    elif op == '-A': state[chain].append(rule)
    elif op in ['-I', '-R']:
        index = int(rule[0]) - 1 if rule[0].isdigit() else 0
        if rule[0].isdigit(): rule = rule[1:]
        if op == '-I': state[chain].insert(index, rule)
        else: state[chain][index] = rule
    elif op == '-C': code = 0 if rule in state[chain] else 1
    elif op == '-D':
        if rule in state[chain]: state[chain].remove(rule)
        else: code = 1
else:
    raise AssertionError('unexpected/global firewall operation: ' + op)
path.write_text(json.dumps(state))
sys.exit(code)
