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
                check grep -q 'short-id: "12345678"' "$scratch/$mode.yaml"
                check grep -q '^  tfo: true$' "$scratch/$mode.yaml"
                check grep -q '^  mptcp: true$' "$scratch/$mode.yaml"
                check grep -q '^  udp: true$' "$scratch/$mode.yaml"
                if grep -q 'sockopt:' "$scratch/$mode.yaml"; then
                    echo 'FAIL: ignored Mihomo sockopt block was exported'; exit 1
                fi
                if [[ $mode != vision ]]; then
                    for parameter in 'x-padding-bytes: "100-1000"' 'x-padding-obfs-mode: true' \
                        'x-padding-placement: queryInHeader' 'x-padding-method: tokenish' \
                        'x-padding-key: x_padding' 'x-padding-header: Referer' \
                        'no-grpc-header: true' 'session-placement: path' 'seq-placement: path'; do
                        check grep -Fqx "    $parameter" "$scratch/$mode.yaml"
                    done
                    check grep -q '^      max-concurrency: "16-32"$' "$scratch/$mode.yaml"
                fi
                if [[ $mode == split ]]; then
                    check grep -q '^      client-fingerprint: firefox$' "$scratch/$mode.yaml"
                    check grep -q '^        max-concurrency: "8-16"$' "$scratch/$mode.yaml"
                    if grep -qE '^      (x-padding-|no-grpc-header:|session-placement:|seq-placement:)' "$scratch/$mode.yaml"; then
                        echo 'FAIL: ignored download-settings overrides were exported'; exit 1
                    fi
                fi
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
    check grep -q "#$(printf '%s' 'Premium-Landing-日本落地' | jq -Rr @uri)" "$scratch/relay-export-second.txt"
    rm -f "$is_relay_state_file"

    # Standalone landing config test without xhttp
    scratch_landing="$scratch/pure_landing"
    mkdir -p "$scratch_landing/conf"
    (
        is_core_dir="$scratch_landing"
        is_custom_rules_file="$scratch_landing/custom_rules.json"
        mkdir -p "$scratch_landing/bin"
        cp "$scratch/install/bin/"* "$scratch_landing/bin/" 2>/dev/null || true
        is_conf_dir="$scratch_landing/conf"
        is_config_json="$scratch_landing/config.json"
        is_relay_state_file="$scratch_landing/relay.json"
        _create config.json
        check relay_generate_vlessenc
        relay_apply_landing "44444444-4444-4444-8444-444444444444" "$vlessenc_decryption" 28888 "$vlessenc_encryption" "nat-ddns.example.com" "" 38888
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

        # Test change menu and options for pure landing server
        clear() { :; }
        # 1. Main menu option 1 routes to landing config menu without blocking
        landing_menu_out="$scratch_landing/main-menu-change.txt"
        _reset_state
        is_main_menu <<< $'1\n0\n0\n' > "$landing_menu_out" || true
        check grep -q '落地机配置更改' "$landing_menu_out"
        check grep -q '管理自定义分流规则' "$landing_menu_out"
        check grep -q '切换出站 IP 优先' "$landing_menu_out"
        if grep -q '无独立客户端节点配置' "$landing_menu_out"; then
            echo 'FAIL: landing change menu was blocked in main menu'
            exit 1
        fi

        # 2. Change outbound strategy in landing mode
        change <<< $'2\n1\n\n0\n' > "$scratch_landing/change-strategy.txt" || true
        check test "$(jq -r '.outbounds[] | select(.tag == "direct") | .settings.domainStrategy' "$is_config_json")" = "UseIPv4"

        # 3. Manage custom rules in landing mode
        change <<< $'1\n1\nDOMAIN-SUFFIX,netflix.com\n1\n0\n0\n' > "$scratch_landing/change-rules.txt" || true
        check jq -e '.[0].domain[0] == "domain:netflix.com"' "$is_custom_rules_file"
        check jq -e '.routing.rules[] | select(.domain[0]? == "domain:netflix.com" and .outboundTag == "direct")' "$is_config_json"

        # 4. Quick execution via is_change_id in landing mode
        is_change_id=10 change <<< $'2\n' >/dev/null || true
        check test "$(jq -r '.outbounds[] | select(.tag == "direct") | .settings.domainStrategy' "$is_config_json")" = "UseIPv6"
        unset is_change_id

        # 5. Configure and toggle v4 entry VLESS Encryption (方案一) interactively in pure landing mode
        change <<< $'3\n28889\n38889\n\n0\n' > "$scratch_landing/change-entry-on.txt" || true
        check jq -e '.entry_listen_port == 28889 and .entry_external_port == 38889 and (.entry_uuid | length > 0) and (.entry_encryption | startswith("mlkem768x25519plus.random."))' "$is_relay_state_file"
        check jq -e '.inbounds[1].tag == "relay-entry-v4" and .inbounds[1].port == 28889 and .inbounds[1].protocol == "vless" and .inbounds[1].streamSettings.network == "raw"' "$scratch_landing/conf/99_relay_in.json"
        check jq -e '(.inbounds[1].settings.clients[0].flow | not) and (.inbounds[1].settings.decryption | startswith("mlkem768x25519plus.random.600s."))' "$scratch_landing/conf/99_relay_in.json"
        info_out_entry=$(relay_view_info_landing)
        check grep -q '&entry_port=38889&entry_uuid=' <<< "$info_out_entry"

        # 5b. Direct client export on pure landing machine via export_landing_vlessenc (YAML + URI)
        export_landing_vlessenc <<< $'1\n' > "$scratch_landing/direct-yaml.txt" || true
        check grep -q 'NAT-v4-VLESS-Enc' "$scratch_landing/direct-yaml.txt"
        check grep -q 'mlkem768x25519plus.random.0rtt.' "$scratch_landing/direct-yaml.txt"
        export_landing_vlessenc <<< $'2\n' > "$scratch_landing/direct-link.txt" || true
        check grep -q '@nat-ddns.example.com:38889?encryption=mlkem768x25519plus.random.0rtt.' "$scratch_landing/direct-link.txt"

        # Turn off v4 entry VLESS Encryption via menu
        change <<< $'3\n2\n\n0\n' > "$scratch_landing/change-entry-off.txt" || true
        check test "$(jq -r '.entry_listen_port // 0' "$is_relay_state_file")" = "0"
        check jq -e '.inbounds | length == 1' "$scratch_landing/conf/99_relay_in.json"
    )

    # Cross-VPS v4 entry separation export test (HK-NAT v4 方案一 + HK v6 split, landing on HK-NAT v4)
    scratch_cross="$scratch/cross_split"
    mkdir -p "$scratch_cross"
    cat <<'EOF' > "$is_relay_state_file"
{
  "version": 2,
  "role": "line",
  "landings": [
    {
      "id": "1",
      "name": "HK-NAT",
      "landing_ip": "203.0.113.50",
      "landing_port": 30001,
      "entry_port": 40002,
      "entry_uuid": "66666666-6666-4666-8666-666666666666",
      "entry_encryption": "mlkem768x25519plus.random.0rtt.100-111-1111.75-0-111.50-0-3333.BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB",
      "transport_uuid": "11111111-1111-4111-8111-111111111111",
      "encryption": "chacha20poly1305.x25519.0rtt.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      "client_uuid": "55555555-5555-4555-8555-555555555555"
    }
  ]
}
EOF
    # Test dynamic entry_port update via relay_menu_entry_port (keep existing uuid & enc with Enter)
    relay_menu_entry_port <<< $'40008\n\n\n' >/dev/null
    check test "$(jq -r '.landings[0].entry_port' "$is_relay_state_file")" = "40008"
    for mode in single split vision; do
        for export_format in yaml link; do
            _reset_state
            case "$mode" in
                split) answers=$'2
