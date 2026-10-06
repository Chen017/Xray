#!/bin/bash

# Connectivity and target checks restored from v2.5.4 (61744f3).

_detect_cdn() {
    local domain="$1"
    local dns_servers=("8.8.8.8" "1.1.1.1" "208.67.222.222" "9.9.9.9")
    local all_ips=""

    if command -v dig &>/dev/null; then
        # 优先使用 dig
        for ns in "${dns_servers[@]}"; do
            local ips=$(dig +short +time=2 +tries=1 A "$domain" @"$ns" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
            [[ -n "$ips" ]] && all_ips+="$ips"$'\n'
        done
    elif command -v nslookup &>/dev/null; then
        # 降级到 nslookup
        for ns in "${dns_servers[@]}"; do
            local ips=$(nslookup "$domain" "$ns" 2>/dev/null | awk '/^Address:/ && !/#/ {print $2}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
            [[ -n "$ips" ]] && all_ips+="$ips"$'\n'
        done
    else
        # fallback: getent + ipinfo（使用缩减后的纯 CDN 黑名单）
        local first_ip=$(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | grep -v ':' | head -1)
        [[ -z "$first_ip" ]] && first_ip=$(getent ahosts "$domain" 2>/dev/null | awk '{print $1}' | head -1)
        if [[ -n "$first_ip" ]]; then
            local org=$(curl -s --max-time 5 "https://ipinfo.io/$first_ip/org" 2>/dev/null | tr -d '\n')
            if [[ -n "$org" ]]; then
                local cdn_name=$(echo "$org" | grep -ioE "$CDN_BLACKLIST_STRICT" | head -1)
                if [[ -n "$cdn_name" ]]; then
                    echo "CDN:$cdn_name|$org"
                    return
                fi
            fi
        fi
        echo "CDN_OK"
        return
    fi

    # 去重统计唯一 IP 数
    local unique_count=$(echo "$all_ips" | sed '/^$/d' | sort -u | wc -l)
    if [[ $unique_count -gt 1 ]]; then
        local ip_list=$(echo "$all_ips" | sed '/^$/d' | sort -u | head -5 | tr '\n' ',' | sed 's/,$//')
        echo "CDN:Anycast/GeoDNS|多 DNS 解析到 ${unique_count} 个不同 IP ($ip_list)"
    else
        echo "CDN_OK"
    fi
}

_check_ip_blocked() {
    if [[ $_ov_ip_blocked ]]; then
        return
    fi
    _ov_ip_blocked="检测中..."
    _ov_ip_warning=""
    local check_urls=(
        "sh-cm-dualstack.ip.zstaticcdn.com/80"
        "sh-cu-dualstack.ip.zstaticcdn.com/80"
        "sh-ct-dualstack.ip.zstaticcdn.com/80"
    )
    local is_blocked=1
    for url in "${check_urls[@]}"; do
        if timeout 2 bash -c "echo > /dev/tcp/$url" &>/dev/null; then
            is_blocked=0
            break
        fi
    done
    if [[ $is_blocked == 0 ]]; then
        _ov_ip_blocked="${green}✓${none} "
    else
        _ov_ip_blocked="${red}✗${none} "
        _ov_ip_warning="  [警告] 当前服务器 IP 的部分国内测速节点超时，可能已被 GFW 阻断！\n"
    fi
}

_check_sni_status() {
    if [[ $_ov_sni_checked ]]; then
        return
    fi
    _ov_sni_checked=1

    _ov_v4_sni_status=""
    _ov_v6_sni_status=""
    _ov_v4_cdn_status=""
    _ov_v6_cdn_status=""
    _ov_sni_warning=""
    _ov_cdn_warning=""

    local v4_tmp="/tmp/.v4_sni_res_$$"
    local v6_tmp="/tmp/.v6_sni_res_$$"

    local pid_v4=""
    local pid_v6=""

    # 每个子 shell 同时检测 TLS 和 CDN，输出格式: TLS_OK|CDN_OK 或 TLS_FAIL|CDN:名称|归属
    if [[ $_ov_v4_sni ]]; then
        (
            # ── TLS 检测 ──
            tls_res="TLS_FAIL"
            res=$(curl -s -v -m 3 -A "Mozilla/5.0" -o /dev/null "https://$_ov_v4_sni" 2>&1)
            if [[ $? == 0 ]] && echo "$res" | grep -qE "TLSv1.3"; then
                tls_res="TLS_OK"
            fi
            # ── CDN 检测（多 DNS 视角）──
            cdn_res=$(_detect_cdn "$_ov_v4_sni")
            echo "${tls_res}|${cdn_res}"
        ) > "$v4_tmp" &
        pid_v4=$!
    fi

    if [[ $_ov_v6_sni ]]; then
        (
            tls_res="TLS_FAIL"
            res=$(curl -s -v -m 3 -A "Mozilla/5.0" -o /dev/null "https://$_ov_v6_sni" 2>&1)
            if [[ $? == 0 ]] && echo "$res" | grep -qE "TLSv1.3"; then
                tls_res="TLS_OK"
            fi
            # ── CDN 检测（多 DNS 视角）──
            cdn_res=$(_detect_cdn "$_ov_v6_sni")
            echo "${tls_res}|${cdn_res}"
        ) > "$v6_tmp" &
        pid_v6=$!
    fi

    [[ $pid_v4 ]] && wait $pid_v4
    [[ $pid_v6 ]] && wait $pid_v6

    # ── 解析 v4 结果 ──
    if [[ $_ov_v4_sni && -f $v4_tmp ]]; then
        local v4_raw=$(cat "$v4_tmp")
        local v4_tls=${v4_raw%%|*}
        local v4_cdn=${v4_raw#*|}
        # TLS 状态
        if [[ "$v4_tls" == "TLS_OK" ]]; then
            _ov_v4_sni_status="${green}✓${none} "
        else
            _ov_v4_sni_status="${red}✗${none} "
            _ov_sni_warning+="  [警告] v4 伪装域名 ($_ov_v4_sni) 证书不受信、无法连通或不支持 TLS 1.3 / h2，强烈建议更换！\n"
        fi
        # CDN 状态
        case "$v4_cdn" in
        CDN:*)
            local v4_cdn_name=$(echo "$v4_cdn" | cut -d: -f2 | cut -d'|' -f1)
            local v4_cdn_org=$(echo "$v4_cdn" | cut -d'|' -f2)
            _ov_v4_cdn_status="${red}CDN${none} "
            _ov_cdn_warning+="  [警告] v4 域名 ($_ov_v4_sni) 挂了 CDN（$v4_cdn_name: $v4_cdn_org），请更换域名！\n"
            ;;
        esac
        rm -f "$v4_tmp"
    fi

    # ── 解析 v6 结果 ──
    if [[ $_ov_v6_sni && -f $v6_tmp ]]; then
        local v6_raw=$(cat "$v6_tmp")
        local v6_tls=${v6_raw%%|*}
        local v6_cdn=${v6_raw#*|}
        # TLS 状态
        if [[ "$v6_tls" == "TLS_OK" ]]; then
            _ov_v6_sni_status="${green}✓${none} "
        else
            _ov_v6_sni_status="${red}✗${none} "
            _ov_sni_warning+="  [警告] v6 伪装域名 ($_ov_v6_sni) 证书不受信、无法连通或不支持 TLS 1.3 / h2，强烈建议更换！\n"
        fi
        # CDN 状态
        case "$v6_cdn" in
        CDN:*)
            local v6_cdn_name=$(echo "$v6_cdn" | cut -d: -f2 | cut -d'|' -f1)
            local v6_cdn_org=$(echo "$v6_cdn" | cut -d'|' -f2)
            _ov_v6_cdn_status="${red}CDN${none} "
            _ov_cdn_warning+="  [警告] v6 域名 ($_ov_v6_sni) 挂了 CDN（$v6_cdn_name: $v6_cdn_org），请更换域名！\n"
            ;;
        esac
        rm -f "$v6_tmp"
    fi
}

follow_logs() (
    local pid
    trap '[[ -z ${pid:-} ]] || { kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; }; :' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    _info "Enter 返回，Ctrl+C 退出日志查看"
    tail -F "$is_log_dir/access.log" "$is_log_dir/error.log" &
    pid=$!
    read -r _ || true
)
