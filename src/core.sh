#!/bin/bash

protocol_list=(
    VLESS-REALITY
)
mainmenu=(
    "更改配置"
    "查看配置"
    "运行管理"
    "更新"
    "卸载"
    "其他"
)
info_list=(
    "协议 (protocol)"
    "地址 (address)"
    "端口 (port)"
    "用户ID (id)"
    "传输协议 (network)"
    "伪装类型 (type)"
    "伪装域名 (host)"
    "路径 (path)"
    "传输层安全 (TLS)"
    "mKCP seed"
    "密码 (password)"
    "加密方式 (encryption)"
    "链接 (URL)"
    "目标地址 (remote addr)"
    "目标端口 (remote port)"
    "流控 (flow)"
    "SNI (serverName)"
    "指纹 (Fingerprint)"
    "公钥 (Public key)"
    "用户名 (Username)"
)
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
)
servername_list=(
    www.amazon.com
    www.ebay.com
    www.paypal.com
    www.cloudflare.com
    dash.cloudflare.com
    aws.amazon.com
)

is_random_servername=${servername_list[$(shuf -i 0-${#servername_list[@]} -n1) - 1]}

msg() {
    echo -e "$@"
}

msg_ul() {
    echo -e "\e[4m$@\e[0m"
}

# pause
pause() {
    echo
    echo -ne "按 $(_green Enter 回车键) 继续, 或按 $(_red Ctrl + C) 取消."
    read -rs -d $'\n'
    echo
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
    [[ $ip || $is_no_auto_tls || $is_gen || $is_dont_get_ip ]] && return
    export "$(_wget -4 -qO- https://one.one.one.one/cdn-cgi/trace | grep ip=)" &>/dev/null
    [[ ! $ip ]] && export "$(_wget -6 -qO- https://one.one.one.one/cdn-cgi/trace | grep ip=)" &>/dev/null
    [[ ! $ip ]] && {
        err "获取服务器 IP 失败.."
    }
}

get_ipv6() {
    [[ $ipv6 || $is_no_auto_tls || $is_gen || $is_dont_get_ip ]] && return
    export "ipv6=$(_wget -6 -qO- https://one.one.one.one/cdn-cgi/trace | grep ip= | cut -d= -f2)" &>/dev/null
}

get_port() {
    tmp_port=443
    if [[ $(is_test port_used 443) ]]; then
        tmp_port=8443
        if [[ $(is_test port_used 8443) ]]; then
            err "端口 (443) 和 (8443) 均被占用，安装失败。"
        fi
    fi
}

get_pbk() {
    is_tmp_pbk=($($is_core_bin x25519 | sed 's/.*://'))
    is_private_key=${is_tmp_pbk[0]}
    is_public_key=${is_tmp_pbk[1]}
}

get_random_sni() {
    local snis=("www.magicardshop.jp" "ototoy.jp" "dova-s.jp" "hf-mirror.com")
    local idx1=$((RANDOM % 4))
    local idx2=$((RANDOM % 4))
    while [[ $idx2 == $idx1 ]]; do
        idx2=$((RANDOM % 4))
    done
    tmp_v4_sni=${snis[$idx1]}
    tmp_v6_sni=${snis[$idx2]}
}

show_list() {
    PS3=''
    COLUMNS=1
    select i in "$@"; do echo; done &
    wait
    # i=0
    # for v in "$@"; do
    #     ((i++))
    #     echo "$i) $v"
    # done
    # echo

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
    msg "$is_warn 无法检测端口是否可用."
    msg "请执行: $(_yellow "${cmd} update -y; ${cmd} install net-tools -y") 来修复此问题."
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
    set_ss_method)
        is_tmp_list=(${ss_method_list[@]})
        is_default_arg=$is_random_ss_method
        is_opt_msg="\n请选择加密方式:\n"
        is_opt_input_msg="(默认\e[92m $is_default_arg\e[0m):"
        is_ask_set=ss_method
        ;;
    set_header_type)
        is_tmp_list=(${header_type_list[@]})
        is_default_arg=$is_random_header_type
        [[ $(grep -i tcp <<<"$is_new_protocol-$net") ]] && {
            is_tmp_list=(none http)
            is_default_arg=none
        }
        is_opt_msg="\n请选择伪装类型:\n"
        is_opt_input_msg="(默认\e[92m $is_default_arg\e[0m):"
        is_ask_set=header_type
        [[ $is_use_header_type ]] && return
        ;;
    set_protocol)
        is_tmp_list=(${protocol_list[@]})
        [[ $is_no_auto_tls ]] && {
            unset is_tmp_list
            for v in ${protocol_list[@]}; do
                [[ $(grep -i tls$ <<<$v) ]] && is_tmp_list=(${is_tmp_list[@]} $v)
            done
        }
        is_opt_msg="\n请选择协议:\n"
        is_ask_set=is_new_protocol
        ;;
    set_change_list)
        is_tmp_list=()
        for v in ${is_can_change[@]}; do
            is_tmp_list+=("${change_list[$v]}")
        done
        is_opt_msg="\n请选择更改:\n"
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
        is_opt_msg="\n请选择配置:\n"
        is_ask_set=is_config_file
        ;;
    mainmenu)
        is_tmp_list=("${mainmenu[@]}")
        is_ask_set=is_main_pick
        is_emtpy_exit=1
        ;;
    esac
    msg $is_opt_msg
    [[ ! $is_opt_input_msg ]] && is_opt_input_msg="请选择 [\e[91m1-${#is_tmp_list[@]}\e[0m] [0 返回]:"
    [[ $is_tmp_list ]] && show_list "${is_tmp_list[@]}"
    while :; do
        echo -ne "$is_opt_input_msg "
        read REPLY
        [[ $REPLY == "0" && $is_ask_set != 'is_main_pick' ]] && exec $is_sh_bin
        [[ ! $REPLY && $is_emtpy_exit ]] && exit
        [[ ! $REPLY && $is_default_arg ]] && export $is_ask_set=$is_default_arg && break
        [[ "$REPLY" == "${is_str}2${is_get}3${is_opt}3" && $is_ask_set == 'is_main_pick' ]] && {
            msg "\n${is_get}2${is_str}3${is_msg}3b${is_tmp}o${is_opt}y\n" && exit
        }
        if [[ ! $is_tmp_list ]]; then
            [[ $(grep port <<<$is_ask_set) ]] && {
                [[ ! $(is_test port "$REPLY") ]] && {
                    msg "$is_err 请输入正确的端口, 可选(1-65535)"
                    continue
                }
                if [[ $(is_test port_used $REPLY) && $is_ask_set != 'door_port' ]]; then
                    msg "$is_err 无法使用 ($REPLY) 端口."
                    continue
                fi
            }
            [[ $(grep path <<<$is_ask_set) && ! $(is_test path "$REPLY") ]] && {
                [[ ! $tmp_uuid ]] && get_uuid
                msg "$is_err 请输入正确的路径, 例如: /$tmp_uuid"
                continue
            }
            [[ $(grep uuid <<<$is_ask_set) && ! $(is_test uuid "$REPLY") ]] && {
                [[ ! $tmp_uuid ]] && get_uuid
                msg "$is_err 请输入正确的 UUID, 例如: $tmp_uuid"
                continue
            }
            [[ $(grep ^y$ <<<$is_ask_set) ]] && {
                [[ $(grep -i ^y$ <<<"$REPLY") ]] && break
                msg "请输入 (y)"
                continue
            }
            [[ $REPLY ]] && export $is_ask_set=$REPLY && msg "使用: ${!is_ask_set}" && break
        else
            [[ $(is_test number "$REPLY") ]] && is_ask_result=${is_tmp_list[$REPLY - 1]}
            [[ $is_ask_result ]] && export $is_ask_set="$is_ask_result" && msg "选择: ${!is_ask_set}" && break
        fi

        msg "输入${is_err}"
    done
    unset is_opt_msg is_opt_input_msg is_tmp_list is_ask_result is_default_arg is_emtpy_exit
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

        # only show json, dont save to file.
        [[ $is_gen ]] && {
            msg
            jq <<<$is_new_json
            msg
            return
        }

        # del old file
        [[ $is_config_file ]] && is_no_del_msg=1 && del $is_config_file
        
        # save json to file
        cat <<<$is_new_json >$is_json_file
        
        open_port $port
        
        if [[ $is_new_install ]]; then
            create config.json
        else
            manage restart &
        fi
        ;;
    client)
        is_tls=tls
        is_client=1
        get info $2
        [[ ! $is_client_id_json ]] && err "($is_config_name) 不支持生成客户端配置."
        [[ $host ]] && is_stream="${is_stream/network:\"$net\"/network:\"$net\",security:\"tls\"}"
        is_new_json=$(jq '{outbounds:[{tag:"'$is_config_name'",protocol:"'$is_protocol'",'"$is_client_id_json"','"$is_stream"'}]}' <<<{})
        if [[ $is_full_client ]]; then
            is_dns='dns:{servers:[{address:"223.5.5.5",domain:["geosite:cn","geosite:geolocation-cn"],expectIPs:["geoip:cn"]},"1.1.1.1","8.8.8.8"]}'
            is_route='routing:{rules:[{type:"field",outboundTag:"direct",ip:["geoip:cn","geoip:private"]},{type:"field",outboundTag:"direct",domain:["geosite:cn","geosite:geolocation-cn"]}]}'
            is_inbounds='inbounds:[{port:2333,listen:"127.0.0.1",protocol:"socks",settings:{udp:true},sniffing:{enabled:true,destOverride:["http","tls"]}}]'
            is_outbounds='outbounds:[{tag:"'$is_config_name'",protocol:"'$is_protocol'",'"$is_client_id_json"','"$is_stream"'},{tag:"direct",protocol:"freedom"}]'
            is_new_json=$(jq '{'$is_dns,$is_route,$is_inbounds,$is_outbounds'}' <<<{})
        fi
        msg
        jq <<<$is_new_json
        msg
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
                "domainStrategy": "UseIPv4"
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
    if [[ $2 ]]; then
        case ${2,,} in
        full)
            is_change_id=full
            ;;
        port)
            is_change_id=0
            ;;
        v4path | v4-path | path | xhttp-path)
            is_change_id=1
            ;;
        id | uuid)
            is_change_id=2
            ;;
        key | publickey | privatekey)
            is_change_id=3
            ;;
        v4dest | v4-dest | v4sni | v4-sni)
            is_change_id=4
            ;;
        v6dest | v6-dest | v6sni | v6-sni)
            is_change_id=5
            ;;
        v4sid | v4-sid | v4shortid)
            is_change_id=6
            ;;
        v6sid | v6-sid | v6shortid)
            is_change_id=7
            ;;
        v6only | v6-only)
            is_change_id=8
            ;;
        *)
            [[ $is_try_change ]] && return
            err "无法识别 ($2) 更改类型."
            ;;
        esac
    fi
    [[ $is_try_change ]] && return
    [[ $is_dont_auto_exit ]] && {
        get info $1
    } || {
        [[ $is_change_id ]] && {
            is_change_msg=${change_list[$is_change_id]}
            [[ $is_change_id == 'full' ]] && {
                [[ $3 ]] && is_change_msg="更改多个参数" || is_change_msg=
            }
            [[ $is_change_msg ]] && _green "\n快速执行: $is_change_msg"
        }
        info $1
        [[ $is_auto_get_config ]] && msg "\n自动选择: $is_config_file"
    }
    is_old_net=$net
    [[ $host ]] && net=$is_protocol-$net-tls
    [[ $is_reality ]] && net=reality
    [[ $is_dynamic_port ]] && net=${net}d
    [[ $3 == 'auto' ]] && is_auto=1
    # if is_dont_show_info exist, cant show info.
    is_dont_show_info=
    # if not prefer args, show change list and then get change id.
    [[ ! $is_change_id ]] && {
        ask set_change_list
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
            [[ ! $(is_test port $is_new_port) ]] && err "请输入正确的端口, 可选(1-65535)"
            [[ $is_new_port != 443 && $(is_test port_used $is_new_port) ]] && err "无法使用 ($is_new_port) 端口"
        fi
        [[ $is_auto ]] && get_port && is_new_port=$tmp_port
        [[ ! $is_new_port ]] && ask string is_new_port "请输入新端口:"
        add $net $is_new_port
        ;;
    1)
        # new xhttp path
        is_new_v4_path=$3
        [[ ! $is_reality ]] && err "($is_config_file) 不支持此更改."
        [[ ! $is_new_v4_path ]] && ask string is_new_v4_path "请输入新 xhttp 路径:"
        v4_path=$is_new_v4_path
        add $net
        ;;
    2)
        # new uuid
        [[ ! $is_reality ]] && err "($is_config_file) 不支持此更改."
        get_uuid
        is_new_uuid=$tmp_uuid
        add $net auto $is_new_uuid
        ;;
    3)
        # new is_private_key is_public_key
        [[ ! $is_reality ]] && err "($is_config_file) 不支持此更改."
        get_pbk
        add $net
        ;;
    4)
        # new v4 sni/dest
        is_new_v4_sni=$3
        [[ ! $is_reality ]] && err "($is_config_file) 不支持此更改."
        [[ ! $is_new_v4_sni ]] && ask string is_new_v4_sni "请输入新的 v4 目标域名 (SNI/Dest) [0 返回]:"
        v4_sni=$is_new_v4_sni
        add $net
        ;;
    5)
        # new v6 sni/dest
        is_new_v6_sni=$3
        [[ ! $is_reality ]] && err "($is_config_file) 不支持此更改."
        [[ ! $is_new_v6_sni ]] && ask string is_new_v6_sni "请输入新的 v6 目标域名 (SNI/Dest) [0 返回]:"
        v6_sni=$is_new_v6_sni
        add $net
        ;;
    6)
        # new v4 short ids
        [[ ! $is_reality ]] && err "($is_config_file) 不支持此更改."
        get_short_ids
        v4_short_ids=$is_short_ids
        add $net
        ;;
    7)
        # new v6 short ids
        [[ ! $is_reality ]] && err "($is_config_file) 不支持此更改."
        get_short_ids
        v6_short_ids=$is_short_ids
        add $net
        ;;
    8)
        # toggle v6only
        [[ ! $is_reality ]] && err "($is_config_file) 不支持此更改."
        if [[ $v6_only == 'true' ]]; then
            v6_only=false
        else
            v6_only=true
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
        if [[ $is_main_start && ! $is_no_del_msg ]]; then
            msg "\n是否删除配置文件?: $is_config_file"
            pause
        fi
        api del $is_conf_dir/"$is_config_file" $is_dynamic_port_file &>/dev/null
        rm -rf $is_conf_dir/"$is_config_file" $is_dynamic_port_file
        [[ $is_api_fail && ! $is_new_json ]] && manage restart &
        [[ ! $is_no_del_msg ]] && _green "\n已删除: $is_config_file\n"
    fi
    if [[ ! $(ls $is_conf_dir | grep .json) && ! $is_change ]]; then
        warn "当前配置目录为空! 因为你刚刚删除了最后一个配置文件."
        is_conf_dir_empty=1
    fi
    unset is_dont_get_ip
    [[ $is_dont_auto_exit ]] && unset is_config_file
}

