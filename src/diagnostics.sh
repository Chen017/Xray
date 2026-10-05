#!/bin/bash

# Modules are sourced inside load(); ordinary declare would create function-local arrays.
declare -gA diagnostic_cache diagnostic_time

_detect_cdn() {
    local domain="$1" family="${2:-4}" ips="" first org count type=A
    [[ $family != 6 ]] || type=AAAA
    if command -v dig >/dev/null; then
        local ns
        for ns in 1.1.1.1 8.8.8.8; do
            ips+=$(dig +short +time=2 +tries=1 "$type" "$domain" "@$ns" 2>/dev/null)
            ips+=$'\n'
        done
        ips=$(printf '%s' "$ips" | grep -E '^([0-9]+\.){3}[0-9]+$|^[0-9a-fA-F:]+:[0-9a-fA-F:]*$' | sort -u)
    else
        ips=$(timeout 3 getent "ahostsv$family" "$domain" 2>/dev/null | awk '{print $1}' | sort -u)
    fi
    [[ -n "$ips" ]] || { echo '归属：无法判断（DNS 无结果或查询失败）'; return; }
    count=$(printf '%s\n' "$ips" | wc -l)
    first=${ips%%$'\n'*}
    org=$(curl --noproxy '*' -fsS --max-time 3 "https://ipinfo.io/$first/org" 2>/dev/null) || org=""
    if [[ "$org" =~ $CDN_BLACKLIST_STRICT ]]; then
        printf '归属：疑似 CDN（%s），建议核对目标站点\n' "$org"
    elif [[ -n "$org" ]]; then
        printf '归属：%s（不能仅凭 ASN 排除 CDN）\n' "$org"
    else
        echo '归属：查询失败，无法判断 CDN'
    fi
    if (( count > 1 )); then
        printf '解析：%s 个地址，可能是负载均衡 / GeoDNS，不能据此认定 CDN\n' "$count"
    fi
}

diagnose_sni() {
    local domain="$1" family="$2" refresh="${3:-0}" key="$2:$1" now result output rc=0
    now=$(date +%s)
    if [[ $refresh == 0 && -n ${diagnostic_cache[$key]:-} ]] && (( now - ${diagnostic_time[$key]:-0} < 300 )); then
        printf '%s\n' "${diagnostic_cache[$key]}"
        return
    fi
    [[ $(is_test domain "$domain") ]] || { _fail "无效 SNI 域名"; return 1; }
    local -a http_options=()
    if curl --version | grep -q HTTP2; then http_options=(--http2); fi
    output=$(curl --noproxy '*' "-$family" --silent --show-error --connect-timeout 3 --max-time 5 \
        --tlsv1.3 --tls-max 1.3 "${http_options[@]}" -o /dev/null -w '%{http_version}' "https://$domain" 2>&1) || rc=$?
    if (( rc )); then
        result="IPv$family $domain：本机测试未通过（$output）；请同时检查本机出站与 DNS"
    elif (( ${#http_options[@]} == 0 )); then
        result="IPv$family $domain：证书与 TLS 1.3 通过；本机 curl 无 HTTP/2 能力，h2 未验证"
    elif [[ $output == 2 || $output == 2.0 ]]; then
        result="IPv$family $domain：证书、TLS 1.3 与 h2 通过"
    else
        result="IPv$family $domain：证书与 TLS 1.3 通过，协商结果 HTTP/$output（未通过 h2 检查）"
    fi
    result+=$'\n'
    result+=$(_detect_cdn "$domain" "$family")
    diagnostic_cache[$key]="$result"
    diagnostic_time[$key]="$now"
    printf '%s\n' "$result"
}

diagnose_domestic() {
    local family host reachable=0
    _info "检测服务器到国内节点的出站连通性；结果不能证明客户端到本机是否被阻断。"
    for family in 4 6; do
        reachable=0
        for host in sh-cm-dualstack.ip.zstaticcdn.com sh-cu-dualstack.ip.zstaticcdn.com sh-ct-dualstack.ip.zstaticcdn.com; do
            if curl --noproxy '*' "-$family" -sS --connect-timeout 2 --max-time 2 -o /dev/null "http://$host/" 2>/dev/null; then
                reachable=1
                break
            fi
        done
        if (( reachable )); then _ok "IPv$family：至少一个测试节点可达"
        else _info "IPv$family：所选测试节点未连通，原因无法仅凭此测试确定"; fi
    done
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
