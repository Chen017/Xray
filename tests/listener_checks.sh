#!/bin/bash
# Resolve a bindable local address, including NAT and IPv6-only installations.
(
    ip() { printf '%s\n' '1.1.1.1 via 10.0.0.1 dev eth0 src 10.0.0.2 uid 0'; }
    check test "$(node_ipv4_listen_address)" = 10.0.0.2
    ip() { [[ $1 != -4 ]] && printf '%s\n' '2: eth0 inet 192.0.2.5/24 scope global eth0'; return 0; }
    check test "$(node_ipv4_listen_address)" = 192.0.2.5
    ip() { return 1; }
    check test "$(node_ipv4_listen_address)" = 127.0.0.1
) || exit 1
pass 'listener address uses local NAT address, assigned fallback and IPv6-only loopback'

# Isolated parser fixtures must not depend on the host's live routes.
node_ipv4_listen_address() { printf '%s\n' 203.0.113.10; }
