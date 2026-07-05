#!/bin/bash

change_list=(
    "更改端口"
    "更改 xhttp 路径"
    "重新生成 UUID"
    "重新生成密钥"
    "更改 v4 目标域名 (SNI/Dest)"
    "更改 v6 目标域名 (SNI/Dest)"
    "重新生成 v4 Short IDs"
    "重新生成 v6 Short IDs"
    "切换 v6only"
    "切换分离类型"
)
servername_list=(
    www.magicardshop.jp
    dova-s.jp
    hf-mirror.com
    hahuma.com
    dodoshort.com
)

msg() {
    echo -e "$@"
}

msg_ul() {
    echo -e "\e[4m$@\e[0m"
}

get_uuid() {
    tmp_uuid=$(cat /proc/sys/kernel/random/uuid)
}

get_short_ids() {
    is_short_id_8=$(openssl rand -hex 4)
    is_short_id_16=$(openssl rand -hex 8)
    is_short_ids='["","'$is_short_id_8'","'$is_short_id_16'"]'
}

get_ip() {
    [[ $ip || $is_dont_get_ip || $is_get_ip_done ]] && return
    export is_get_ip_done=1
    
    local is_local_ip=$(ip route get 1.1.1.1 2>/dev/null | grep -Eo 'src [0-9.]+' | awk '{print $2}')
    if [[ $is_local_ip ]] && ! echo "$is_local_ip" | grep -qE '^(10|127|192\.168|172\.(1[6-9]|2[0-9]|3[0-1])|100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7]))\.'; then
        export ip=$is_local_ip
    else
        export "$(_wget -T 2 -4 -qO- https://one.one.one.one/cdn-cgi/trace | grep ip=)" &>/dev/null
    fi
    
    [[ ! $ip ]] && export "$(_wget -T 2 -6 -qO- https://one.one.one.one/cdn-cgi/trace | grep ip=)" &>/dev/null
    [[ ! $ip ]] && {
        err "获取服务器 IP 失败"
    }
}

get_ipv6() {
    [[ $ipv6 || $is_dont_get_ip || $is_get_ipv6_done ]] && return
    export is_get_ipv6_done=1
    
    local is_local_ipv6=$(ip route get 2606:4700:4700::1111 2>/dev/null | grep -Eo 'src [0-9a-fA-F:]+' | awk '{print $2}')
    if [[ $is_local_ipv6 ]] && ! echo "$is_local_ipv6" | grep -qE '^(fe80|fd|fc|::1)'; then
        export ipv6=$is_local_ipv6
    else
        export "ipv6=$(_wget -T 2 -6 -qO- https://one.one.one.one/cdn-cgi/trace | grep ip= | cut -d= -f2)" &>/dev/null
    fi
}

get_port() {
    tmp_port=443
    if [[ $(is_test port_used 443) ]]; then
        _yellow "  [警告] 标准 HTTPS 端口 (443) 已被占用，回落至备用端口 (8443)"
        tmp_port=8443
        if [[ $(is_test port_used 8443) ]]; then
            err "标准端口 (443) 与备用端口 (8443) 均被占用!\n         为保障协议伪装的安全性和隐蔽性，本脚本仅支持这两个端口。\n         请释放端口后再试。"
        fi
    fi
}

get_pbk() {
    is_tmp_pbk=($($is_core_bin x25519 | sed 's/.*://'))
    is_private_key=${is_tmp_pbk[0]}
    is_public_key=${is_tmp_pbk[1]}
}

get_random_sni() {
    local len=${#servername_list[@]}
    local idx1=$((RANDOM % len))
    local idx2=$((RANDOM % len))
    while [[ $idx2 == $idx1 ]]; do
        idx2=$((RANDOM % len))
    done
    tmp_v4_sni=${servername_list[$idx1]}
    tmp_v6_sni=${servername_list[$idx2]}
}

show_list() {
    local i=0
    for v in "$@"; do
        ((i++))
        printf "  ${green}%2s)${none} %s\n" "$i" "$v"
    done
    echo
}

is_test() {
    case $1 in
    number)
        echo $2 | grep -E '^[1-9][0-9]?+$'
        ;;
    port)
        if [[ $(is_test number $2) ]]; then
            [[ $2 -le 65535 ]] && echo ok
        fi
        ;;
    port_used)
        [[ $(is_port_used $2) && ! $is_cant_test_port ]] && echo ok
        ;;
    domain)
        echo $2 | grep -E -i '^\w(\w|\-|\.)?+\.\w+$'
        ;;
    path)
        echo $2 | grep -E -i '^\/\w(\w|\-|\/)?+\w$'
        ;;
    uuid)
        echo $2 | grep -E -i '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
        ;;
    esac

}

is_port_used() {
    if [[ $(type -P netstat) ]]; then
        [[ ! $is_used_port ]] && is_used_port="$(netstat -tunlp | sed -n 's/.*:\([0-9]\+\).*/\1/p' | sort -nu)"
        echo $is_used_port | sed 's/ /\n/g' | grep ^${1}$
        return
    fi
    if [[ $(type -P ss) ]]; then
        [[ ! $is_used_port ]] && is_used_port="$(ss -tunlp | sed -n 's/.*:\([0-9]\+\).*/\1/p' | sort -nu)"
        echo $is_used_port | sed 's/ /\n/g' | grep ^${1}$
        return
    fi
    is_cant_test_port=1
    _fail "无法检测端口是否可用"
    _info "请执行: $(_yellow "${cmd} update -y; ${cmd} install net-tools -y") 来修复此问题"
}

save_iptables() {
    if [[ $(type -P iptables-save) && -d /etc/iptables ]]; then
        iptables-save > /etc/iptables/rules.v4
        [[ $(type -P ip6tables-save) ]] && ip6tables-save > /etc/iptables/rules.v6
    elif [[ $(type -P netfilter-persistent) ]]; then
        netfilter-persistent save &>/dev/null
    fi
}

open_port() {
    local p=$1
    close_port $p
    if [[ $(type -P iptables) ]]; then
        iptables -I INPUT -p tcp --dport $p -j ACCEPT &>/dev/null
        iptables -I INPUT -p udp --dport $p -j ACCEPT &>/dev/null
    fi
    if [[ $(type -P ip6tables) ]]; then
        ip6tables -I INPUT -p tcp --dport $p -j ACCEPT &>/dev/null
        ip6tables -I INPUT -p udp --dport $p -j ACCEPT &>/dev/null
    fi
    save_iptables
}

