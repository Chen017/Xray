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
