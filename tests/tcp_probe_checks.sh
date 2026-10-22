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

    curl() {
        if [[ $1 == --version ]]; then echo 'Features: HTTP2 SSL'; return; fi
        printf 'call\n' >> "$TEST_STATE/sni-http.calls"
        printf 'SSL connection using TLSv1.3\nXRAY_HTTP_VERSION:2\n'
    }
    dig() { echo 203.0.113.1; }
    unset _ov_sni_checked
    _ov_v4_sni=us.kjwing.com; _ov_v6_sni=example.org
    _check_sni_status
    check test "$_ov_v4_sni_status" = "${green}✓${none} "
    check test "$_ov_v6_sni_status" = "${green}✓${none} "
    check test "$(wc -l < "$TEST_STATE/sni-http.calls")" = 2
    _check_sni_status
    check test "$(wc -l < "$TEST_STATE/sni-http.calls")" = 2
    _ov_v4_sni=changed.example.org
    _check_sni_status
    check test "$(wc -l < "$TEST_STATE/sni-http.calls")" = 4

    check grep -q '^CDN_UNCONFIRMED|' <<< "$(_detect_cdn example.org '' $'203.0.113.1\n203.0.113.2')"
    check grep -q '^CDN_UNKNOWN|' <<< "$(_detect_cdn example.org '' '')"
    check grep -q '^CDN_UNCONFIRMED|' <<< "$(_detect_cdn example.org '' '2001:db8::1')"
    check grep -q '^CDN_UNCONFIRMED|' <<< "$(_detect_cdn example.org '' $'d123.cloudfront.net.example.org.\n203.0.113.1')"
    check grep -q '^CDN:CloudFront|' <<< "$(_detect_cdn example.org '' 'd123.cloudfront.net.')"
    check grep -q '^CDN:Cloudflare|' <<< "$(_detect_cdn example.org $'server: cloudflare\r\ncf-ray: abc' '203.0.113.1')"

    curl() {
        if [[ $1 == --version ]]; then echo 'Features: HTTP2 SSL'; return; fi
        printf 'SSL connection using TLSv1.3\nXRAY_HTTP_VERSION:1.1\n'
    }
    unset _ov_sni_checked
    _check_sni_status
    check test "$_ov_v4_sni_status" = "${red}✗${none} "

    curl() {
        if [[ $1 == --version ]]; then echo 'Features: SSL'; return; fi
        printf 'SSL connection using TLSv1.3\nXRAY_HTTP_VERSION:1.1\n'
    }
    unset _ov_sni_checked
    _check_sni_status
    check grep -q 'h2未验证' <<< "$_ov_v4_sni_status"

    dig() { return 1; }
    curl() {
        if [[ $1 == --version ]]; then echo 'Features: HTTP2 SSL'; return; fi
        return 28
    }
    unset _ov_sni_checked
    _check_sni_status
    check test "$_ov_v4_sni_status" = "${red}✗${none} "
    check grep -q 'CDN未知' <<< "$_ov_v4_cdn_status"
) || exit 1
pass 'bounded parallel SNI checks reuse HTTPS, verify h2, refresh changed domains and distinguish CDN evidence from DNS failure'