close_port() {
    local p=$1
    if [[ $(type -P iptables) ]]; then
        while iptables -D INPUT -p tcp --dport $p -j ACCEPT &>/dev/null; do :; done
        while iptables -D INPUT -p udp --dport $p -j ACCEPT &>/dev/null; do :; done
    fi
    if [[ $(type -P ip6tables) ]]; then
        while ip6tables -D INPUT -p tcp --dport $p -j ACCEPT &>/dev/null; do :; done
        while ip6tables -D INPUT -p udp --dport $p -j ACCEPT &>/dev/null; do :; done
    fi
    save_iptables
}

# ask input a string or pick a option for list.
ask() {
    case $1 in
    set_change_list)
        is_tmp_list=()
        for v in ${is_can_change[@]}; do
            is_tmp_list+=("${change_list[$v]}")
        done
        is_opt_msg="\n  请选择更改:\n"
        is_ask_set=is_change_str
        is_opt_input_msg=$3
        ;;
    string)
        is_ask_set=$2
        is_opt_input_msg=$3
        ;;
    list)
        is_ask_set=$2
        [[ ! $is_tmp_list ]] && is_tmp_list=($3)
        is_opt_msg=$4
        is_opt_input_msg=$5
        ;;
    get_config_file)
        is_tmp_list=("${is_all_json[@]}")
        is_opt_msg="\n  请选择配置:\n"
        is_ask_set=is_config_file
        ;;
    esac
    msg $is_opt_msg
    [[ ! $is_opt_input_msg ]] && is_opt_input_msg="  请选择 [\e[91m1-${#is_tmp_list[@]}\e[0m] [0 返回]:"
    [[ $is_tmp_list ]] && show_list "${is_tmp_list[@]}"
    while :; do
        echo -ne "$is_opt_input_msg "
        read REPLY
        [[ $REPLY == "0" ]] && {
            unset is_opt_msg is_opt_input_msg is_tmp_list is_ask_result is_default_arg
            return
        }
        [[ ! $REPLY && $is_default_arg ]] && {
            [[ $is_default_arg != "empty_allowed" ]] && export $is_ask_set="$is_default_arg"
            break
        }
        if [[ ! $is_tmp_list ]]; then
            [[ $(grep port <<<$is_ask_set) ]] && {
                [[ ! $(is_test port "$REPLY") ]] && {
                    _fail "请输入正确的端口, 可选 (1-65535)"
                    continue
                }
                if [[ $(is_test port_used $REPLY) && $is_ask_set != 'door_port' ]]; then
                    _fail "无法使用 ($REPLY) 端口"
                    continue
                fi
            }
            [[ $(grep path <<<$is_ask_set) && ! $(is_test path "$REPLY") ]] && {
                [[ ! $tmp_uuid ]] && get_uuid
                _fail "请输入正确的路径, 例如: /$tmp_uuid"
                continue
            }
            [[ $(grep uuid <<<$is_ask_set) && ! $(is_test uuid "$REPLY") ]] && {
                [[ ! $tmp_uuid ]] && get_uuid
                _fail "请输入正确的 UUID, 例如: $tmp_uuid"
                continue
            }
            [[ $(grep ^y$ <<<$is_ask_set) ]] && {
                [[ $(grep -i ^y$ <<<"$REPLY") ]] && break
                _info "请输入 (y)"
                continue
            }
            [[ $REPLY ]] && export $is_ask_set=$REPLY && _ok "使用: ${!is_ask_set}" && break
        else
            [[ $(is_test number "$REPLY") ]] && is_ask_result=${is_tmp_list[$REPLY - 1]}
            [[ $is_ask_result ]] && export $is_ask_set="$is_ask_result" && _ok "选择: ${!is_ask_set}" && break
        fi

        _fail "输入有误，请重试"
    done
    unset is_opt_msg is_opt_input_msg is_tmp_list is_ask_result is_default_arg
}