# uninstall
uninstall() {
    ask string y "是否卸载 ${is_core_name}? [y]:"
    manage stop &>/dev/null
    manage disable &>/dev/null
    
    # Close all opened ports before deleting config
    if [[ -d $is_conf_dir ]]; then
        for v in $(ls $is_conf_dir | grep .json$ | sed '/dynamic-port-.*-link/d'); do
            local p=$(jq -r '.inbounds[0].port' $is_conf_dir/"$v")
            [[ $(is_test port $p) ]] && close_port $p
        done
    fi

    rm -rf $is_core_dir $is_log_dir $is_sh_bin /lib/systemd/system/$is_core.service /etc/init.d/$is_core
    sed -i "/$is_core/d" /root/.bashrc
    systemctl daemon-reload &>/dev/null
    
    [[ $is_install_sh ]] && return # reinstall
    _green "\n卸载完成!"
    msg "脚本哪里需要完善? 请反馈"
    msg "反馈问题) $(msg_ul https://github.com/${is_sh_repo}/issues)\n"
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
                msg
                warn "($is_do_msg) $is_do_name_msg 失败"
                _yellow "检测到运行失败, 自动执行测试运行."
                get test-run
                _yellow "测试结束, 请按 Enter 退出."
            }
        fi
    }
}

# use api add or del inbounds
api() {
    [[ ! $1 ]] && err "无法识别 API 的参数."
    [[ $is_core_stop ]] && {
        warn "$is_core_name 当前处于停止状态."
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
            warn "读取 API 端口失败, 无法使用 API 操作."
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
                err "($is_use_port) 不是一个有效的端口."
            }
            [[ $(is_test port_used $is_use_port) ]] && {
                err "无法使用 ($is_use_port) 端口."
            }
            port=$is_use_port
        fi
        if [[ $is_use_uuid ]]; then
            [[ ! $(is_test uuid $is_use_uuid) ]] && {
                err "($is_use_uuid) 不是一个有效的 UUID."
            }
            uuid=$is_use_uuid
        fi
        [[ $is_use_servername ]] && is_servername=$is_use_servername
    fi

    # for main menu start, dont auto create args
    if [[ $is_main_start ]]; then
        # set port
        [[ ! $port ]] && ask string port "请输入端口:"
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
            ask list is_route_mode "v4上行/v6下行 v6上行/v4下行" "\n请选择首选的流向模式:" "请选择 (默认: v4上行/v6下行):"
            if [[ $is_route_mode == "v6上行/v4下行" ]]; then
                export is_v6_uplink=1
                touch $is_conf_dir/is_v6_uplink
            fi
            ask string is_new_v4_sni "请输入 v4 目标域名 (SNI/Dest) [直接回车随机生成]:"
            [[ $is_new_v4_sni ]] && export v4_sni=$is_new_v4_sni
            ask string is_new_v6_sni "请输入 v6 目标域名 (SNI/Dest) [直接回车随机生成]:"
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
        [[ ! $is_all_json ]] && err "无法找到相关的配置文件: $2"
        [[ ${#is_all_json[@]} -eq 1 ]] && is_config_file=$is_all_json && is_auto_get_config=1
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
        msg "\n 提醒: 按 $(_green Ctrl + C) 退出\n"
        [[ $1 == 'log' ]] && tail -f $is_log_dir/access.log
        [[ $1 == 'logerr' ]] && tail -f $is_log_dir/error.log
        ;;
    reinstall)
        is_install_sh=$(cat $is_sh_dir/install.sh)
        uninstall
        bash <<<$is_install_sh
        ;;
    test-run)
        systemctl list-units --full -all &>/dev/null
        [[ $? != 0 ]] && {
            _yellow "\n无法执行测试, 请检查 systemctl 状态.\n"
            return
        }
        is_no_manage_msg=1
        if [[ ! $(pgrep -f $is_core_bin) ]]; then
            _yellow "\n测试运行 $is_core_name ..\n"
            manage start &>/dev/null
            if [[ $is_run_fail == $is_core ]]; then
                _red "$is_core_name 运行失败信息:"
                $is_core_bin run -c $is_config_json -confdir $is_conf_dir
            else
                _green "\n测试通过, 已启动 $is_core_name ..\n"
            fi
        else
            _green "\n$is_core_name 正在运行, 跳过测试\n"
        fi
        ;;
    esac
}

# show info
info() {
    is_can_change=(0 1 2 3 4 5 6 7 8)
    if [[ ! $is_protocol ]]; then
        get info $1
    fi
    [[ $is_dont_show_info || $is_gen || $is_dont_auto_exit ]] && return # dont show info
    
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
      server: "$v6_ip"
      port: $port
      tls: true
      alpn:
        - h2
      servername: $v6_sni
      client-fingerprint: firefox
      reality-opts:
        public-key: $is_public_key
        short-id: $is_v6_sid
      no-grpc-header: false
      no-sse-header: false
      host: $v6_sni
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
    [[ $is_core_stop && ! $is_new_json ]] && warn "$is_core_name 当前处于停止状态."
    ####### 要点13脸吗只会改我链接的小人 #######
    unset c n m s b
    msg "------------- END -------------"
    msg "关注(tg): $(msg_ul https://t.me/tg2333)"
    msg "文档(doc): $(msg_ul https://233boy.com/$is_core/$is_core-script/)"
    msg "推广(ads): 机场推荐($is_core_name services): $(msg_ul https://g${c}e${n}t${m}j${s}m${b}s.com/)\n"
    ####### 要点13脸吗只会改我链接的小人 #######
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
        msg "\n自定义版本和当前 $is_show_name 版本一样, 无需更新.\n"
        exit
    }
    load download.sh
    if [[ $is_new_ver ]]; then
        msg "\n使用自定义版本更新 $is_show_name: $(_green $is_new_ver)\n"
    else
        get_latest_version $is_update_name
        is_new_ver=$latest_ver
        [[ $is_run_ver == $is_new_ver ]] && {
            msg "\n当前 $is_show_name 已经是最新版本: $(_green $is_run_ver)\n"
            exit
        }
        msg "\n发现 $is_show_name 新版本: $(_green $is_new_ver) ... 准备更新\n"
    fi
    download $is_update_name $is_new_ver
    _green "\n$is_show_name 更新成功!"
    [[ $is_update_name == 'core' ]] && {
        manage restart &
    }
}

