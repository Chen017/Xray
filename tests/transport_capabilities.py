#!/usr/bin/env python3
"""Read-only host capability report. No sysctl writes or remote traffic."""
import json
from pathlib import Path
import platform
import socket
import sys


def integer(path):
    try:
        return int(Path(path).read_text().strip())
    except (OSError, ValueError):
        return None


def report():
    result = {'platform': platform.system(), 'kernel': platform.release(),
              'tcp_fast_open': {}, 'mptcp': {},
              'end_to_end_tfo_cookie_or_mptcp_subflows': 'not_tested'}
    if sys.platform != 'linux':
        result['tcp_fast_open']['host_probe'] = 'not_implemented_on_this_platform'
        if sys.platform == 'win32':
            # Windows TCP_FASTOPEN = 15 (golang.org/x/sys/windows).
            try:
                with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
                    probe.setsockopt(socket.IPPROTO_TCP, 15, 1)
                result['tcp_fast_open']['unbound_socket_option'] = 'available'
                result['tcp_fast_open']['host_probe'] = 'unbound_socket_only'
            except OSError as exc:
                result['tcp_fast_open']['unbound_socket_option'] = f'unavailable_errno_{exc.errno}'
        result['mptcp'] = {'go_net_support': False,
                           'reason': 'Go net uses ordinary TCP on non-Linux platforms'}
        return result
    mask = integer('/proc/sys/net/ipv4/tcp_fastopen')
    result['tcp_fast_open'] = {'sysctl_mask': mask,
                              'client_enabled': bool(mask & 1) if mask is not None else None,
                              'server_enabled': bool(mask & 2) if mask is not None else None}
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            probe.setsockopt(socket.IPPROTO_TCP, getattr(socket, 'TCP_FASTOPEN', 23), 1)
        result['tcp_fast_open']['unbound_socket_option'] = 'available'
    except OSError as exc:
        result['tcp_fast_open']['unbound_socket_option'] = f'unavailable_errno_{exc.errno}'
    result['mptcp'] = {'go_net_support': True, 'sysctl_enabled': integer('/proc/sys/net/mptcp/enabled')}
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM, getattr(socket, 'IPPROTO_MPTCP', 262)):
            pass
        result['mptcp']['unbound_socket'] = 'available'
    except OSError as exc:
        result['mptcp']['unbound_socket'] = f'unavailable_errno_{exc.errno}'
    return result


if __name__ == '__main__':
    print(json.dumps(report(), indent=2))
