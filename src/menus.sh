#!/bin/bash

_reset_state() {
    unset is_protocol is_config_file is_config_name is_json_str net is_reality port uuid
    unset is_private_key is_public_key v4_sni v6_sni v4_path v6_path v4_short_ids v6_short_ids
    unset is_change is_change_id is_dont_show_info is_auto_get_config is_new_json is_conf_dir_empty
    unset is_addr is_core_stop is_new_protocol is_short_ids is_new_v4_sni is_new_v6_sni is_servername
    unset is_default_arg is_new_v4_path is_new_uuid is_new_port
    if service_active; then is_core_status="${green}● 运行中${none}"
    else is_core_status="${red}● 已停止${none}"; is_core_stop=1; fi
    is_core_status_short=$is_core_status
}

_get_overview() {
    local first values
    _ov_port=""; _ov_v4_sni=""; _ov_v6_sni=""
    first=$(list_managed_node_configs | head -1)
    if [[ -n "$first" ]]; then
        mapfile -t values < <(jq -r '.inbounds[0].port // "",
            .inbounds[0].streamSettings.realitySettings.serverNames[0] // "",
            .inbounds[1].streamSettings.realitySettings.serverNames[0] // ""' "$is_conf_dir/$first")
        _ov_port=${values[0]:-}; _ov_v4_sni=${values[1]:-}; _ov_v6_sni=${values[2]:-}
    fi
    _ov_route_mode='v4上行/v6下行'
    [[ ! -f "$is_conf_dir/is_v6_uplink" ]] || _ov_route_mode='v6上行/v4下行'
    _ov_outbound_pref=$(outbound_label "$(outbound_strategy)")
    _ov_log_level=$(jq -r '.log.loglevel // "未知"' "$is_config_json" 2>/dev/null)
    _ov_relay_status='未配置'
    if [[ -f "$is_relay_state_file" ]]; then
        _ov_relay_status=$(jq -r 'if .role == "line" then "线路 → " + .landing_ip + ":" + (.landing_port|tostring)
            elif .role == "landing" then "落地 ← " + .peer_ip + "（TCP " + (.listen_port|tostring) + "）" else "状态无法识别" end' "$is_relay_state_file")
    fi
}

show_merged_config() {
    local output
    output=$("$is_core_bin" run -dump -config "$is_config_json" -confdir "$is_conf_dir" 2>&1) || {
        _fail "无法读取合并配置"
        printf '%s\n' "$output"
        return 1
    }
    if command -v less >/dev/null; then printf '%s\n' "$output" | less -R
    else printf '%s\n' "$output"; fi
}

node_menu() {
    local choice
    while :; do
        _section "节点配置"
        _menu 1 修改节点参数
        _menu 2 查看节点详情
        _menu 3 查看完整服务端配置
        prompt_input "选择操作（0 返回）" choice
        [[ $choice != 0 && -n $choice ]] || return
        _reset_state
        case "$choice" in
            1) change ;;
            2)
                get info || return 1
                _kv 配置 "$is_config_file"
                _kv 端口 "$port"
                _kv UUID "$uuid"
                _kv IPv4目标 "$v4_sni"
                _kv IPv6目标 "$v6_sni"
                _kv IPv4ShortID "$v4_short_ids"
                _kv IPv6ShortID "$v6_short_ids"
                _kv XHTTP路径 "$v4_path"
                _kv REALITY公钥 "$is_public_key"
                ;;
            3) show_merged_config ;;
            *) _fail "无效操作" ;;
        esac
        pause
    done
}

service_menu() {
    local choice
    while :; do
        _section "服务管理"
        _menu 1 启动
        _menu 2 停止
        _menu 3 重启
        _menu 4 查看运行状态
        prompt_input "选择操作（0 返回）" choice
        [[ $choice != 0 && -n $choice ]] || return
        case "$choice" in
            1|2|3) manage "$choice" && _ok "服务操作成功" ;;
            4) systemctl status "$is_core" -l --no-pager ;;
            *) _fail "无效操作" ;;
        esac
        pause
    done
}