# create file
create() {
    case $1 in
    server)
        get new
        
        is_config_name=${2}-${port}.json
        is_json_file=$is_conf_dir/$is_config_name
        
        [[ $is_test_json ]] && return # tmp test
        
        [[ $v6_only == 'true' ]] && is_v6only_str=',"v6only": true' || is_v6only_str=''

        # generate config
        is_new_json=$(cat <<EOF
{
    "inbounds": [
        {
            "tag": "public_${port}_v4",
            "listen": "0.0.0.0",
            "port": $port,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$uuid",
                        "flow": "xtls-rprx-vision",
                        "email": "vision-v4"
                    }
                ],
                "decryption": "none",
                "fallbacks": [
                    {
                        "dest": "@xhttp_inner"
                    }
                ]
            },
            "streamSettings": {
                "network": "raw",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "${v4_sni:-$is_servername}:443",
                    "serverNames": [
                        "${v4_sni:-$is_servername}"
                    ],
                    "privateKey": "$is_private_key",
                    "publicKey": "$is_public_key",
                    "shortIds": ${v4_short_ids:-$is_short_ids},
                    "maxTimeDiff": 60000,
                    "limitFallbackUpload": {
                        "afterBytes": 8192,
                        "bytesPerSec": 10240,
                        "burstBytesPerSec": 51200
                    },
                    "limitFallbackDownload": {
                        "afterBytes": 8192,
                        "bytesPerSec": 10240,
                        "burstBytesPerSec": 51200
                    }
                },
                "sockopt": {
                    "tcpFastOpen": true,
                    "tcpCongestion": "bbr"
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "routeOnly": true
            }
        },
        {
            "tag": "public_${port}_v6",
            "listen": "::",
            "port": $port,
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$uuid",
                        "flow": "xtls-rprx-vision",
                        "email": "vision-v6"
                    }
                ],
                "decryption": "none",
                "fallbacks": [
                    {
                        "dest": "@xhttp_inner"
                    }
                ]
            },
            "streamSettings": {
                "network": "raw",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "dest": "${v6_sni:-$is_servername}:443",
                    "serverNames": [
                        "${v6_sni:-$is_servername}"
                    ],
                    "privateKey": "$is_private_key",
                    "publicKey": "$is_public_key",
                    "shortIds": ${v6_short_ids:-$is_short_ids},
                    "maxTimeDiff": 60000,
                    "limitFallbackUpload": {
                        "afterBytes": 8192,
                        "bytesPerSec": 10240,
                        "burstBytesPerSec": 51200
                    },
                    "limitFallbackDownload": {
                        "afterBytes": 8192,
                        "bytesPerSec": 10240,
                        "burstBytesPerSec": 51200
                    }
                },
                "sockopt": {
                    "tcpFastOpen": true,
                    "tcpCongestion": "bbr"
                    $is_v6only_str
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "routeOnly": true
            }
        },
        {
            "tag": "local_xhttp_stream_up",
            "listen": "@xhttp_inner",
            "protocol": "vless",
            "settings": {
                "clients": [
                    {
                        "id": "$uuid",
                        "email": "xhttp-stream-up"
                    }
                ],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "xhttp",
                "security": "none",
                "xhttpSettings": {
                    "mode": "stream-up",
                    "host": "",
                    "path": "${v4_path:-/api/v3/updates}",
                    "uplinkHTTPMethod": "PUT",
                    "noGRPCHeader": false,
                    "noSSEHeader": false,
                    "xPaddingBytes": "100-1000",
                    "xPaddingObfsMode": true,
                    "xPaddingPlacement": "queryInHeader",
                    "xPaddingMethod": "tokenish",
                    "xPaddingKey": "x_padding",
                    "xPaddingHeader": "Referer",
                    "sessionPlacement": "path",
                    "seqPlacement": "path",
                    "scStreamUpServerSecs": "20-80",
                    "serverMaxHeaderBytes": 8192,
                    "xmux": {
                        "maxConcurrency": "16-32",
                        "cMaxReuseTimes": 0,
                        "hMaxRequestTimes": "600-900",
                        "hMaxReusableSecs": "1800-3000",
                        "hKeepAlivePeriod": 0
                    }
                }
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls", "quic"],
                "routeOnly": true
            }
        }
    ]
}
EOF
)
        # del old file
        [[ $is_config_file ]] && is_no_del_msg=1 && del $is_config_file
        
        # save json to file
        cat <<<$is_new_json >$is_json_file
        
        if [[ $is_new_install ]]; then
            echo
            _ok "VLESS-REALITY 节点基础配置生成完毕"
            _kv "监听端口:" "$port"
            _kv "UUID:" "$uuid"
            _kv "分离模式:" "${is_route_mode:-v4上行/v6下行}"
            echo
        fi
        
        open_port $port
        [[ $is_new_install ]] && _ok "防火墙端口已放行: $port"
        
        if [[ $is_new_install ]]; then
            create config.json
        else
            manage restart &
        fi
        ;;
    config.json)
        cat <<EOF >$is_config_json
{
    "log": {
        "access": "$is_log_dir/access.log",
        "error": "$is_log_dir/error.log",
        "loglevel": "warning"
    },
    "dns": {
        "servers": [
            "localhost",
            "1.1.1.1",
            "8.8.8.8"
        ]
    },
    "geodata": {
        "cron": "0 4 * * *",
        "outbound": "direct",
        "assets": [
            {
                "url": "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat",
                "file": "geoip.dat"
            },
            {
                "url": "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat",
                "file": "geosite.dat"
            }
        ]
    },
    "outbounds": [
        {
            "protocol": "freedom",
            "tag": "direct",
            "settings": {
                "domainStrategy": "UseIPv4v6"
            }
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ],
    "routing": {
        "domainStrategy": "IPIfNonMatch",
        "rules": [
            {
                "type": "field",
                "domain": [
                    "geosite:google"
                ],
                "outboundTag": "direct"
            },
            {
                "type": "field",
                "domain": [
                    "geosite:cn"
                ],
                "outboundTag": "block"
            },
            {
                "type": "field",
                "ip": [
                    "geoip:cn",
                    "geoip:private"
                ],
                "outboundTag": "block"
            },
            {
                "type": "field",
                "protocol": [
                    "bittorrent"
                ],
                "outboundTag": "block"
            }
        ]
    }
}
EOF
        manage restart &
        ;;
    esac
}

# change config file
change() {
    is_change=1
    is_dont_show_info=1
    [[ $is_dont_auto_exit ]] && {
        get info $1
    } || {
        [[ $is_change_id ]] && {
            is_change_msg=${change_list[$is_change_id]}
            [[ $is_change_id == 'full' ]] && {
                [[ $3 ]] && is_change_msg="更改多个参数" || is_change_msg=
            }
            [[ $is_change_msg ]] && _step "快速执行: $is_change_msg"
        }
        info $1
        [[ $is_auto_get_config ]] && _info "自动选择: $is_config_file"
    }
    is_old_net=$net
    [[ $host ]] && net=$is_protocol-$net-tls
    [[ $is_reality ]] && net=reality
    [[ $is_dynamic_port ]] && net=${net}d
    # if is_dont_show_info exist, cant show info.
    is_dont_show_info=
    
    # update change list dynamically for route mode
    if [[ -f $is_conf_dir/is_v6_uplink ]]; then
        change_list[9]="切换分离类型 (当前: v6上行/v4下行)"
    else
        change_list[9]="切换分离类型 (当前: v4上行/v6下行)"
    fi
    
    # if not prefer args, show change list and then get change id.
    [[ ! $is_change_id ]] && {
        ask set_change_list
        [[ $REPLY == "0" ]] && return
        is_change_id=${is_can_change[$REPLY - 1]}
    }
    case $is_change_id in
    full)
        add $net ${@:3}
        ;;
    0)
        # new port
        is_new_port=$3
        if [[ $is_new_port && ! $is_auto ]]; then
            if [[ $is_new_port != 443 && $is_new_port != 8443 ]]; then
                err "为保障协议伪装的隐蔽性与安全性，本脚本强制规定仅支持 443 或 8443 端口"
            fi
            [[ $(is_test port_used $is_new_port) ]] && err "无法使用 ($is_new_port) 端口，该端口已被占用"
        fi
        
        [[ $is_auto ]] && get_port && is_new_port=$tmp_port
        
        if [[ ! $is_new_port ]]; then
            ask list is_new_port "443 8443" "\n  为保障协议伪装的安全性和隐蔽性，仅支持如下端口:" "  请选择新端口:"
            [[ $REPLY == "0" ]] && return
        fi
        
        [[ $is_new_port == $port ]] && {
            _fail "新端口与当前端口 ($port) 相同，无需切换"
            return
        }
        
        if [[ $(is_test port_used $is_new_port) ]]; then
            _fail "目标端口 ($is_new_port) 已被占用，无法切换"
            return
        fi
        
        close_port $port
        _ok "已关闭旧端口防火墙规则: $port"
        
        add $net $is_new_port
        _ok "已放行新端口防火墙规则: $is_new_port"
        ;;
    1)
        # new xhttp path
        is_new_v4_path=$3
        [[ ! $is_reality ]] && err "($is_config_file) 不支持此更改"
        [[ ! $is_new_v4_path ]] && ask string is_new_v4_path "  请输入新 xhttp 路径:"
        [[ $REPLY == "0" ]] && return
        v4_path=$is_new_v4_path
        add $net
        ;;
    2)
        # new uuid
        [[ ! $is_reality ]] && err "($is_config_file) 不支持此更改"
        get_uuid
        is_new_uuid=$tmp_uuid
        add $net auto $is_new_uuid
        ;;
    3)
        # new is_private_key is_public_key
        [[ ! $is_reality ]] && err "($is_config_file) 不支持此更改"
        get_pbk
        add $net
        ;;
    4)
        # new v4 sni/dest
        is_new_v4_sni=$3
        [[ ! $is_reality ]] && err "($is_config_file) 不支持此更改"
        [[ ! $is_new_v4_sni ]] && ask string is_new_v4_sni "  请输入新的 v4 目标域名 (SNI/Dest) [0 返回]:"
        [[ $REPLY == "0" ]] && return
        v4_sni=$is_new_v4_sni
        add $net
        ;;
    5)
        # new v6 sni/dest
        is_new_v6_sni=$3
        [[ ! $is_reality ]] && err "($is_config_file) 不支持此更改"
        [[ ! $is_new_v6_sni ]] && ask string is_new_v6_sni "  请输入新的 v6 目标域名 (SNI/Dest) [0 返回]:"
        [[ $REPLY == "0" ]] && return
        v6_sni=$is_new_v6_sni
        add $net
        ;;
    6)
        # new v4 short ids
        [[ ! $is_reality ]] && err "($is_config_file) 不支持此更改"
        get_short_ids
        v4_short_ids=$is_short_ids
        add $net
        ;;
    7)
        # new v6 short ids
        [[ ! $is_reality ]] && err "($is_config_file) 不支持此更改"
        get_short_ids
        v6_short_ids=$is_short_ids
        add $net
        ;;
    8)
        # toggle v6only
        [[ ! $is_reality ]] && err "($is_config_file) 不支持此更改"
        if [[ $v6_only == 'true' ]]; then
            v6_only=false
            _ok "v6only 已关闭"
        else
            v6_only=true
            _ok "v6only 已开启"
        fi
        add $net
        ;;
    9)
        # toggle route mode
        [[ ! $is_reality ]] && err "($is_config_file) 不支持此更改"
        if [[ -f $is_conf_dir/is_v6_uplink ]]; then
            rm -f $is_conf_dir/is_v6_uplink
            unset is_v6_uplink
            _ok "分离类型已切换为: v4上行/v6下行"
        else
            touch $is_conf_dir/is_v6_uplink
            export is_v6_uplink=1
            _ok "分离类型已切换为: v6上行/v4下行"
        fi
        add $net
        ;;
    esac
}

