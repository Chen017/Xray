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

    printf '{"role":"line","landing_ip":"203.0.113.20","client_uuid":"11111111-1111-4111-8111-111111111111"}\n' > "$is_relay_state_file"
    _reset_state
    info <<< $'2\n3\n1\n2' > "$scratch/relay-export.txt" || true
    check grep -q '^vless://11111111-1111-4111-8111-111111111111@203.0.113.10:' "$scratch/relay-export.txt"
) || exit 1
pass 'restored exports cover all three modes, both formats, reverse split, IPv6 and relay identities'
