#!/bin/bash
# The legacy probe connects to the hostname on TCP 80 without family splitting.
(
    unset _ov_ip_blocked
    timeout() {
        check test "$1" = 2
        check test "$2" = bash
        check test "$3" = -c
        check test "$4" = 'echo > /dev/tcp/sh-cm-dualstack.ip.zstaticcdn.com/80'
        echo call >> "$TEST_STATE/legacy-tcp.calls"
    }
    _check_ip_blocked
    check test "$_ov_ip_blocked" = "${green}✓${none} "
    _check_ip_blocked
    check test "$(wc -l < "$TEST_STATE/legacy-tcp.calls")" = 1
    unset _ov_ip_blocked
    timeout() { echo "$4" >> "$TEST_STATE/legacy-failed-tcp.calls"; return 1; }
    _check_ip_blocked
    check test "$_ov_ip_blocked" = "${red}✗${none} "
    check test "$(wc -l < "$TEST_STATE/legacy-failed-tcp.calls")" = 3

    curl() { echo 'SSL connection using TLSv1.3'; }
    dig() { echo 203.0.113.1; }
    unset _ov_sni_checked
    _ov_v4_sni=us.kjwing.com; _ov_v6_sni=example.org
    _check_sni_status
    check test "$_ov_v4_sni_status" = "${green}✓${none} "
    check test "$_ov_v6_sni_status" = "${green}✓${none} "
    dig() { if [[ $* == *@8.8.8.8* ]]; then echo 203.0.113.1; else echo 203.0.113.2; fi; }
    check grep -q '^CDN:Anycast/GeoDNS|' <<< "$(_detect_cdn example.org)"
) || exit 1
pass 'legacy hostname TCP 80, per-launch cache, TLS and multi-DNS checks are restored'
