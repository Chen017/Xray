#!/bin/bash

_reset_state() {
    unset is_protocol is_config_file is_config_name is_json_str net is_reality port uuid
    unset is_private_key is_public_key v4_sni v6_sni v4_path v6_path v4_short_ids v6_short_ids
    unset is_change is_change_id is_dont_show_info is_auto_get_config is_new_json is_conf_dir_empty
    unset is_addr is_core_stop is_new_protocol is_short_ids is_new_v4_sni is_new_v6_sni is_servername
    unset is_default_arg is_new_v4_path is_new_uuid is_new_port
    if service_active; then is_core_status="${green}● 运行中${none}"
    else is_core_status="${red}● 已停止${none}"; is_core_stop=1; fi
    if service_active; then is_core_status_short="${green}运行中${none}"
    else is_core_status_short="${red}已停止${none}"; fi
}

_get_overview() {
    local first values cached state='{"open":[],"closed":[]}'
    _ov_port=""; _ov_v4_sni=""; _ov_v6_sni=""
    _ov_uuid=""; _ov_v4_sids=""; _ov_v6_sids=""; _ov_path=""; _ov_pbk=""
    _ov_v4_sni_status=""; _ov_v6_sni_status=""; _ov_v4_cdn_status=""; _ov_v6_cdn_status=""
    _ov_ip_blocked="${gray}未检测${none}"
    _ov_ip_warning=""; _ov_sni_warning=""; _ov_cdn_warning=""; _ov_relay_warn=""
    first=$(list_managed_node_configs | head -1)
    if [[ -n $first ]]; then
        mapfile -t values < <(jq -r '.inbounds[0].port // "",
            .inbounds[0].streamSettings.realitySettings.serverNames[0] // "",
            .inbounds[1].streamSettings.realitySettings.serverNames[0] // "",
            .inbounds[0].settings.clients[0].id // "",
            (.inbounds[0].streamSettings.realitySettings.shortIds // [] | join(",")),
            (.inbounds[1].streamSettings.realitySettings.shortIds // [] | join(",")),
            .inbounds[2].streamSettings.xhttpSettings.path // "",
            .inbounds[0].streamSettings.realitySettings.publicKey // ""' "$is_conf_dir/$first")
        _ov_port=${values[0]:-}; _ov_v4_sni=${values[1]:-}; _ov_v6_sni=${values[2]:-}
        _ov_uuid=${values[3]:-}; _ov_v4_sids=${values[4]:-}; _ov_v6_sids=${values[5]:-}
        _ov_path=${values[6]:-}; _ov_pbk=${values[7]:-}
    fi
    cached=${diagnostic_cache["4:$_ov_v4_sni"]:-}
    [[ $cached != *'证书、TLS 1.3 与 h2 通过'* ]] || _ov_v4_sni_status="${green}✓ ${none}"
    [[ $cached != *'疑似 CDN'* ]] || _ov_v4_cdn_status="${red}CDN ${none}"
    cached=${diagnostic_cache["6:$_ov_v6_sni"]:-}
    [[ $cached != *'证书、TLS 1.3 与 h2 通过'* ]] || _ov_v6_sni_status="${green}✓ ${none}"
    [[ $cached != *'疑似 CDN'* ]] || _ov_v6_cdn_status="${red}CDN ${none}"
    _ov_route_mode='v4上行/v6下行'
    [[ ! -f "$is_conf_dir/is_v6_uplink" ]] || _ov_route_mode='v6上行/v4下行'
    case "$(outbound_strategy)" in
        UseIPv4) _ov_outbound_pref='v4优先' ;;
        UseIPv6|UseIPv6v4) _ov_outbound_pref='v6优先' ;;
        UseIPv4v6) _ov_outbound_pref='双栈优选' ;;
        HappyEyeballs4) _ov_outbound_pref='双栈竞速(v4先)' ;;
        HappyEyeballs6) _ov_outbound_pref='双栈竞速(v6先)' ;;
        *) _ov_outbound_pref='未知' ;;
    esac
    _ov_log_level=$(jq -r '.log.loglevel // "未知"' "$is_config_json" 2>/dev/null)
    [[ ! -f $firewall_ports_file ]] || state=$(cat "$firewall_ports_file")
    _ov_fw_ports=$(jq -sr --argjson state "$state" '
        ([.[] | .inbounds[]? | select(.streamSettings.security == "reality") | .port] + $state.open) |
        unique - $state.closed | map(tostring) | join(", ")' "$is_conf_dir"/*.json 2>/dev/null)
    _ov_fw_ports=${_ov_fw_ports:-无}
    _ov_sys_ports="无"
    if command -v ss >/dev/null; then
        _ov_sys_ports=$(ss -tuln 2>/dev/null | awk '$1 ~ /^(tcp|udp)/ {n=split($5,a,":"); print a[n]}' | sort -nu | paste -sd ',' -)
        _ov_sys_ports=${_ov_sys_ports:-无}
    fi
    _ov_relay_status=""
    if [[ -f $is_relay_state_file ]]; then
        mapfile -t values < <(jq -r '.role // "", .landing_ip // .peer_ip // "", .landing_port // .listen_port // ""' "$is_relay_state_file")
        if [[ ${values[0]} == line ]]; then
            _ov_relay_status="${cyan}[中继]${none} 线路 → ${green}${values[1]}:${values[2]}${none}"
        elif [[ ${values[0]} == landing ]]; then
            _ov_relay_status="${cyan}[中继]${none} 落地 ← ${green}${values[1]}${none}   端口: ${green}${values[2]}${none}"
        fi
    fi
}

