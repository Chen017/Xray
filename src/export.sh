#!/bin/bash

load_node_info() {
    local -a values
    is_json_str=$(cat "$is_conf_dir/$is_config_file") || return 1
    mapfile -t values < <(jq -r '
        .inbounds[0] as $v4 | .inbounds[1] as $v6 | .inbounds[2] as $xh |
        $v4.protocol, $v4.port, $v4.settings.clients[0].id,
        ($v4.streamSettings.realitySettings.serverNames[0] // ""),
        ($v6.streamSettings.realitySettings.serverNames[0] // ""),
        ($v4.streamSettings.realitySettings.privateKey // ""),
        ($v4.streamSettings.realitySettings.publicKey // ""),
        ($v4.streamSettings.realitySettings.shortIds // [""] | tojson),
        ($v6.streamSettings.realitySettings.shortIds // [""] | tojson),
        ($xh.streamSettings.xhttpSettings.path // "/")' <<< "$is_json_str")
    (( ${#values[@]} == 10 )) || { _fail "节点配置结构无法识别"; return 1; }
    is_protocol=${values[0]}; port=${values[1]}; uuid=${values[2]}
    v4_sni=${values[3]}; v6_sni=${values[4]}
    is_private_key=${values[5]}; is_public_key=${values[6]}
    v4_short_ids=${values[7]}; v6_short_ids=${values[8]}; v4_path=${values[9]}; v6_path=$v4_path
    if [[ -z "$is_public_key" ]]; then
        is_public_key=$("$is_core_bin" x25519 -i "$is_private_key" 2>/dev/null |
            awk -F ': *' '/^(Public key|PublicKey|Password( \(PublicKey\))?):/ {print $2; exit}')
    fi
    net=reality
    is_reality=1
    is_config_name=$is_config_file
}

# Retain client reuse settings explicitly: Mihomo has no Xray-like XMUX defaults.
client_xhttp() {
    local down="${1:-false}"
    jq -c --argjson down "$down" '
        .inbounds[] | select(.streamSettings.network == "xhttp") | .streamSettings.xhttpSettings |
        with_entries(select(.key as $k | ["path","headers","xPaddingBytes","xPaddingObfsMode","xPaddingPlacement",
            "xPaddingMethod","xPaddingKey","xPaddingHeader","sessionPlacement","sessionKey","sessionTable",
            "sessionLength","seqPlacement","seqKey","uplinkDataPlacement","uplinkDataKey","uplinkChunkSize"] | index($k))) |
        .mode = "stream-up" | .noGRPCHeader = true | .uplinkHTTPMethod = "PUT" |
        .xmux = (if $down then {maxConcurrency:"8-16",cMaxReuseTimes:0,hMaxRequestTimes:"300-600",hMaxReusableSecs:"2400-3600",hKeepAlivePeriod:0}
            else {maxConcurrency:"16-32",cMaxReuseTimes:0,hMaxRequestTimes:"600-900",hMaxReusableSecs:"1800-3000",hKeepAlivePeriod:0} end)
    ' <<< "$is_json_str"
}

mihomo_node_json() {
    local mode="$1" up_ip="$2" up_sni="$3" up_sid="$4" down_ip="${5:-}" down_sni="${6:-}" down_sid="${7:-}"
    local extra down_extra
    extra=$(client_xhttp) && down_extra=$(client_xhttp true) || return 1
    jq -n --arg mode "$mode" --arg up "$up_ip" --arg sni "$up_sni" --arg sid "$up_sid" \
        --arg down "$down_ip" --arg dsni "$down_sni" --arg dsid "$down_sid" \
        --arg uuid "$active_uuid" --arg pk "$is_public_key" --arg name "${is_config_name} · ${mode} · ${outbound_mode:-direct}" \
        --argjson port "$port" --argjson extra "$extra" --argjson de "$down_extra" '
        def reuse: {"max-concurrency":.maxConcurrency,"c-max-reuse-times":(.cMaxReuseTimes|tostring),
            "h-max-request-times":.hMaxRequestTimes,"h-max-reusable-secs":.hMaxReusableSecs,"h-keep-alive-period":.hKeepAlivePeriod};
        def xhttp: with_entries(.key |= (
            if . == "noGRPCHeader" then "no-grpc-header"
            elif . == "uplinkHTTPMethod" then "uplink-http-method"
            else gsub("(?<c>[A-Z])"; "-" + (.c|ascii_downcase)) end)) |
            del(.xmux) | .["reuse-settings"] = ($extra.xmux | reuse);
        {name:$name,type:"vless",server:$up,port:$port,uuid:$uuid,network:"tcp",tls:true,udp:true,tfo:true,mptcp:true,
            "packet-encoding":"xudp",encryption:"none",servername:$sni,"client-fingerprint":"chrome",
            "reality-opts":{"public-key":$pk,"short-id":$sid}} |
        if $mode == "vision" then .flow = "xtls-rprx-vision" else
            .network = "xhttp" | .alpn = ["h2"] | .["xhttp-opts"] = ($extra | xhttp | .host = $sni) |
            if $mode == "split" then
                .["xhttp-opts"]["download-settings"] = {
                    server:$down,port:$port,tls:true,alpn:["h2"],servername:$dsni,"client-fingerprint":"firefox",
                    "reality-opts":{"public-key":$pk,"short-id":$dsid},host:$dsni,path:$de.path,
                    "reuse-settings":($de.xmux|reuse)
                }
            else . end
        end'
}

render_mihomo() {
    jq -r '
        def indent($n): " " * $n;
        def mapping($n): to_entries[] |
            if (.value | type) == "object" then
                indent($n) + .key + ":", (.value | mapping($n+2))
            else indent($n) + .key + ": " + (.value | tojson) end;
        "- name: " + (.name | tojson), (del(.name) | mapping(2))'
}

export_vless_link() {
    local mode="$1" addr="$2" sni="$3" sid="$4" down="${5:-}" dsni="${6:-}" dsid="${7:-}"
    local extra query
    extra=$(client_xhttp) || return 1
    if [[ $mode == split ]]; then
        local down_extra
        down_extra=$(client_xhttp true) || return 1
        extra=$(jq -c --arg addr "$down" --arg sni "$dsni" --arg sid "$dsid" --arg pk "$is_public_key" \
            --argjson port "$port" --argjson de "$down_extra" '
            .downloadSettings={address:$addr,port:$port,network:"xhttp",security:"reality",
                realitySettings:{fingerprint:"firefox",serverName:$sni,publicKey:$pk,shortId:$sid},
                xhttpSettings:($de + {host:$sni})}' <<< "$extra") || return 1
    fi
    query=$(jq -nr --arg mode "$mode" --arg sni "$sni" --arg sid "$sid" --arg pk "$is_public_key" \
        --arg path "$v4_path" --arg extra "$extra" '
        {encryption:"none",security:"reality",sni:$sni,fp:"chrome",pbk:$pk,sid:$sid} +
        (if $mode == "vision" then {flow:"xtls-rprx-vision",type:"tcp"}
         else {type:"xhttp",host:$sni,path:$path,mode:"stream-up",extra:$extra} end) |
        to_entries | map((.key|@uri)+"="+(.value|@uri)) | join("&")') || return 1
    [[ $addr != *:* ]] || addr="[$addr]"
    printf 'vless://%s@%s:%s?%s#%s\n' "$active_uuid" "$addr" "$port" "$query" "Xray-${mode}-${outbound_mode:-direct}"
}

info() {
    is_can_change=(0 1 2 3 4 5 6 7 8 9 10)
    get info || return 1
    [[ ! $is_dont_show_info ]] || return 0
    [[ -n "$is_public_key" ]] || { _fail "无法读取或推导 REALITY 公钥，请检查内核与密钥"; return 1; }
    get addr || return 1
    get_ipv6 || true
    local v4_ip="$is_addr" v6_ip="${ipv6:-}" mode up_ip up_sni up_sid down_ip down_sni down_sid
    v4_ip=${v4_ip#[}; v4_ip=${v4_ip%]}
    [[ $v4_ip != *:* ]] || { v6_ip=$v4_ip; v4_ip=""; }
    local active_uuid="$uuid" outbound_mode=direct sid4 sid6
    sid4=$(jq -r '.[0] // ""' <<< "$v4_short_ids")
    sid6=$(jq -r '.[1] // .[0] // ""' <<< "$v6_short_ids")
    if [[ $(relay_get_role) == line ]]; then
        ask list outlet "本机直出 经落地($(jq -r .landing_ip "$is_relay_state_file"))" "\n  请选择出口:"
        [[ $REPLY != 0 ]] || return
        if [[ $REPLY == 2 ]]; then
            active_uuid=$(jq -er '.client_uuid' "$is_relay_state_file") || return 1
            outbound_mode=landing
        fi
    fi
    echo
    ask list scheme "XHTTP双栈分离 XHTTP单栈 仅VisionReality" "\n  请选择部署模式:"
    [[ $REPLY != 0 ]] || return
    case "$REPLY" in 1) mode=split ;; 2) mode=single ;; 3) mode=vision ;; esac
    if [[ $mode == split ]]; then
        [[ -n "$v4_ip" && -n "$v6_ip" ]] || { _fail "双栈分离需要公网 IPv4 和 IPv6，请选择单栈方案"; return 1; }
        up_ip=$v4_ip; up_sni=$v4_sni; up_sid=$sid4
        down_ip=$v6_ip; down_sni=$v6_sni; down_sid=$sid6
        if [[ -f "$is_conf_dir/is_v6_uplink" ]]; then
            up_ip=$v6_ip; up_sni=$v6_sni; up_sid=$sid6
            down_ip=$v4_ip; down_sni=$v4_sni; down_sid=$sid4
        fi
    else
        ask list family "v4-SNI($v4_sni) v6-SNI($v6_sni)" "\n  请选择 SNI:"
        [[ $REPLY != 0 ]] || return
        if [[ $REPLY == 1 ]]; then up_ip=$v4_ip; up_sni=$v4_sni; up_sid=$sid4
        else up_ip=$v6_ip; up_sni=$v6_sni; up_sid=$sid6; fi
        [[ -n "$up_ip" ]] || { _fail "未获取到所选地址，请使用另一栈或检查公网地址"; return 1; }
    fi
    ask list format "Mihomo配置 VLESS链接" "\n  请选择输出格式:"
    [[ $REPLY != 0 ]] || return
    if [[ $REPLY == 1 ]]; then
        mihomo_node_json "$mode" "$up_ip" "$up_sni" "$up_sid" "$down_ip" "$down_sni" "$down_sid" | render_mihomo
    else
        export_vless_link "$mode" "$up_ip" "$up_sni" "$up_sid" "$down_ip" "$down_sni" "$down_sid"
    fi
}
