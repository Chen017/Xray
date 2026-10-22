#!/bin/bash
# Regression cases for configuration/export bugs found in the full code review.
(
    original_node="$is_conf_dir/VLESS-REALITY-443.json"
    original_config="$is_config_json"
    is_core_dir="$scratch/review-fixes"
    is_conf_dir="$is_core_dir/conf"
    is_config_json="$is_core_dir/config.json"
    is_relay_state_file="$is_core_dir/relay.json"
    is_custom_rules_file="$is_core_dir/custom_rules.json"
    firewall_ports_file="$is_core_dir/firewall_ports.json"
    mkdir -p "$is_conf_dir" "$is_core_dir/state"
    cp "$original_node" "$is_conf_dir/VLESS-REALITY-443.json"
    cp "$original_config" "$is_config_json"
    export TEST_STATE="$is_core_dir/state"
    case "$(uname -s)" in MINGW*|MSYS*) TEST_STATE=$(cygpath -m "$TEST_STATE") ;; esac
    touch "$TEST_STATE/active"

    check config_transaction relay_apply_landing "$transport_uuid" "$vlessenc_decryption" 30443 "$vlessenc_encryption" 203.0.113.20 ''
    check python -c 'import json,os; from pathlib import Path; s=json.loads((Path(os.environ["TEST_STATE"])/"v4.json").read_text()); r=s[s["XRAY-SCRIPT"][0][-1]]; assert ["-p","tcp","--dport","30443","-j","ACCEPT"] in r; assert not any("30443" in x and "udp" in x for x in r)'
    check config_transaction relay_apply_remove landing

    for mode in single split vision; do
        for format in yaml link; do
            _reset_state
            case "$mode" in
                split) answers=$'1\n' ;;
                single) answers=$'2\n1\n' ;;
                vision) answers=$'3\n1\n' ;;
            esac
            if [[ $format == yaml ]]; then answers+=1; else answers+=2; fi
            # Numeric-looking hex must remain exact, including leading zeroes.
            get info
            v4_short_ids='["00123456"]'
            v6_short_ids='["87654321","0000123456789012"]'
            info <<< "$answers" > "$is_core_dir/$mode-output" || true
            if [[ $format == yaml ]]; then
                awk '/^- name:/ {show=1} show' "$is_core_dir/$mode-output" > "$is_core_dir/$mode.yaml"
            else
                grep '^vless://' "$is_core_dir/$mode-output" > "$is_core_dir/$mode.link"
            fi
        done
    done
    check python "$repo/tests/check_exports.py" "$is_core_dir"

    # Exercise both direction changes without restarting the manager process.
    touch "$is_conf_dir/is_v6_uplink"
    _reset_state
    info <<< $'1\n2' > "$is_core_dir/reverse-link" || true
    check grep -q '^vless://.*@\[2001:db8::10\]:' "$is_core_dir/reverse-link"
    rm "$is_conf_dir/is_v6_uplink"
    # No reset here: the export itself must derive the direction from the file.
    info <<< $'1\n2' > "$is_core_dir/forward-link" || true
    check grep -q '^vless://.*@203.0.113.10:' "$is_core_dir/forward-link"

    first_uuid=$("$is_core_bin" uuid)
    second_uuid=$("$is_core_bin" uuid)
    check config_transaction relay_apply_line 203.0.113.20 30001 "$transport_uuid" "$vlessenc_encryption" "$first_uuid" 'Hong Kong: "Primary" &备用'
    check config_transaction relay_apply_line 203.0.113.30 30002 "$transport_uuid" "$vlessenc_encryption" "$second_uuid" 'Japan Tokyo'
    _reset_state
    info <<< $'3\n3\n1\n2' > "$is_core_dir/alias-link" || true
    check grep -q "^vless://$second_uuid@" "$is_core_dir/alias-link"
    check grep -q '#Premium-Landing-Japan%20Tokyo' "$is_core_dir/alias-link"
    _reset_state
    info <<< $'2\n3\n1\n1' > "$is_core_dir/alias-yaml-output" || true
    awk '/^- name:/ {show=1} show' "$is_core_dir/alias-yaml-output" > "$is_core_dir/alias.yaml"
    check python -c 'import sys,yaml; from pathlib import Path; s=sys.argv[1]; s=(s[1].upper()+":"+s[2:]) if s.startswith("/") and s[2:3]=="/" and sys.platform=="win32" else s; v=yaml.safe_load(Path(s).read_text())[0]; assert "Hong Kong:" in v["name"] and "\"Primary\"" in v["name"]' "$is_core_dir/alias.yaml"

    check config_transaction relay_apply_failover true 30s '["2","1"]'
    check config_transaction relay_apply_line 203.0.113.40 30003 "$transport_uuid" "$vlessenc_encryption" "$("$is_core_bin" uuid)" third
    check jq -e '.failover.order == ["2","1","3"]' "$is_relay_state_file"
    check jq -e '.routing.balancers[0].tag == "relay-balancer-2" and .routing.balancers[0].fallbackTag == "loop-relay-1"' "$is_config_json"
) || exit 1
pass 'review regressions preserve Short IDs, direction, aliases, client-only links, landing reachability and failover priority'