# delete config.
del() {
    # dont get ip
    is_dont_get_ip=1
    [[ $is_conf_dir_empty ]] && return # not found any json file.
    # get a config file
    [[ ! $is_config_file ]] && get info $1
    if [[ $is_config_file ]]; then
        api del $is_conf_dir/"$is_config_file" $is_dynamic_port_file &>/dev/null
        rm -rf $is_conf_dir/"$is_config_file" $is_dynamic_port_file
        [[ $is_api_fail && ! $is_new_json ]] && manage restart &
        [[ ! $is_no_del_msg ]] && _ok "已删除: $is_config_file"
    fi
    if [[ ! $(ls $is_conf_dir | grep .json) && ! $is_change ]]; then
        warn "当前配置目录为空! 因为你刚刚删除了最后一个配置文件"
        is_conf_dir_empty=1
    fi
    unset is_dont_get_ip
    [[ $is_dont_auto_exit ]] && unset is_config_file
}

# uninstall
uninstall() {
    echo
    ask string y "  确认卸载 ${is_core_name}? [y]:"
    [[ $REPLY == "0" ]] && return
    
    _step "正在停止 $is_core_name 服务..."
    manage stop &>/dev/null
    manage disable &>/dev/null
    
    # Close all opened ports before deleting config
    if [[ -d $is_conf_dir ]]; then
        for v in $(ls $is_conf_dir | grep .json$ | sed '/dynamic-port-.*-link/d'); do
            local p=$(jq -r '.inbounds[0].port' $is_conf_dir/"$v")
            if [[ $(is_test port $p) ]]; then
                close_port $p
                _ok "已关闭防火墙端口: $p"
            fi
        done
    fi

    _step "正在清理文件..."
    rm -rf $is_core_dir $is_log_dir $is_sh_bin /lib/systemd/system/$is_core.service /etc/init.d/$is_core
    sed -i "/$is_core/d" /root/.bashrc
    systemctl daemon-reload &>/dev/null
    
    echo
    _ok "$is_core_name 卸载完成"
    _info "脚本哪里需要完善? 请反馈"
    _info "反馈问题: $(msg_ul https://github.com/${is_sh_repo}/issues)"
    echo
}

# manage run status
manage() {
    [[ $is_dont_auto_exit ]] && return
    case $1 in
    1 | start)
        is_do=start
        is_do_msg=启动
        is_test_run=1
        ;;
    2 | stop)
        is_do=stop
        is_do_msg=停止
        ;;
    3 | r | restart)
        is_do=restart
        is_do_msg=重启
        is_test_run=1
        ;;
    *)
        is_do=$1
        is_do_msg=$1
        ;;
    esac
    is_do_name=$is_core
    is_run_bin=$is_core_bin
    is_do_name_msg=$is_core_name
    systemctl $is_do $is_do_name
    [[ $is_test_run && ! $is_new_install ]] && {
        sleep 2
        if [[ ! $(pgrep -f $is_run_bin) ]]; then
            is_run_fail=${is_do_name_msg,,}
            [[ ! $is_no_manage_msg ]] && {
                echo
                _fail "($is_do_msg) $is_do_name_msg 失败"
                _info "检测到运行失败, 自动执行测试运行..."
                get test-run
                _info "测试结束, 请按 Enter 退出"
            }
        fi
    }
}

# use api add or del inbounds
api() {
    [[ ! $1 ]] && err "无法识别 API 的参数"
    [[ $is_core_stop ]] && {
        warn "$is_core_name 当前处于停止状态"
        is_api_fail=1
        return
    }
    case $1 in
    add)
        is_api_do=adi
        ;;
    del)
        is_api_do=rmi
        ;;
    s)
        is_api_do=stats
        ;;
    t | sq)
        is_api_do=statsquery
        ;;
    esac
    [[ ! $is_api_do ]] && is_api_do=$1
    [[ ! $is_api_port ]] && {
        is_api_port=$(jq '.inbounds[] | select(.tag == "api") | .port' $is_config_json)
        [[ $? != 0 ]] && {
            warn "读取 API 端口失败, 无法使用 API 操作"
            return
        }
    }
    $is_core_bin api $is_api_do --server=127.0.0.1:$is_api_port ${@:2}
    [[ $? != 0 ]] && {
        is_api_fail=1
    }
}