show_merged_config() {
    local output
    output=$("$is_core_bin" run -dump -config "$is_config_json" -confdir "$is_conf_dir" 2>&1) || {
        _fail "无法读取合并配置"
        printf '%s\n' "$output"
        return 1
    }
    if [[ ${1:-} != "输出(打印全部)" ]] && command -v less >/dev/null; then printf '%s\n' "$output" | less -R
    else printf '%s\n' "$output"; fi
}

misc_menu() {
    while :; do
        clear
        echo
        _line
        echo -e "  ${bold}${cyan}$is_core_name${none} ${gray}${is_core_ver}${none}  ${gray}|${none}  ${gray}Script ${is_sh_ver}${none}  ${gray}|${none}  ${is_core_status}"
        _line

        _section "杂项管理"
        _menu 1 "测试运行"
        _menu 2 "查看综合日志"
        _menu 3 "修改日志等级"
        _menu 4 "端口管理 (放行/关闭)"
        _menu 5 "更新"
        _menu 6 "卸载"

        echo
        echo -ne "  请选择 [${green}1-6${none}] [${red}0 返回主菜单${none}]: "
        read -r REPLY || return
        [[ "$REPLY" == "0" ]] && return

        case $REPLY in
        1)
            echo
            validate_config && _ok "配置校验通过"
            if prompt_confirm "是否检测网络与目标域名？" n; then
                _get_overview
                [[ -z $_ov_v4_sni ]] || diagnose_sni "$_ov_v4_sni" 4 1
                [[ -z $_ov_v6_sni ]] || diagnose_sni "$_ov_v6_sni" 6 1
                diagnose_domestic
            fi
            pause
            ;;
        2)
            follow_logs
            ;;
        3)
            echo
            ask list is_log_level "debug info warning error none" "\n  请选择日志等级:"
            [[ $REPLY == "0" ]] && continue
            config_transaction set_log_level "$is_log_level"
            ;;
        4)
            echo
            ask string p "  请输入端口操作 (例: o 443 开放, c 443 关闭) [0 返回]:"
            [[ $REPLY == "0" ]] && continue
            local action=$(echo $p | awk '{print $1}')
            local port=$(echo $p | awk '{print $2}')
            if [[ ($action == "o" || $action == "c") ]] && [[ $(is_test port $port) ]]; then
                if [[ $action == "o" ]]; then
                    open_port "$port" && _ok "已放行端口: $port"
                else
                    close_port "$port" && _ok "已关闭端口: $port"
                fi
            else
                _fail "无效的指令或端口格式"
            fi
            pause
            ;;
        5)
            echo
            is_tmp_list=("更新$is_core_name" "更新脚本" "更新geodata" "重装维护任务")
            ask list is_do_update null "\n  请选择更新:\n"
            [[ $REPLY == "0" ]] && continue
            case "$REPLY" in
                1|2) update "$REPLY" ;;
                3) update_geodata ;;
                4) install_maintenance force && migrate_installation ;;
            esac
            pause
            ;;
        6)
            if uninstall; then exit 0; fi
            ;;
        esac
    done
}