1
' ;;
                single) answers=$'2
2
1
' ;;
                vision) answers=$'2
3
1
' ;;
            esac
            if [[ $export_format == yaml ]]; then answers+=1; else answers+=2; fi
            info <<< "$answers" > "$scratch_cross/$mode-interactive.txt" || true
            if [[ $export_format == yaml ]]; then
                awk '/^- name:/ {show=1} show' "$scratch_cross/$mode-interactive.txt" > "$scratch_cross/$mode.yaml"
                check grep -q 'server: "203.0.113.50"' "$scratch_cross/$mode.yaml"
                check grep -q 'port: 40008' "$scratch_cross/$mode.yaml"
                check grep -q 'mlkem768x25519plus.random.0rtt.' "$scratch_cross/$mode.yaml"
                if [[ $mode == split ]]; then
                    check grep -q 'server: "2001:db8::10"' "$scratch_cross/$mode.yaml"
                    check grep -q 'port: 443' "$scratch_cross/$mode.yaml"
                elif [[ $mode == single ]]; then
                    check grep -q 'dialer-proxy:' "$scratch_cross/$mode.yaml"
                fi
            else
                grep '^vless://' "$scratch_cross/$mode-interactive.txt" > "$scratch_cross/$mode.link"
                if [[ $mode == split || $mode == single ]]; then
                    check grep -q '^vless://55555555-5555-4555-8555-555555555555@203.0.113.10:443?' "$scratch_cross/$mode.link"
                fi
                check grep -q '^vless://66666666-6666-4666-8666-666666666666@203.0.113.50:40008?encryption=mlkem768x25519plus.random.0rtt.' "$scratch_cross/$mode.link" 
            fi
        done
    done
    check python "$repo/tests/check_exports.py" "$scratch_cross"

    # Disable entry_port via relay_menu_entry_port and verify fallback to local HK v4:443
    relay_menu_entry_port <<< $'0\n' >/dev/null
    check test "$(jq -r '.landings[0].entry_port // 0' "$is_relay_state_file")" = "0"
    _reset_state
    info <<< $'2
1
2' > "$scratch_cross/local-v4-link.txt" || true
    check grep -q '^vless://55555555-5555-4555-8555-555555555555@203.0.113.10:443?' "$scratch_cross/local-v4-link.txt"
    rm -f "$is_relay_state_file"
) || exit 1
pass 'restored exports cover all three modes, both formats, Scheme 1 VLESS Encryption NAT v4 split, IPv6, multi-landing and pure landing'
