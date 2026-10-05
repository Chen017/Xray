#!/bin/bash
# Loaded by regression.sh after the isolated installation has been created.

check test "$(system_firewall_summary)" = 22,443
check iptables -N USER-IN
check iptables -A INPUT -j USER-IN
check iptables -A USER-IN -p tcp -m multiport --dports 80,8080,10000:10010 -j ACCEPT
check iptables -A USER-IN -p tcp --dport 8443 -j ACCEPT
check iptables -N UNATTACHED
check iptables -A UNATTACHED -p tcp --dport 9999 -j ACCEPT
check iptables -A OUTPUT -p tcp --dport 5555 -j ACCEPT
check test "$(system_firewall_summary)" = 22,80,443,8080,8443,10000-10010
pass 'firewall overview includes reachable custom chains, multiports and ranges, excluding unrelated chains'

(
    ss() {
        printf '%s\n' 'tcp LISTEN 0 128 0.0.0.0:22 0.0.0.0:*' \
            'tcp LISTEN 0 128 [::]:443 [::]:*' 'udp UNCONN 0 0 127.0.0.1:5353 0.0.0.0:*' \
            'tcp LISTEN 0 128 [::]:443 [::]:*'
    }
    check test "$(system_listening_ports)" = 22,443,5353
    ss() { return 1; }
    check test "$(system_listening_ports)" = 读取失败
) || exit 1
pass 'listening-port summary includes TCP/UDP and IPv4/IPv6, and distinguishes read failures'

(
    nft() {
        cat <<'JSON'
{"nftables":[
 {"chain":{"family":"inet","table":"user","name":"input","hook":"input","policy":"drop"}},
 {"chain":{"family":"inet","table":"user","name":"services"}},
 {"set":{"family":"inet","table":"user","name":"ports","elem":[9090,{"range":[12000,12010]}]}},
 {"rule":{"family":"inet","table":"user","chain":"input","expr":[{"jump":{"target":"services"}}]}},
 {"rule":{"family":"inet","table":"user","chain":"services","expr":[{"match":{"op":"==","left":{"payload":{"protocol":"tcp","field":"dport"}},"right":{"set":[80,443]}}},{"accept":null}]}},
 {"rule":{"family":"inet","table":"user","chain":"services","expr":[{"match":{"op":"==","left":{"payload":{"protocol":"udp","field":"dport"}},"right":"@ports"}},{"accept":null}]}},
 {"rule":{"family":"inet","table":"user","chain":"services","expr":[{"match":{"op":"==","left":{"meta":{"key":"l4proto"}},"right":{"set":["tcp","udp"]}}},{"match":{"op":"==","left":{"payload":{"protocol":"th","field":"dport"}},"right":5353}},{"accept":null}]}},
 {"rule":{"family":"inet","table":"user","chain":"unattached","expr":[{"match":{"op":"==","left":{"payload":{"protocol":"tcp","field":"dport"}},"right":7777}},{"accept":null}]}}
]}
JSON
    }
    summary=$(system_firewall_summary)
    check grep -q '9090' <<< "$summary"
    check grep -q '12000-12010' <<< "$summary"
    check grep -q '5353' <<< "$summary"
    if [[ $summary == *7777* ]]; then echo 'FAIL: unattached nft chain listed'; exit 1; fi
) || exit 1
pass 'native nftables summary follows INPUT jumps and handles inline and named port sets'

# Simulate a new script launch: old cache must not suppress startup probes.
(
    curl() {
        if [[ $1 == --version ]]; then echo 'Features: HTTP2'; return; fi
        echo call >> "$TEST_STATE/startup-curl.calls"
        if [[ $* == *ipinfo.io* ]]; then echo 'AS123 example'; else echo -n 2; fi
    }
    dig() { if [[ $* == *AAAA* ]]; then echo 2001:db8::1; else echo 203.0.113.1; fi; }
    domestic_tcp_probe() { echo call >> "$TEST_STATE/startup-tcp.calls"; return 0; }
    timeout() { shift; "$@"; }
    cache_test_key='4:us.kjwing.com'
    diagnostic_cache[$cache_test_key]='stale'
    check refresh_startup_checks
    check test "${diagnostic_cache[$cache_test_key]}" != stale
    check test "$(wc -l < "$TEST_STATE/startup-tcp.calls")" = 2
    _get_overview
    check test "$_ov_ip_blocked" != "${gray}未检测${none}"
    check test -n "$_ov_v4_sni_status"
    count=$(wc -l < "$TEST_STATE/startup-curl.calls")
    domestic_time=0
    _get_overview
    check test "$_ov_ip_blocked" != "${gray}未检测${none}"
    check test "$count" = "$(wc -l < "$TEST_STATE/startup-curl.calls")"
    check refresh_startup_checks
    check test "$count" -lt "$(wc -l < "$TEST_STATE/startup-curl.calls")"
    domestic_tcp_probe() { return 1; }
    diagnose_domestic >/dev/null
    _get_overview
    check test "$_ov_ip_blocked" = "${red}✗${none}"
    domestic_tcp_probe() { [[ $2 == 4 ]]; }
    diagnose_domestic >/dev/null
    check test "$domestic_status" = "v4 ${green}✓${none} / v6 ${red}✗${none}"
    domestic_tcp_probe() { [[ $2 == 6 ]]; }
    diagnose_domestic >/dev/null
    check test "$domestic_status" = "v4 ${red}✗${none} / v6 ${green}✓${none}"
    domestic_tcp_probe() { return 0; }
    diagnose_domestic >/dev/null
    check test "$domestic_status" = "${green}✓${none}"
) || exit 1
pass 'each startup refreshes TCP/SNI checks; returning to the menu uses the current launch cache'

(
    dig() { return 1; }
    curl() {
        if [[ $1 == --version ]]; then echo 'Features: HTTP2'; return; fi
        echo 'certificate verification failed' >&2
        return 60
    }
    check diagnose_sni us.kjwing.com 4 1 > /dev/null
    _get_overview
    check test "$_ov_v4_sni_status" = "${red}✗ ${none}"
    check grep -q 'v4 SNI' <<< "$_ov_sni_warning"
    curl() {
        if [[ $1 == --version ]]; then echo 'Features: SSL'; else echo -n 1.1; fi
    }
    check diagnose_sni us.kjwing.com 4 1 > /dev/null
    _get_overview
    check test "$_ov_v4_sni_status" = "${yellow}? ${none}"
    check test -z "$_ov_v4_cdn_status"
    curl() {
        if [[ $1 == --version ]]; then echo 'Features: HTTP2'; else echo -n 1.1; fi
    }
    check diagnose_sni us.kjwing.com 4 1 > /dev/null
    _get_overview
    check test "$_ov_v4_sni_status" = "${red}✗ ${none}"
) || exit 1
pass 'failed TLS/h2 checks show the original failure badge; missing HTTP2 capability and DNS results remain unknown'