diagnostics_menu() {
    local choice level refresh
    while :; do
        _section "日志与诊断"
        _menu 1 检查配置合法性
        _menu 2 检查网络与目标域名
        _menu 3 查看综合日志
        _menu 4 修改日志等级
        _menu 5 查看中继组件与连通性
        prompt_input "选择操作（0 返回）" choice
        [[ $choice != 0 && -n $choice ]] || return
        case "$choice" in
            1) validate_config && _ok "配置校验通过；未启动或重启服务" ;;
            2)
                _get_overview
                ask list refresh "使用五分钟内的缓存 强制重新检测" "\n  请选择检测方式:"
                [[ $REPLY != 0 ]] || continue
                refresh=$((REPLY-1))
                [[ -z "$_ov_v4_sni" ]] || diagnose_sni "$_ov_v4_sni" 4 "$refresh"
                [[ -z "$_ov_v6_sni" ]] || diagnose_sni "$_ov_v6_sni" 6 "$refresh"
                diagnose_domestic
                ;;
            3) follow_logs ;;
            4)
                ask list level "debug info warning error none" "\n  请选择日志等级:"
                [[ $REPLY != 0 ]] || continue
                config_transaction set_log_level "$level"
                ;;
            5)
                case "$(relay_get_role)" in
                    line) relay_view_info_line; relay_test ;;
                    landing) relay_view_info_landing; validate_config ;;
                    *) _info "未配置中继" ;;
                esac
                ;;
            *) _fail "无效操作" ;;
        esac
        pause
    done
}

maintenance_menu() {
    local choice p
    while :; do
        _section "更新与维护"
        _menu 1 更新Xray内核
        _menu 2 更新管理脚本
        _menu 3 更新geodata
        _menu 4 管理脚本防火墙端口
        _menu 5 重试安装维护任务
        _menu 6 卸载
        prompt_input "选择操作（0 返回）" choice
        [[ $choice != 0 && -n $choice ]] || return
        case "$choice" in
            1|2) update "$choice" ;;
            3) update_geodata ;;
            4)
                _info "只管理脚本自己的规则，系统及云平台防火墙仍需分别检查。"
                _info "关闭正在使用的节点端口会中断客户端连接。"
                if command -v ss >/dev/null; then
                    _info "系统监听端口："
                    ss -tuln
                fi
                prompt_input "端口号（0 返回）" p
                [[ $p != 0 ]] || continue
                ask list action "放行 关闭" "\n  请选择端口操作:"
                [[ $REPLY != 0 ]] || continue
                if [[ $REPLY == 1 ]]; then open_port "$p"; else close_port "$p"; fi
                ;;
            5) install_maintenance force && migrate_installation ;;
            6) if uninstall; then exit 0; fi ;;
            *) _fail "无效操作" ;;
        esac
        pause
    done
}

is_main_menu() {
    local choice
    while :; do
        _reset_state
        _get_overview
        clear
        _line
        printf '  %b\n' "$is_core_name $is_core_ver | Script $is_sh_ver | $is_core_status"
        _line
        _kv 节点端口 "${_ov_port:-暂无配置}"
        _kv 客户端分离 "$_ov_route_mode"
        _kv 出站策略 "$_ov_outbound_pref"
        _kv 中继状态 "$_ov_relay_status"
        _kv 日志等级 "$_ov_log_level"
        _line
        _menu 1 导出客户端配置
        _menu 2 修改节点配置与查看详情
        _menu 3 路由与分流
        _menu 4 中转/落地管理
        _menu 5 服务管理
        _menu 6 日志与诊断
        _menu 7 更新与维护
        prompt_input "选择操作（0 退出）" choice
        [[ $choice != 0 && -n $choice ]] || return
        case "$choice" in
            1) info; pause ;;
            2) node_menu ;;
            3) route_menu ;;
            4) relay_menu ;;
            5) service_menu ;;
            6) diagnostics_menu ;;
            7) maintenance_menu ;;
            *) _fail "无效操作"; pause ;;
        esac
    done
}