is_main_menu() {
    while :; do
        _reset_state
        _get_overview
        clear

        # ── header ──
        _line
        echo -e "  ${bold}${cyan}$is_core_name${none} ${gray}${is_core_ver}${none}  ${gray}|${none}  ${gray}Script ${is_sh_ver}${none}  ${gray}|${none}  ${is_core_status}"
        _line

        # ── config overview ──
        if [[ $_ov_port ]]; then
            local short_pbk="$_ov_pbk"
            if [[ ${#short_pbk} -gt 25 ]]; then
                short_pbk="${short_pbk:0:15}...${short_pbk:(-5)}"
            fi

            echo -e "  ${cyan}[基础]${none} 端口: ${green}$_ov_port${none}   分离: ${green}$_ov_route_mode${none}   日志: ${green}$_ov_log_level${none}   出站: ${green}$_ov_outbound_pref${none}"
            echo -e "  ${cyan}[UUID]${none} ${green}$_ov_uuid${none}"
            echo -e "  ${cyan}[ v4 ]${none} SNI: $_ov_v4_sni_status$_ov_v4_cdn_status${green}$_ov_v4_sni${none}   SIDs: ${green}$_ov_v4_sids${none}"
            echo -e "  ${cyan}[ v6 ]${none} SNI: $_ov_v6_sni_status$_ov_v6_cdn_status${green}$_ov_v6_sni${none}   SIDs: ${green}$_ov_v6_sids${none}"
            echo -e "  ${cyan}[高级]${none} 路径: ${green}$_ov_path${none}   公钥: ${green}$short_pbk${none}"
            echo -e "  ${cyan}[状态]${none} GFW放行: $_ov_ip_blocked   防火墙: ${green}$_ov_fw_ports${none}   占用: ${green}$_ov_sys_ports${none}"
            echo -e "  $_ov_relay_status"
        else
            echo -e "  ${gray}暂无配置${none}"
        fi
        _line

        # ── menu items ──
        _section "节点管理"
        _menu 1 "更改配置"
        _menu 2 "查看客户端配置"
        _menu 3 "查看完整服务端配置"
        _menu 4 "线路 / 落地互联"

        _section "运行控制"
        _menu 5 "启动 / 停止 / 重启"
        _menu 6 "查看运行状态"

        _section "杂项"
        _menu 7 "杂项管理 (包含日志/更新等)"

        if [[ $_ov_ip_warning || $_ov_sni_warning || $_ov_cdn_warning || $_ov_relay_warn ]]; then
            echo
            [[ $_ov_ip_warning ]] && echo -ne "${red}${_ov_ip_warning}${none}"
            [[ $_ov_sni_warning ]] && echo -ne "${red}${_ov_sni_warning}${none}"
            [[ $_ov_cdn_warning ]] && echo -ne "${red}${_ov_cdn_warning}${none}"
            [[ $_ov_relay_warn ]] && echo -ne "${red}${_ov_relay_warn}${none}"
        fi

        echo
        echo -ne "  请选择 [${green}1-7${none}] [${red}0 退出${none}]: "
        read -r REPLY || return
        [[ "$REPLY" == "0" ]] && return
        case $REPLY in
        1)
            change
            [[ $REPLY == "0" ]] && continue
            pause
            ;;
        2)
            info
            [[ $REPLY == "0" ]] && continue
            pause
            ;;
        3)
            echo
            ask list is_view_mode "预览(支持滚动) 输出(打印全部)" "\n  请选择查看方式:"
            [[ $REPLY == "0" ]] && continue
            echo
            _step "完整服务端配置如下 (自动合并 config.json 及独立节点配置):"
            echo
            show_merged_config "$is_view_mode"
            pause
            ;;
        4)
            relay_menu
            ;;
        5)
            echo
            ask list is_do_manage "启动 停止 重启"
            [[ $REPLY == "0" ]] && continue
            manage "$REPLY" && _ok "执行操作: $is_do_manage"
            ;;
        6)
            echo
            systemctl status $is_core -l --no-pager
            echo
            pause
            ;;
        7)
            misc_menu
            ;;
        esac
    done
}