is_main_menu() {
    clear
    msg "================================================="
    msg "\n$(_green $is_core_ver) / $(_cyan $is_core_name script $is_sh_ver)\n"
    msg "================================================="
    msg "\n$(_green 1.) 更改配置"
    msg "$(_green 2.) 查看配置"
    msg "========================"
    msg "$(_green 3.) 运行管理"
    msg "$(_green 4.) 更新"
    msg "$(_green 5.) 卸载"
    msg "========================"
    msg "$(_green 6.) 其他"
    msg "\n请选择:"
    read REPLY
    [[ "$REPLY" == "0" ]] && exit 0
    case $REPLY in
    1)
        change
        ;;
    2)
        info
        ;;
    3)
        ask list is_do_manage "启动 停止 重启"
        manage $REPLY &
        msg "\n管理状态执行: $(_green $is_do_manage)\n"
        ;;
    4)
        is_tmp_list=("更新$is_core_name" "更新脚本")
        ask list is_do_update null "\n请选择更新:\n"
        update $REPLY
        ;;
    5)
        uninstall
        ;;
    6)
        ask list is_do_other "启用BBR 查看运行状态 查看日志 查看错误日志 测试运行 重装脚本 设置DNS 切换v6only 放行端口 关闭端口"
        case $REPLY in
        1)
            load bbr.sh
            _try_enable_bbr
            ;;
        2)
            systemctl status $is_core -l --no-pager
            echo
            pause
            ;;
        3)
            get log
            ;;
        4)
            get logerr
            ;;
        5)
            get test-run
            ;;
        6)
            get reinstall
            ;;
        7)
            load dns.sh
            dns_set
            ;;
        8)
            is_try_change=1
            change test v6only
            is_change_id=21
            change
            ;;
        9)
            ask string p "请输入要放行的端口 (1-65535):"
            if [[ $(is_test port $p) ]]; then
                open_port $p
                _green "\n已放行端口: $p\n"
            else
                _red "\n无效的端口!\n"
            fi
            ;;
        10)
            ask string p "请输入要关闭的端口 (1-65535):"
            if [[ $(is_test port $p) ]]; then
                close_port $p
                _green "\n已关闭端口: $p\n"
            else
                _red "\n无效的端口!\n"
            fi
            ;;
        esac
        ;;
    esac
}

