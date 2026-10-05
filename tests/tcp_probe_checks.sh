#!/bin/bash
(
    getent() {
        if [[ $1 == ahostsv6 ]]; then printf '%s\n' '::ffff:203.0.113.1 STREAM' '2001:db8::1 STREAM'
        else echo '203.0.113.1 STREAM'; fi
    }
    timeout() {
        check test "$1" = 2
        shift
        if [[ $1 == bash ]]; then
            check test "$2" = -c
            check test "$3" = ': > /dev/tcp/"$1"/80'
            printf '%s\n' "$5" >> "$TEST_STATE/tcp-addresses"
        else "$@"; fi
    }
    check domestic_tcp_probe example.com 4
    check domestic_tcp_probe example.com 6
    check test "$(cat "$TEST_STATE/tcp-addresses")" = $'203.0.113.1\n2001:db8::1'
    getent() { echo '::ffff:203.0.113.1 STREAM'; }
    if domestic_tcp_probe example.com 6; then echo 'FAIL: mapped IPv4 counted as IPv6'; exit 1; fi
    getent() { return 2; }
    if domestic_tcp_probe example.com 4; then echo 'FAIL: failed DNS accepted'; exit 1; fi
    timeout() { return 124; }
    if domestic_tcp_probe example.com 4; then echo 'FAIL: timeout accepted'; exit 1; fi
) || exit 1
pass 'domestic probes connect to TCP/80 with explicit IPv4/IPv6 and reject mapped IPv4, DNS failures and timeouts'