# add a config
add() {
    is_lower=${1,,}
    if [[ $is_lower ]]; then
        case $is_lower in
        r | reality)
            is_new_protocol=VLESS-REALITY
            ;;
        *)
            err "无法识别 ($1), 目前仅支持: r 或 reality"
            ;;
        esac
    fi

    # no prefer protocol
    [[ ! $is_new_protocol ]] && is_new_protocol=VLESS-REALITY

    is_reality=1
    is_use_port=$2
    is_use_uuid=$3
    is_use_servername=$4
    is_add_opts="[port] [uuid] [sni]"

    # prefer args.
    if [[ $2 ]]; then
        for v in is_use_port is_use_uuid is_use_servername; do
            [[ ${!v} == 'auto' ]] && unset $v
        done

        if [[ $is_use_port ]]; then
            [[ ! $(is_test port ${is_use_port}) ]] && {
                err "($is_use_port) 不是一个有效的端口"
            }
            [[ $(is_test port_used $is_use_port) ]] && {
                err "无法使用 ($is_use_port) 端口"
            }
            port=$is_use_port
        fi
        if [[ $is_use_uuid ]]; then
            [[ ! $(is_test uuid $is_use_uuid) ]] && {
                err "($is_use_uuid) 不是一个有效的 UUID"
            }
            uuid=$is_use_uuid
        fi
        [[ $is_use_servername ]] && is_servername=$is_use_servername
    fi

    # create json
    create server $is_new_protocol

    # show config info.
    info
}

