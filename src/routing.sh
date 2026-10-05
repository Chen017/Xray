#!/bin/bash

choose_outbound_strategy() {
    _info "当前: $(outbound_label "$(outbound_strategy)")"
    _info "解析顺序不等于连接失败回退；连接竞速只作用于域名目标的 TCP。"
    ask list ip_pref "IPv4解析 IPv6解析 IPv4解析优先 IPv6解析优先 双栈竞速IPv4先尝试 双栈竞速IPv6先尝试" "\n  请选择出站策略:"
    [[ $REPLY != 0 ]] || return
    local strategies=(UseIPv4 UseIPv6 UseIPv4v6 UseIPv6v4 HappyEyeballs4 HappyEyeballs6)
    config_transaction set_outbound_strategy "${strategies[$REPLY-1]}"
}

route_menu() {
    local choice
    while :; do
        _section "路由与分流"
        _menu 1 管理自定义规则
        _menu 2 设置出站IP策略
        _menu 3 切换客户端双栈分离方向
        prompt_input "选择操作（0 返回）" choice
        [[ $choice != 0 && -n $choice ]] || return
        case "$choice" in
            1) manage_custom_rules ;;
            2) choose_outbound_strategy ;;
            3) config_transaction toggle_route_mode ;;
            *) _fail "无效操作" ;;
        esac
        pause
    done
}

toggle_route_mode() {
    if [[ -f "$is_conf_dir/is_v6_uplink" ]]; then
        rm -f "$is_conf_dir/is_v6_uplink"
    else
        : > "$is_conf_dir/is_v6_uplink"
    fi
}

rules_apply() {
    local operation="$1" index="${2:-0}" rule="${3:-null}" destination="${4:-0}" rules
    rules=$(load_custom_rules) || return 1
    rules=$(jq --arg operation "$operation" --argjson index "$index" --argjson rule "$rule" --argjson destination "$destination" '
        if type != "array" then error("rules must be an array") else . end |
        if $operation == "add" then . + [$rule]
        elif $index < 0 or $index >= length then error("invalid index")
        elif $operation == "edit" then .[$index] = $rule
        elif $operation == "delete" then del(.[$index])
        elif $operation == "move" then
            if $destination < 0 or $destination >= length then error("invalid destination") else
                .[$index] as $moving | del(.[$index]) | .[:$destination] + [$moving] + .[$destination:]
            end
        else error("unknown operation") end
    ' <<< "$rules") || return 1
    save_custom_rules "$rules" && rebuild_main_config
}

prompt_rule() {
    local input tag=direct
    _info "格式: DOMAIN/DOMAIN-SUFFIX/DOMAIN-KEYWORD/IP-CIDR/GEOSITE/GEOIP,值"
    prompt_input "输入规则，例如 DOMAIN-SUFFIX,kimi.ai（0 返回）" input
    [[ -n "$input" && $input != 0 ]] || return 1
    [[ "$input" == *,* ]] && parse_rule_input "$input" || { _fail "无法识别规则格式"; return 1; }
    ask list action "直连 IPv4解析 IPv6解析 阻止" "\n  请选择规则动作:"
    [[ $REPLY != 0 ]] || return 1
    case "$REPLY" in 2) tag=direct-v4 ;; 3) tag=direct-v6 ;; 4) tag=block ;; esac
    prompted_rule=$(jq -n --arg field "$_rule_field" --arg value "$_rule_value" --arg tag "$tag" \
        '{type:"field", ($field):[$value], outboundTag:$tag}')
}

manage_custom_rules() {
    local rules count choice index destination entry field value tag
    while :; do
        clear
        _section "自定义路由规则（按列表顺序匹配）"
        rules=$(load_custom_rules)
        count=$(jq -er 'if type == "array" then length else error("invalid rules") end' <<< "$rules") || return 1
        index=1
        while IFS= read -r entry; do
            [[ -n "$entry" ]] || continue
            IFS=$'\t' read -r field value tag < <(jq -r '[
                (if .domain then "domain" elif .ip then "ip" else "protocol" end),
                (.domain[0] // .ip[0] // .protocol[0] // ""), .outboundTag] | @tsv' <<< "$entry")
            printf '  %s. %s\n' "$index" "$(rule_to_display "$field" "$value" "$tag")"
            ((index+=1))
        done < <(jq -c '.[]' <<< "$rules")
        (( count )) || _info "暂无自定义规则"
        _info "线路机的中继用户规则在这些规则之前；默认阻断规则在其后。"
        _menu 1 添加规则
        _menu 2 修改规则
        _menu 3 删除规则
        _menu 4 调整规则顺序
        prompt_input "选择操作（0 返回）" choice
        [[ $choice != 0 && -n $choice ]] || return
        case "$choice" in
            1)
                if prompt_rule; then config_transaction rules_apply add 0 "$prompted_rule"; fi
                ;;
            2|3|4)
                (( count )) || { _info "没有可操作的规则"; pause; continue; }
                prompt_input "规则序号（0 返回）" index
                [[ $index != 0 ]] || continue
                [[ $index =~ ^[1-9][0-9]*$ ]] && (( index <= count )) || { _fail "无效序号"; pause; continue; }
                ((index-=1))
                case "$choice" in
                    2) if prompt_rule; then config_transaction rules_apply edit "$index" "$prompted_rule"; fi ;;
                    3) config_transaction rules_apply delete "$index" ;;
                    4)
                        prompt_input "移动到第几条（1-$count，0 返回）" destination
                        [[ $destination != 0 ]] || continue
                        [[ $destination =~ ^[1-9][0-9]*$ ]] && (( destination <= count )) || { _fail "无效目标序号"; pause; continue; }
                        config_transaction rules_apply move "$index" null "$((destination-1))"
                        ;;
                esac
                ;;
            *) _fail "无效操作" ;;
        esac
        pause
    done
}