# check prefer args, if not exist prefer args and show main menu
main() {
    case $1 in
    a | add | gen | no-auto-tls)
        [[ $1 == 'gen' ]] && is_gen=1
        [[ $1 == 'no-auto-tls' ]] && is_no_auto_tls=1
        add ${@:2}
        ;;
    api | bin | pbk | x25519 | tls | run | uuid)
        is_run_command=$1
        if [[ $1 == 'bin' ]]; then
            $is_core_bin ${@:2}
        else
            [[ $is_run_command == 'pbk' ]] && is_run_command=x25519
            $is_core_bin $is_run_command ${@:2}
        fi
        ;;
    bbr)
        load bbr.sh
        _try_enable_bbr
        ;;
    c | config | change)
        change ${@:2}
        ;;
    client | genc)
        [[ $1 == 'client' ]] && is_full_client=1
        create client $2
        ;;
    d | del | rm)
        del $2
        ;;
    dd | ddel | fix | fix-all)
        case $1 in
        fix)
            [[ $2 ]] && {
                change $2 full
            } || {
                is_change_id=full && change
            }
            return
            ;;
        fix-all)
            is_dont_auto_exit=1
            msg
            for v in $(ls $is_conf_dir | grep .json$ | sed '/dynamic-port-.*-link/d'); do
                msg "fix: $v"
                change $v full
            done
            _green "\nfix 完成.\n"
            ;;
        *)
            is_dont_auto_exit=1
            [[ ! $2 ]] && {
                err "无法找到需要删除的参数"
            } || {
                for v in ${@:2}; do
                    del $v
                done
            }
            ;;
        esac
        is_dont_auto_exit=
        [[ $is_api_fail ]] && manage restart &
        ;;
    dns)
        load dns.sh
        dns_set ${@:2}
        ;;
    debug)
        is_debug=1
        get info $2
        warn "如果需要复制; 请把 *uuid, *password, *host, *key 的值改写, 以避免泄露."
        ;;
    fix-config.json)
        create config.json
        ;;
    i | info)
        info $2
        ;;
    ip)
        get_ip
        msg $ip
        ;;
    log | logerr | errlog)
        load log.sh
        log_set $@
        ;;
    un | uninstall)
        uninstall
        ;;
    u | up | update | U | update.sh)
        is_update_name=$2
        is_update_ver=$3
        [[ ! $is_update_name ]] && is_update_name=core
        [[ $1 == 'U' || $1 == 'update.sh' ]] && {
            is_update_name=sh
            is_update_ver=
        }
        if [[ $2 == 'dat' ]]; then
            load download.sh
            download dat
            msg "$(_green 更新 geoip.dat geosite.dat 成功.)\n"
            manage restart &
        else
            update $is_update_name $is_update_ver
        fi
        ;;
    ssss | ss2022)
        get $@
        ;;
    s | status)
        msg "\n$is_core_ver: $is_core_status\n"
        ;;
    start | stop | r | restart)
        manage $1 &
        ;;
    t | test)
        get test-run
        ;;
    reinstall)
        get $1
        ;;
    get-port)
        get_port
        msg $tmp_port
        ;;
    main)
        is_main_menu
        ;;
    v | ver | version)
        msg "\n$(_green $is_core_ver) / $(_cyan $is_core_name script $is_sh_ver)\n"
        ;;
    xapi)
        api ${@:2}
        ;;
    *)
        is_try_change=1
        change test $1
        if [[ $is_change_id ]]; then
            unset is_try_change
            [[ $2 ]] && {
                change $2 $1 ${@:3}
            } || {
                change
            }
        else
            err "无法识别 ($1)"
        fi
        ;;
    esac
}