# get config info
# or somes required args
get() {
    case $1 in
    addr)
        is_addr=$host
        [[ ! $is_addr ]] && {
            get_ip
            is_addr=$ip
            [[ $(grep ":" <<<$ip) ]] && is_addr="[$ip]"
        }
        ;;
    new)
        [[ ! $host ]] && get_ip
        [[ ! $port ]] && get_port && port=$tmp_port
        [[ ! $uuid ]] && get_uuid && uuid=$tmp_uuid
        [[ ! $is_short_ids ]] && get_short_ids
        [[ ! $is_private_key ]] && get_pbk
        if [[ $is_new_install ]]; then
            is_default_arg="v4上行/v6下行"
            ask list is_route_mode "v4上行/v6下行 v6上行/v4下行" "\n  请选择首选的流向模式:" "  请选择 (默认: v4上行/v6下行):"
            if [[ $is_route_mode == "v6上行/v4下行" ]]; then
                export is_v6_uplink=1
                touch $is_conf_dir/is_v6_uplink
            fi
            is_default_arg="empty_allowed"
            ask string is_new_v4_sni "  请输入 v4 目标域名 (SNI/Dest) [直接回车随机生成]:"
            [[ $is_new_v4_sni ]] && export v4_sni=$is_new_v4_sni
            is_default_arg="empty_allowed"
            ask string is_new_v6_sni "  请输入 v6 目标域名 (SNI/Dest) [直接回车随机生成]:"
            [[ $is_new_v6_sni ]] && export v6_sni=$is_new_v6_sni
        fi
        if [[ ! $v4_sni || ! $v6_sni ]]; then
            get_random_sni
            [[ ! $v4_sni ]] && v4_sni=$tmp_v4_sni
            [[ ! $v6_sni ]] && v6_sni=$tmp_v6_sni
        fi
        ;;
    file)
        is_file_str=$2
        [[ ! $is_file_str ]] && is_file_str='.json$'
        # is_all_json=("$(ls $is_conf_dir | grep -E $is_file_str)")
        readarray -t is_all_json <<<"$(ls $is_conf_dir | grep -E -i "$is_file_str" | sed '/dynamic-port-.*-link/d' | head -233)" # limit max 233 lines for show.
        [[ ${#is_all_json[@]} -eq 1 && -z "${is_all_json[0]}" ]] && unset is_all_json
        [[ ! $is_all_json ]] && err "无法找到相关的配置文件: $2"
        [[ ${#is_all_json[@]} -eq 1 ]] && is_config_file=${is_all_json[0]} && is_auto_get_config=1
        [[ ! $is_config_file ]] && {
            [[ $is_dont_auto_exit ]] && return
            ask get_config_file
        }
        ;;
    info)
        get file $2
        if [[ $is_config_file ]]; then
            is_json_str=$(cat $is_conf_dir/"$is_config_file")
            
            # v4 parsing
            is_protocol=$(jq -r '.inbounds[0].protocol' <<<$is_json_str)
            port=$(jq -r '.inbounds[0].port' <<<$is_json_str)
            uuid=$(jq -r '.inbounds[0].settings.clients[0].id' <<<$is_json_str)
            v4_dest=$(jq -r '.inbounds[0].streamSettings.realitySettings.dest' <<<$is_json_str)
            v4_sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0]' <<<$is_json_str)
            is_private_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.privateKey' <<<$is_json_str)
            is_public_key=$(jq -r '.inbounds[0].streamSettings.realitySettings.publicKey // ""' <<<$is_json_str)
            v4_short_ids=$(jq -c '.inbounds[0].streamSettings.realitySettings.shortIds // [""]' <<<$is_json_str)
            
            # fallback for older generated config without publicKey in json
            if [[ ! $is_public_key ]]; then
                is_public_key="Unknown(please regenerate config)"
            fi
            
            # v6 parsing
            v6_dest=$(jq -r '.inbounds[1].streamSettings.realitySettings.dest // ""' <<<$is_json_str)
            v6_sni=$(jq -r '.inbounds[1].streamSettings.realitySettings.serverNames[0] // ""' <<<$is_json_str)
            v6_short_ids=$(jq -c '.inbounds[1].streamSettings.realitySettings.shortIds // [""]' <<<$is_json_str)
            v6_only=$(jq -r '.inbounds[1].streamSettings.sockopt.v6only // false' <<<$is_json_str)
            
            # xhttp parsing
            v4_path=$(jq -r '.inbounds[2].streamSettings.xhttpSettings.path // ""' <<<$is_json_str)
            v6_path=$v4_path
            
            # core variables
            net=reality
            is_reality=reality
            is_config_name=$is_config_file
        fi
        ;;
    log | logerr)
        echo
        _info "按 ${green}Enter${none} 返回主菜单, 或 ${red}Ctrl+C${none} 退出脚本"
        echo
        trap "exit 0" INT
        if [[ $1 == 'log' ]]; then
            tail -f $is_log_dir/access.log $is_log_dir/error.log &
        else
            tail -f $is_log_dir/error.log &
        fi
        local tail_pid=$!
        read -rs -d $'\n'
        kill $tail_pid &>/dev/null
        trap - INT
        ;;
    test-run)
        systemctl list-units --full -all &>/dev/null
        [[ $? != 0 ]] && {
            _fail "无法执行测试, 请检查 systemctl 状态"
            return
        }
        is_no_manage_msg=1
        if [[ ! $(pgrep -f $is_core_bin) ]]; then
            _step "测试运行 $is_core_name ..."
            manage start &>/dev/null
            if [[ $is_run_fail == $is_core ]]; then
                _fail "$is_core_name 运行失败，错误信息:"
                echo
                $is_core_bin run -c $is_config_json -confdir $is_conf_dir
            else
                _ok "测试通过, 已启动 $is_core_name"
            fi
        else
            _ok "$is_core_name 正在运行, 跳过测试"
        fi
        ;;
    esac
}

# show info
info() {
    is_can_change=(0 1 2 3 4 5 6 7 8 9)
    if [[ ! $is_protocol ]]; then
        get info $1
    fi
    [[ $is_dont_show_info || $is_dont_auto_exit ]] && return # dont show info
    
    get addr
    is_color=41

    # get active shortId (first non-empty or empty)
    is_v4_sid=$(jq -r '.[1] // ""' <<<"$v4_short_ids")
    [[ "$is_v4_sid" == "null" ]] && is_v4_sid=""
    is_v6_sid=$(jq -r '.[1] // ""' <<<"$v6_short_ids")
    [[ "$is_v6_sid" == "null" ]] && is_v6_sid=""
    
    v4_url="$is_protocol://$uuid@$is_addr:$port?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=${v4_sni}&pbk=$is_public_key&fp=chrome&sid=${is_v4_sid}#233boy-v4-$is_addr"
    v6_url="$is_protocol://$uuid@$is_addr:$port?encryption=none&security=reality&flow=xtls-rprx-vision&type=tcp&sni=${v6_sni}&pbk=$is_public_key&fp=chrome&sid=${is_v6_sid}#233boy-v6-$is_addr"

    get_ipv6
    v6_ip=${ipv6:-""}

    [[ -f $is_conf_dir/is_v6_uplink ]] && is_v6_uplink=1
    
    if [[ $is_v6_uplink ]]; then
        uplink_ip=$v6_ip
        uplink_sni=$v6_sni
        uplink_sid=$is_v6_sid
        downlink_ip=$is_addr
        downlink_sni=$v4_sni
        downlink_sid=$is_v4_sid
    else
        uplink_ip=$is_addr
        uplink_sni=$v4_sni
        uplink_sid=$is_v4_sid
        downlink_ip=$v6_ip
        downlink_sni=$v6_sni
        downlink_sid=$is_v6_sid
    fi

    cat <<EOF
- name: $is_config_name
  type: vless
  server: "$uplink_ip"
  port: $port
  uuid: $uuid
  network: xhttp
  tls: true
  udp: true
  tfo: true
  mptcp: true
  packet-encoding: xudp
  encryption: none
  servername: $uplink_sni
  client-fingerprint: chrome
  alpn:
    - h2
  reality-opts:
    public-key: $is_public_key
    short-id: $uplink_sid
  sockopt:
    tcp-fast-open: true
    tcp-no-delay: true
    tcp-mptcp: true
  xhttp-opts:
    mode: stream-up
    host: $uplink_sni
    path: $v4_path
    no-grpc-header: false
    no-sse-header: false
    uplink-http-method: PUT
    x-padding-bytes: "100-1000"
    x-padding-obfs-mode: true
    x-padding-key: x_padding
    x-padding-header: Referer
    x-padding-placement: queryInHeader
    x-padding-method: tokenish
    session-placement: path
    seq-placement: path
    reuse-settings:
      max-concurrency: "16-32"
      c-max-reuse-times: 0
      h-max-request-times: "600-900"
      h-max-reusable-secs: "1800-3000"
      h-keep-alive-period: 0
    download-settings:
      server: "$downlink_ip"
      port: $port
      tls: true
      alpn:
        - h2
      servername: $downlink_sni
      client-fingerprint: firefox
      reality-opts:
        public-key: $is_public_key
        short-id: $downlink_sid
      no-grpc-header: false
      no-sse-header: false
      host: $downlink_sni
      path: $v4_path
      x-padding-bytes: "100-1000"
      x-padding-obfs-mode: true
      x-padding-key: x_padding
      x-padding-header: Referer
      x-padding-placement: queryInHeader
      x-padding-method: tokenish
      session-placement: path
      seq-placement: path
      sockopt:
        tcp-fast-open: true
        tcp-no-delay: true
        tcp-mptcp: true
      reuse-settings:
        max-concurrency: "8-16"
        c-max-reuse-times: 0
        h-max-request-times: "300-600"
        h-max-reusable-secs: "2400-3600"
        h-keep-alive-period: 0
EOF
    
    is_url="$v4_url\n$v6_url" # for url_qr compatibility

    footer_msg
}

# footer msg
footer_msg() {
    [[ $is_core_stop && ! $is_new_json ]] && warn "$is_core_name 当前处于停止状态"
}

# update core, sh
update() {
    case $1 in
    1 | core | $is_core)
        is_update_name=core
        is_show_name=$is_core_name
        is_run_ver=v${is_core_ver##* }
        is_update_repo=$is_core_repo
        ;;
    2 | sh)
        is_update_name=sh
        is_show_name="$is_core_name 脚本"
        is_run_ver=$is_sh_ver
        is_update_repo=$is_sh_repo
        ;;
    *)
        err "无法识别 ($1), 请使用: $is_core update [core | sh] [ver]"
        ;;
    esac
    [[ $2 ]] && is_new_ver=v${2#v}
    [[ $is_run_ver == $is_new_ver ]] && {
        _info "自定义版本和当前 $is_show_name 版本一样, 无需更新"
        return
    }
    load download.sh
    if [[ $is_new_ver ]]; then
        _step "使用自定义版本更新 $is_show_name: $(_green $is_new_ver)"
    else
        get_latest_version $is_update_name
        is_new_ver=$latest_ver
        [[ $is_run_ver == $is_new_ver ]] && {
            _ok "当前 $is_show_name 已是最新版本: $(_green $is_run_ver)"
            return
        }
        _step "发现 $is_show_name 新版本: $(_green $is_new_ver)"
    fi
    _step "正在下载更新..."
    download $is_update_name $is_new_ver
    _ok "$is_show_name 更新成功: $(_green $is_new_ver)"
    [[ $is_update_name == 'core' ]] && {
        manage restart &
        is_core_ver=$($is_core_bin version | head -n1 | cut -d " " -f1-2)
        _ok "$is_core_name 已重启"
    }
    [[ $is_update_name == 'sh' ]] && {
        _ok "脚本已更新，正在重新加载..."
        sleep 1
        exec $is_sh_bin
    }
}

