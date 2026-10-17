#!/usr/bin/env python3
"""Read-only Linux sampler; run via SSH stdin, write JSON lines on stdout."""
import argparse
import json
import os
from pathlib import Path
import time


def read(path):
    try:
        return Path(path).read_text().strip()
    except (OSError, PermissionError):
        return None


def proc_stat(path):
    raw = read(path)
    if raw is None:
        return None
    # comm can contain spaces and parentheses; numeric fields start after its last ).
    fields = raw[raw.rfind(")") + 2:].split()
    return {"user_ticks": int(fields[11]), "system_ticks": int(fields[12]),
            "processor": int(fields[36])}


def sample(pid):
    cpu = {}
    for line in (read('/proc/stat') or '').splitlines():
        fields = line.split()
        if fields[0].startswith('cpu'):
            cpu[fields[0]] = list(map(int, fields[1:]))
    net = {}
    for line in (read('/proc/net/dev') or '').splitlines()[2:]:
        name, values = line.split(':', 1)
        values = values.split()
        net[name.strip()] = {"rx_bytes": int(values[0]), "tx_bytes": int(values[8])}
    tasks = {}
    try:
        tids = Path(f'/proc/{pid}/task').iterdir()
        for tid in tids:
            stat = proc_stat(tid / 'stat')
            if stat is not None:
                tasks[tid.name] = stat
    except OSError:
        pass
    cgroups = {}
    for line in (read(f'/proc/{pid}/cgroup') or '').splitlines():
        hierarchy, controllers, relative = line.split(':', 2)
        # Resolve the process cgroup rather than assuming the hierarchy root.
        if hierarchy == '0' and not controllers:
            base = Path('/sys/fs/cgroup') / relative.lstrip('/')
        elif 'cpu' in controllers.split(','):
            base = Path('/sys/fs/cgroup') / controllers / relative.lstrip('/')
            if not base.exists():
                base = Path('/sys/fs/cgroup/cpu') / relative.lstrip('/')
        else:
            continue
        for name in ('cpu.max', 'cpu.stat', 'cpu.cfs_quota_us', 'cpu.cfs_period_us'):
            value = read(base / name)
            if value is not None:
                cgroups[str(base / name)] = value
    return {"utc": time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            "monotonic": time.monotonic(), "cpu_ticks": cpu, "threads": tasks,
            "net": net, "process_status": read(f'/proc/{pid}/status'),
            "cgroups": cgroups, "loadavg": read('/proc/loadavg')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pid', required=True, type=int)
    parser.add_argument('--seconds', type=int, default=180)
    parser.add_argument('--interval', type=float, default=1)
    args = parser.parse_args()
    if not 1 <= args.seconds <= 900 or not 0.2 <= args.interval <= 10:
        parser.error('seconds must be 1..900 and interval 0.2..10')
    print(json.dumps({"type": "metadata", "pid": args.pid,
                      "clock_ticks": os.sysconf('SC_CLK_TCK'), "logical_cpus": os.cpu_count(),
                      "cpu_tick_fields": ['user', 'nice', 'system', 'idle', 'iowait', 'irq',
                                          'softirq', 'steal', 'guest', 'guest_nice']}), flush=True)
    deadline = time.monotonic() + args.seconds
    while time.monotonic() < deadline:
        print(json.dumps(sample(args.pid)), flush=True)
        time.sleep(min(args.interval, max(0, deadline - time.monotonic())))


if __name__ == '__main__':
    main()