relay_apply_landing() {
    relay_create_landing_inbound "$1" "$2" "$3" || return 1
    local state
    state=$(jq -n --arg tuuid "$1" --arg dec "$2" --argjson port "$3" --arg enc "$4" \
        --arg lip "$5" --arg peer "$6" \
        '{version:1,role:"landing",transport_uuid:$tuuid,decryption:$dec,listen_port:$port,encryption:$enc,landing_ip:$lip,peer_ip:$peer}') || return 1
    relay_save_state "$state"
}

relay_apply_line() {
    local state
    state=$(jq -n --arg lip "$1" --argjson port "$2" --arg tuuid "$3" --arg enc "$4" --arg cuuid "$5" \
        '{version:1,role:"line",landing_ip:$lip,landing_port:$port,transport_uuid:$tuuid,encryption:$enc,client_uuid:$cuuid}') || return 1
    relay_save_state "$state" && relay_add_client_identity "$5" && rebuild_main_config
}

relay_apply_remove() {
    case "$1" in
        line) relay_delete_state && relay_remove_client_identity && rebuild_main_config ;;
        landing) relay_remove_landing_inbound && relay_delete_state ;;
        *) return 1 ;;
    esac
}

relay_setup_landing() {
    local peer landing_ip port transport_uuid
    _section "配置本机为落地机"
    command -v iptables >/dev/null || { _fail "请先安装 iptables，以限制中继来源 IP"; return 1; }
    relay_generate_vlessenc || { _fail "内核不支持所需的 VLESS Encryption，请先更新"; return 1; }
    prompt_input "线路机公网 IPv4（0 返回）" peer
    [[ $peer != 0 ]] || return
    relay_validate_ipv4 "$peer" || { _fail "无效的线路机 IPv4"; return 1; }
    get_ip || return 1
    landing_ip="$ip"
    if ! relay_validate_ipv4 "$landing_ip"; then
        prompt_input "本机公网 IPv4（0 返回）" landing_ip
    fi
    relay_validate_ipv4 "$landing_ip" && [[ $landing_ip != "$peer" ]] || { _fail "落地 IPv4 无效或与线路机相同"; return 1; }
    port=$(relay_get_random_port) || { _fail "没有可用中继端口"; return 1; }
    get_uuid
    transport_uuid="$tmp_uuid"
    if config_transaction relay_apply_landing "$transport_uuid" "$vlessenc_decryption" "$port" "$vlessenc_encryption" "$landing_ip" "$peer"; then
        _ok "落地中继已配置，只有 $peer 可以访问 TCP $port"
        _info "在线路机导入以下链接："
        relay_build_link "$transport_uuid" "$landing_ip" "$port" "$vlessenc_encryption"
    fi
}

relay_setup_line() {
    local input
    _section "配置本机为线路机"
    relay_generate_vlessenc || { _fail "内核不支持所需的 VLESS Encryption，请先更新"; return 1; }
    prompt_input "落地机中继链接（0 返回）" input
    [[ $input != 0 ]] || return
    relay_parse_link "$input" || { _fail "链接需要合法 IPv4、VLESS 加密及 RAW/Vision 参数"; return 1; }
    get_uuid
    if config_transaction relay_apply_line "$parsed_landing_ip" "$parsed_landing_port" "$parsed_transport_uuid" "$parsed_encryption" "$tmp_uuid"; then
        _ok "线路绑定成功，在导出客户端配置时选择经落地"
    fi
}

relay_remove_line() {
    prompt_confirm "解除当前线路绑定？" n || return
    config_transaction relay_apply_remove line
}
relay_remove_landing() {
    prompt_confirm "移除当前落地中继？" n || return
    config_transaction relay_apply_remove landing
}