# reset state variables between menu operations
_reset_state() {
    unset is_protocol is_config_file is_config_name is_json_str
    unset net is_reality is_old_net is_dynamic_port
    unset port uuid is_private_key is_public_key
    unset v4_sni v6_sni v4_dest v6_dest v4_path v6_path
    unset v4_short_ids v6_short_ids v6_only
    unset is_change is_change_id is_change_msg is_dont_show_info
    unset is_auto_get_config is_no_del_msg is_new_json
    unset is_addr is_v4_sid is_v6_sid is_v6_uplink
    unset host is_conf_dir_empty
    unset is_api_fail is_run_fail is_no_manage_msg
    unset is_core_stop
    # re-check core status
    if [[ $(pgrep -f $is_core_bin) ]]; then
        is_core_status="${green}● 运行中${none}"
        is_core_status_short="${green}运行中${none}"
    else
        is_core_status="${red}● 已停止${none}"
        is_core_status_short="${red}已停止${none}"
        is_core_stop=1
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
    _ov_sni_warning=""

    local v4_tmp="/tmp/.v4_sni_res_$$"
    local v6_tmp="/tmp/.v6_sni_res_$$"

    local pid_v4=""
    local pid_v6=""

    if [[ $_ov_v4_sni ]]; then
        (
            res=$(curl -s -v -m 3 -A "Mozilla/5.0" -o /dev/null "https://$_ov_v4_sni" 2>&1)
            if [[ $? == 0 ]] && echo "$res" | grep -qE "TLSv1.3"; then
                echo "OK"
            else
                echo "FAIL"
            fi
        ) > "$v4_tmp" &
        pid_v4=$!
    fi

    if [[ $_ov_v6_sni ]]; then
        (
            res=$(curl -s -v -m 3 -A "Mozilla/5.0" -o /dev/null "https://$_ov_v6_sni" 2>&1)
            if [[ $? == 0 ]] && echo "$res" | grep -qE "TLSv1.3"; then
                echo "OK"
            else
                echo "FAIL"
            fi
        ) > "$v6_tmp" &
        pid_v6=$!
    fi

    [[ $pid_v4 ]] && wait $pid_v4
    [[ $pid_v6 ]] && wait $pid_v6

    if [[ $_ov_v4_sni ]]; then
        if [[ -f $v4_tmp && $(cat "$v4_tmp") == "OK" ]]; then
            _ov_v4_sni_status="${green}✓${none} "
        else
            _ov_v4_sni_status="${red}✗${none} "
            _ov_sni_warning+="  [警告] v4 伪装域名 ($_ov_v4_sni) 证书不受信、无法连通或不支持 TLS 1.3 / h2，强烈建议更换！\n"
        fi
        rm -f "$v4_tmp"
    fi

    if [[ $_ov_v6_sni ]]; then
        if [[ -f $v6_tmp && $(cat "$v6_tmp") == "OK" ]]; then
            _ov_v6_sni_status="${green}✓${none} "
        else
            _ov_v6_sni_status="${red}✗${none} "
            _ov_sni_warning+="  [警告] v6 伪装域名 ($_ov_v6_sni) 证书不受信、无法连通或不支持 TLS 1.3 / h2，强烈建议更换！\n"
        fi
        rm -f "$v6_tmp"
    fi
}

