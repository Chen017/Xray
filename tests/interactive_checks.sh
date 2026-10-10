#!/bin/bash
# Exercise the restored v2.5.4 export prompts with real client parsers.
(
    (
        create() { return 0; }
        info() { echo exported > "$TEST_STATE/auto-export"; return 1; }
        check add reality
        check test -s "$TEST_STATE/auto-export"
        create() { return 1; }
        rm "$TEST_STATE/auto-export"
        if add reality; then echo 'FAIL: failed creation reported success'; exit 1; fi
        check test ! -e "$TEST_STATE/auto-export"
    ) || exit 1
    for mode in single split vision; do
        for export_format in yaml link; do
            _reset_state
            case "$mode" in
                split) answers=$'1\n' ;;
                single) answers=$'2\n1\n' ;;
                vision) answers=$'3\n1\n' ;;
            esac
            if [[ $export_format == yaml ]]; then answers+=1; else answers+=2; fi
            # The old footer's status is not an export success indicator.
            info <<< "$answers" > "$scratch/$mode-interactive.txt" || true
            if [[ $export_format == yaml ]]; then
                awk '/^- name:/ {show=1} show' "$scratch/$mode-interactive.txt" > "$scratch/$mode.yaml"
                check grep -q 'short-id: 12345678' "$scratch/$mode.yaml"
                check grep -q 'sockopt:' "$scratch/$mode.yaml"
            else
                grep '^vless://' "$scratch/$mode-interactive.txt" > "$scratch/$mode.link"
                check test -s "$scratch/$mode.link"
            fi
        done
    done
    check python "$repo/tests/check_exports.py" "$scratch"

    cp "$is_conf_dir/VLESS-REALITY-443.json" "$scratch/node-original.json"
    jq 'del(.inbounds[].streamSettings.realitySettings.publicKey)' "$scratch/node-original.json" > "$is_conf_dir/VLESS-REALITY-443.json"
    _reset_state
    get info || true
    check test "$is_public_key" = 'Unknown(please regenerate config)'
    cp "$scratch/node-original.json" "$is_conf_dir/VLESS-REALITY-443.json"

    touch "$is_conf_dir/is_v6_uplink"
    _reset_state
    info <<< $'1\n2' > "$scratch/reverse-split.txt" || true
    check grep -q '^vless://.*@\[2001:db8::10\]:' "$scratch/reverse-split.txt"
    rm "$is_conf_dir/is_v6_uplink"
    _reset_state
    info <<< $'3\n2\n2' > "$scratch/ipv6-vision.txt" || true
    check grep -q '^vless://.*@\[2001:db8::10\]:' "$scratch/ipv6-vision.txt"

    cat <<'EOF' > "$is_relay_state_file"
{
  "version": 1,
  "role": "line",
  "landing_ip": "203.0.113.20",
  "client_uuid": "11111111-1111-4111-8111-111111111111"
}
EOF
    _reset_state
    info <<< $'2\n3\n1\n2' > "$scratch/relay-export.txt" || true
    check grep -q '^vless://11111111-1111-4111-8111-111111111111@203.0.113.10:' "$scratch/relay-export.txt"

    # Multi-landing export test: selecting second landing
    cat <<'EOF' > "$is_relay_state_file"
{
  "version": 2,
  "role": "line",
  "landings": [
    {
      "id": "1",
      "name": "落地1",
      "landing_ip": "203.0.113.20",
      "landing_port": 30001,
      "transport_uuid": "11111111-1111-4111-8111-111111111111",
      "encryption": "chacha20poly1305.x25519.0rtt.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
      "client_uuid": "11111111-1111-4111-8111-111111111111"
    },
    {
      "id": "2",
      "name": "日本落地",
      "landing_ip": "203.0.113.30",
      "landing_port": 30002,
      "transport_uuid": "22222222-2222-4222-8222-222222222222",
      "encryption": "chacha20poly1305.x25519.0rtt.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
      "client_uuid": "33333333-3333-4333-8333-333333333333"
    }
  ]
}
EOF
    _reset_state
    info <<< $'3\n3\n1\n2' > "$scratch/relay-export-second.txt" || true
    check grep -q '^vless://33333333-3333-4333-8333-333333333333@203.0.113.10:' "$scratch/relay-export-second.txt"
    check grep -q '#Premium-Landing-日本落地' "$scratch/relay-export-second.txt"
    rm -f "$is_relay_state_file"

    # Standalone landing config test without xhttp
    scratch_landing="$scratch/pure_landing"
    mkdir -p "$scratch_landing/conf"
    (
        is_conf_dir="$scratch_landing/conf"
        is_config_json="$scratch_landing/config.json"
        is_relay_state_file="$scratch_landing/relay.json"
        _create config.json
        relay_apply_landing "44444444-4444-4444-8444-444444444444" "chacha20poly1305.x25519.0rtt.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" 28888 "chacha20poly1305.x25519.0rtt.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" "nat-ddns.example.com" "" 38888
        check test -f "$scratch_landing/conf/99_relay_in.json"
        check test ! -f "$scratch_landing/conf/VLESS-REALITY-*.json"
        check jq -e '.inbounds[0].port == 28888 and .inbounds[0].tag == "relay-in"' "$scratch_landing/conf/99_relay_in.json"
        check test "$(jq -r '.external_port' "$is_relay_state_file")" = "38888"
        check test "$(jq -r '.landing_ip' "$is_relay_state_file")" = "nat-ddns.example.com"
        info_out=$(relay_view_info_landing)
        check grep -q 'nat-ddns.example.com' <<< "$info_out"
        check grep -q '@nat-ddns.example.com:38888?' <<< "$info_out"
        # Test firewall degradation when iptables tool is unavailable
        iptables() { return 1; }
        check firewall_sync
    )
) || exit 1
pass 'restored exports cover all three modes, both formats, reverse split, IPv6, multi-landing and pure landing'
