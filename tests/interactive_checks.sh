#!/bin/bash
# Exercise real selection functions rather than calling export generators directly.
(
    _reset_state
    check get info
    check test "$is_config_file" = VLESS-REALITY-443.json
    host=custom.example.com
    check get addr
    check test "$is_addr" = custom.example.com
    unset host
    for mode in single split vision; do
        for export_format in yaml link; do
            _reset_state
            case "$mode" in
                split) answers=$'1\n' ;;
                single) answers=$'2\n1\n' ;;
                vision) answers=$'3\n1\n' ;;
            esac
            if [[ $export_format == yaml ]]; then answers+=1; else answers+=2; fi
            check info <<< "$answers" > "$scratch/$mode-interactive.txt"
            if [[ $export_format == yaml ]]; then
                awk '/^- name:/ {show=1} show' "$scratch/$mode-interactive.txt" > "$scratch/$mode.yaml"
                check test -s "$scratch/$mode.yaml"
            else
                grep '^vless://' "$scratch/$mode-interactive.txt" > "$scratch/$mode.link"
                check test -s "$scratch/$mode.link"
            fi
        done
    done
    check python "$repo/tests/check_exports.py" "$scratch"

    # Legacy configs may omit the stored public key; derive it with the real core.
    cp "$is_conf_dir/VLESS-REALITY-443.json" "$scratch/node-original.json"
    expected_public_key="$is_public_key"
    jq 'del(.inbounds[].streamSettings.realitySettings.publicKey)' "$scratch/node-original.json" > "$is_conf_dir/VLESS-REALITY-443.json"
    _reset_state
    check get info
    check test "$is_public_key" = "$expected_public_key"
    cp "$scratch/node-original.json" "$is_conf_dir/VLESS-REALITY-443.json"

    touch "$is_conf_dir/is_v6_uplink"
    _reset_state
    check info <<< $'1\n2' > "$scratch/reverse-split.txt"
    check grep -q '^vless://.*@\[2001:db8::10\]:' "$scratch/reverse-split.txt"
    rm "$is_conf_dir/is_v6_uplink"
    _reset_state
    check info <<< $'3\n2\n2' > "$scratch/ipv6-vision.txt"
    check grep -q '^vless://.*@\[2001:db8::10\]:' "$scratch/ipv6-vision.txt"

    # Missing IPv6 must produce an explanation, not an empty split configuration.
    _reset_state
    get_ipv6() { ipv6=""; return 1; }
    if info <<< 1 > "$scratch/missing-ipv6.txt"; then echo 'FAIL: split export accepted missing IPv6'; exit 1; fi
    check grep -q '双栈分离需要公网 IPv4 和 IPv6' "$scratch/missing-ipv6.txt"
    check info <<< $'2\n1\n2' > "$scratch/ipv4-only.txt"
    check grep -q '^vless://' "$scratch/ipv4-only.txt"

    # Multiple configs require selection; cancelling leaves no selected config.
    cp "$is_conf_dir/VLESS-REALITY-443.json" "$is_conf_dir/VLESS-REALITY-8443.json"
    _reset_state
    check get info <<< 2 > /dev/null
    check test "$is_config_file" = VLESS-REALITY-8443.json
    _reset_state
    if get info <<< 0 > /dev/null; then echo 'FAIL: cancelled config selection succeeded'; exit 1; fi
    rm "$is_conf_dir/VLESS-REALITY-8443.json"

    _reset_state
    if get info MISSING-CONFIG > "$scratch/missing-node.txt"; then echo 'FAIL: missing config accepted'; exit 1; fi
    check grep -q '无法找到相关的配置文件' "$scratch/missing-node.txt"

    clear() { :; }
    _reset_state
    check is_main_menu <<< $'2\n2\n1\n2\n\n0' > "$scratch/menu-export.txt"
    check grep -q '^vless://' "$scratch/menu-export.txt"
) || exit 1
pass 'interactive export choices, reverse split/IPv6, legacy key derivation and missing/multiple configs work'