# get overview info for main menu
_get_overview() {
    _check_ip_blocked
    _ov_port=""
    _ov_v4_sni=""
    _ov_v6_sni=""
    _ov_v6only=""
    _ov_route_mode=""
    _ov_log_level=""
    _ov_fw_ports=""
    _ov_sys_ports=""
    _ov_v4_sids=""
    _ov_v6_sids=""
    _ov_path=""
    _ov_pbk=""
    _ov_uuid=""

    # parse first config file
    if [[ -d $is_conf_dir ]]; then
        local first_json=$(ls $is_conf_dir 2>/dev/null | grep '.json$' | sed '/dynamic-port-.*-link/d' | head -1)
        if [[ $first_json && -f $is_conf_dir/$first_json ]]; then
            local json_str=$(cat $is_conf_dir/$first_json)
            _ov_port=$(jq -r '.inbounds[0].port // ""' <<<$json_str 2>/dev/null)
            _ov_v4_sni=$(jq -r '.inbounds[0].streamSettings.realitySettings.serverNames[0] // ""' <<<$json_str 2>/dev/null)
            _ov_v6_sni=$(jq -r '.inbounds[1].streamSettings.realitySettings.serverNames[0] // ""' <<<$json_str 2>/dev/null)
            
            _ov_v4_sids=$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds | join(",") // ""' <<<$json_str 2>/dev/null)
            _ov_v6_sids=$(jq -r '.inbounds[1].streamSettings.realitySettings.shortIds | join(",") // ""' <<<$json_str 2>/dev/null)
            _ov_path=$(jq -r '.inbounds[2].streamSettings.xhttpSettings.path // ""' <<<$json_str 2>/dev/null)
            _ov_pbk=$(jq -r '.inbounds[0].streamSettings.realitySettings.publicKey // ""' <<<$json_str 2>/dev/null)
            _ov_uuid=$(jq -r '.inbounds[0].settings.clients[0].id // ""' <<<$json_str 2>/dev/null)
            
            local v6o=$(jq -r '.inbounds[1].streamSettings.sockopt.v6only // false' <<<$json_str 2>/dev/null)
            [[ "$v6o" == "true" ]] && _ov_v6only="开启" || _ov_v6only="关闭"
        fi
    fi

    # route mode
    if [[ -f $is_conf_dir/is_v6_uplink ]]; then
        _ov_route_mode="v6上行/v4下行"
    else
        _ov_route_mode="v4上行/v6下行"
    fi

    # log level
    if [[ -f $is_config_json ]]; then
        _ov_log_level=$(jq -r '.log.loglevel // "unknown"' $is_config_json 2>/dev/null)
    fi

    # firewall ports
    local fw_ports_v4=""
    if [[ $(type -P iptables) ]]; then
        fw_ports_v4=$(iptables -nL INPUT 2>/dev/null | grep -w "ACCEPT" | grep -Eo 'dpt:[0-9]+' | cut -d: -f2 | sort -nu | xargs echo)
    fi
    local fw_ports_v6=""
    if [[ $(type -P ip6tables) ]]; then
        fw_ports_v6=$(ip6tables -nL INPUT 2>/dev/null | grep -w "ACCEPT" | grep -Eo 'dpt:[0-9]+' | cut -d: -f2 | sort -nu | xargs echo)
    fi
    _ov_fw_ports=$(echo "$fw_ports_v4 $fw_ports_v6" | tr ' ' '\n' | sort -nu | xargs echo | sed 's/ /, /g')
    [[ ! $_ov_fw_ports ]] && _ov_fw_ports="无"

    # system listening ports
    local core_name=${is_core:-xray}
    if [[ $(type -P ss) ]]; then
        _ov_sys_ports=$(ss -tunlp 2>/dev/null | grep -vE "systemd-resolve|chronyd" | awk -v core="$core_name" '
            $1 ~ /^(tcp|udp)/ {
                n = split($5, a, ":"); port = a[n];
                if ($1 ~ /^udp/ && port >= 30000 && $0 ~ core) next;
                print port;
            }' | sort -nu | xargs echo | sed 's/ /, /g')
    elif [[ $(type -P netstat) ]]; then
        _ov_sys_ports=$(netstat -tunlp 2>/dev/null | grep -vE "systemd-resolve|chronyd" | awk -v core="$core_name" '
            $1 ~ /^(tcp|udp)/ {
                n = split($4, a, ":"); port = a[n];
                if ($1 ~ /^udp/ && port >= 30000 && $0 ~ core) next;
                print port;
            }' | sort -nu | xargs echo | sed 's/ /, /g')
    fi
    [[ ! $_ov_sys_ports ]] && _ov_sys_ports="无"
    
    _check_sni_status
}


misc_menu() {
    while :; do
        clear
        echo
        _line
        echo -e "  ${bold}${cyan}$is_core_name${none} ${gray}${is_core_ver}${none}  ${dim}/${none}  ${gray}Script ${is_sh_ver}${none}  ${dim}│${none}  ${is_core_status}"
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
        read REPLY
        [[ "$REPLY" == "0" ]] && return
        
        case $REPLY in
        1)
            echo
            get test-run
            pause
            ;;
        2)
            get log
            ;;
        3)
            echo
            ask list is_log_level "debug info warning error none" "\n  请选择日志等级:"
            [[ $REPLY == "0" ]] && continue
            sed -i "s/\"loglevel\": \".*\"/\"loglevel\": \"$is_log_level\"/g" /usr/local/etc/xray/config.json
            _ok "日志等级已修改为: $is_log_level"
            manage restart &
            sleep 1
            ;;
        4)
            echo
            ask string p "  请输入端口操作 (例: o 443 开放, c 443 关闭) [0 返回]:"
            [[ $REPLY == "0" ]] && continue
            local action=$(echo $p | awk '{print $1}')
            local port=$(echo $p | awk '{print $2}')
            if [[ ($action == "o" || $action == "c") ]] && [[ $(is_test port $port) ]]; then
                if [[ $action == "o" ]]; then
                    open_port $port
                    _ok "已放行端口: $port"
                else
                    close_port $port
                    _ok "已关闭端口: $port"
                fi
            else
                _fail "无效的指令或端口格式"
            fi
            pause
            ;;
        5)
            echo
            is_tmp_list=("更新$is_core_name" "更新脚本")
            ask list is_do_update null "\n  请选择更新:\n"
            [[ $REPLY == "0" ]] && continue
            update $REPLY
            pause
            ;;
        6)
            uninstall
            exit 0
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
        echo -e "  ${bold}${cyan}$is_core_name${none} ${gray}${is_core_ver}${none}  ${dim}/${none}  ${gray}Script ${is_sh_ver}${none}  ${dim}│${none}  ${is_core_status}"
        _line

        # ── config overview ──
        if [[ $_ov_port ]]; then
            local short_pbk="$_ov_pbk"
            if [[ ${#short_pbk} -gt 25 ]]; then
                short_pbk="${short_pbk:0:15}...${short_pbk:(-5)}"
            fi
            
            local v6o_color="${gray}关闭${none}"
            [[ "$_ov_v6only" == "开启" ]] && v6o_color="${green}开启${none}"

            echo -e "  ${cyan}[基础]${none} 端口: ${green}$_ov_port${none}   分离: ${green}$_ov_route_mode${none}   日志: ${green}$_ov_log_level${none}"
            echo -e "  ${cyan}[UUID]${none} ${green}$_ov_uuid${none}"
            echo -e "  ${cyan}[ v4 ]${none} SNI: $_ov_v4_sni_status${green}$_ov_v4_sni${none}   SIDs: ${green}$_ov_v4_sids${none}"
            echo -e "  ${cyan}[ v6 ]${none} SNI: $_ov_v6_sni_status${green}$_ov_v6_sni${none}   SIDs: ${green}$_ov_v6_sids${none}   v6only: $v6o_color"
            echo -e "  ${cyan}[高级]${none} 路径: ${green}$_ov_path${none}   公钥: ${green}$short_pbk${none}"
            echo -e "  ${cyan}[状态]${none} GFW放行: $_ov_ip_blocked   防火墙: ${green}$_ov_fw_ports${none}   占用: ${green}$_ov_sys_ports${none}"
        else
            echo -e "  ${gray}暂无配置${none}"
        fi
        _line

        # ── menu items ──
        _section "节点管理"
        _menu 1 "更改配置"
        _menu 2 "查看客户端配置"
        _menu 3 "查看完整服务端配置"

        _section "运行控制"
        _menu 4 "启动 / 停止 / 重启"
        _menu 5 "查看运行状态"

        _section "杂项"
        _menu 6 "杂项管理 (包含日志/更新等)"

        if [[ $_ov_ip_warning || $_ov_sni_warning ]]; then
            echo
            [[ $_ov_ip_warning ]] && echo -ne "${red}${_ov_ip_warning}${none}"
            [[ $_ov_sni_warning ]] && echo -ne "${red}${_ov_sni_warning}${none}"
        fi

        echo
        echo -ne "  请选择 [${green}1-6${none}] [${red}0 退出${none}]: "
        read REPLY
        [[ "$REPLY" == "0" ]] && exit 0
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
            local merged_json=$(jq -s '.[0] + {inbounds: [.[1:][].inbounds[]?]}' $is_config_json $is_conf_dir/*.json 2>/dev/null)
            if [[ $merged_json ]]; then
                if [[ $is_view_mode == "预览(支持滚动)" ]] && command -v less &>/dev/null; then
                    echo "$merged_json" | jq -C . | less -R
                else
                    echo "$merged_json" | jq -C .
                fi
            else
                _fail "无法读取或合并配置文件"
            fi
            pause
            ;;
        4)
            echo
            ask list is_do_manage "启动 停止 重启"
            [[ $REPLY == "0" ]] && continue
            manage $REPLY &
            _ok "执行操作: $is_do_manage"
            sleep 2
            ;;
        5)
            echo
            systemctl status $is_core -l --no-pager
            echo
            pause
            ;;
        6)
            misc_menu
            ;;
        esac
    done
}
