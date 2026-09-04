#!/bin/bash

author=Chen017
# github=https://github.com/233boy/xray

# ─── bash fonts colors ────────────────────────────────────
red='\e[31m'
yellow='\e[33m'
gray='\e[90m'
green='\e[92m'
blue='\e[94m'
magenta='\e[95m'
cyan='\e[96m'
bold='\e[1m'
dim='\e[2m'
none='\e[0m'

_red() { echo -e "${red}$@${none}"; }
_blue() { echo -e "${blue}$@${none}"; }
_cyan() { echo -e "${cyan}$@${none}"; }
_green() { echo -e "${green}$@${none}"; }
_yellow() { echo -e "${yellow}$@${none}"; }
_magenta() { echo -e "${magenta}$@${none}"; }
_gray() { echo -e "${gray}$@${none}"; }
_bold() { echo -e "${bold}$@${none}"; }
_red_bg() { echo -e "\e[41m$@${none}"; }

# ─── formatted output helpers ─────────────────────────────
_line() { echo -e "${gray}──────────────────────────────────────────────────${none}"; }
_section() { echo -e "${cyan} ── $@ ──${none}"; }
_menu() { printf "  ${green}%2s.${none} %s\n" "$1" "$2"; }
_kv() { printf "  ${gray}%-14s${none}%b\n" "$1" "$2"; }

# Status Badges
b_ok="${green}[OK]${none}"
b_warn="${yellow}[WARN]${none}"
b_err="${red}[ERROR]${none}"
b_info="${cyan}[INFO]${none}"

_ok() { echo -e "  ${b_ok} $@"; }
_fail() { echo -e "  ${b_err} $@"; }
_info() { echo -e "  ${b_info} $@"; }
_step() { echo -e "  ${blue}>>>${none} $@"; }

is_err="${b_err}"
is_warn="${b_warn}"

err() {
    echo -e "\n  ${b_err} $@\n"
    [[ $is_dont_auto_exit ]] && return
    exit 1
}

warn() {
    echo -e "\n  ${b_warn} $@\n"
}

# ─── Standard Prompts ─────────────────────────────────────
# prompt_confirm: Prompts user for Y/n confirmation. Returns 0 for Y, 1 for N.
prompt_confirm() {
    local prompt_msg="$1"
    local default="${2:-y}"
    local reply
    if [[ "$default" == "y" ]]; then
        echo -ne "  ${blue}?${none} ${prompt_msg} [Y/n]: "
    else
        echo -ne "  ${blue}?${none} ${prompt_msg} [y/N]: "
    fi
    read -r reply
    reply=${reply:-$default}
    [[ "${reply,,}" == "y" || "${reply,,}" == "yes" ]]
}

# prompt_input: Prompts for a string input with an optional default.
prompt_input() {
    local prompt_msg="$1"
    local var_name="$2"
    local default_val="$3"
    if [[ -n "$default_val" ]]; then
        echo -ne "  ${blue}?${none} ${prompt_msg} [${cyan}${default_val}${none}]: "
    else
        echo -ne "  ${blue}?${none} ${prompt_msg}: "
    fi
    local reply
    read -r reply
    eval "$var_name=\"\${reply:-\$default_val}\""
}

# pause
pause() {
    echo
    echo -ne "  ${gray}按 ${green}Enter${gray} 返回主菜单, 或 ${red}Ctrl+C${gray} 退出脚本 ...${none}"
    read -rs -d $'\n'
    echo
}

# load bash script.
load() {
    . $is_sh_dir/src/$1
}

# wget add --no-check-certificate
_wget() {
    # [[ $proxy ]] && export https_proxy=$proxy
    wget --no-check-certificate "$@"
}

# yum or apt-get
cmd=$(type -P apt-get || type -P yum)

# x64
case $(arch) in
amd64 | x86_64)
    is_core_arch="64"
    ;;
*aarch64* | *armv8*)
    is_core_arch="arm64-v8a"
    ;;
*)
    err "此脚本仅支持 64 位系统..."
    ;;
esac

is_core=xray
is_core_name=Xray
is_core_dir=/usr/local/etc/$is_core
is_core_bin=$is_core_dir/bin/$is_core
is_core_repo=xtls/$is_core-core
is_conf_dir=$is_core_dir/conf
is_log_dir=/var/log/$is_core
is_sh_bin=/usr/local/bin/$is_core
is_sh_dir=$is_core_dir/sh
is_sh_repo=$author/$is_core
is_pkg="wget curl unzip jq"

check_dependencies() {
    local missing_pkgs=""
    for pkg in $is_pkg; do
        if ! command -v "$pkg" &>/dev/null; then
            missing_pkgs="$missing_pkgs $pkg"
        fi
    done
    if [[ -n "$missing_pkgs" ]]; then
        _info "正在安装缺失的依赖:$missing_pkgs ..."
        $cmd update -y &>/dev/null || true
        $cmd install -y $missing_pkgs &>/dev/null || true
        for pkg in $is_pkg; do
            if ! command -v "$pkg" &>/dev/null; then
                err "依赖安装失败: $pkg, 请手动安装后再运行。"
            fi
        done
    fi
}

# ─── auto install geodata cronjob ─────────────────────────
if [[ ! -f /usr/local/etc/xray/sh/update_geodata.sh ]]; then
    cat << 'EOF' > /usr/local/etc/xray/sh/update_geodata.sh
#!/bin/bash
TARGET_DIR="/usr/local/etc/xray/bin"
mkdir -p $TARGET_DIR

curl -sL -o "${TARGET_DIR}/geoip.dat" "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
curl -sL -o "${TARGET_DIR}/geosite.dat" "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"

systemctl restart xray
EOF
    chmod +x /usr/local/etc/xray/sh/update_geodata.sh
fi
# ensure crontab is available, install cron if missing
if ! command -v crontab &>/dev/null; then
    if [[ $cmd =~ apt ]]; then
        $cmd install -y cron &>/dev/null && systemctl enable --now cron &>/dev/null
    else
        $cmd install -y cronie &>/dev/null && systemctl enable --now crond &>/dev/null
    fi
fi
if command -v crontab &>/dev/null; then
    if ! crontab -l 2>/dev/null | grep -q "update_geodata.sh"; then
        (crontab -l 2>/dev/null; echo "0 4 * * * /usr/local/etc/xray/sh/update_geodata.sh >/var/log/xray/geodata_update.log 2>&1") | crontab -
    fi
fi

# ─── auto setup iptables firewall (one-time) ─────────────
if [[ ! -f $is_core_dir/.fw_init_done ]]; then
    # auto-detect SSH port (sshd_config → ss → fallback 22)
    is_ssh_port=$(grep -E '^\s*Port\s+[0-9]+' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)
    [[ -z $is_ssh_port ]] && is_ssh_port=$(ss -tlnp 2>/dev/null | grep -E 'sshd|"ssh"' | awk '{print $4}' | sed 's/.*://' | head -1)
    [[ -z $is_ssh_port ]] && is_ssh_port=22

    # install iptables + persistence tools
    if ! command -v iptables &>/dev/null; then
        if [[ $cmd =~ apt ]]; then
            DEBIAN_FRONTEND=noninteractive $cmd install -y iptables ip6tables netfilter-persistent iptables-persistent &>/dev/null
        else
            $cmd install -y iptables iptables-services &>/dev/null
            systemctl enable --now iptables &>/dev/null
            systemctl enable --now ip6tables &>/dev/null
        fi
    else
        # iptables already present — ensure persistence tools exist
        if [[ $cmd =~ apt ]] && ! dpkg -l iptables-persistent &>/dev/null 2>&1; then
            DEBIAN_FRONTEND=noninteractive $cmd install -y netfilter-persistent iptables-persistent &>/dev/null
        fi
    fi

    if command -v iptables &>/dev/null; then
        # ── IPv4: temp ACCEPT → flush → rules → DROP ──
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT
        iptables -F
        iptables -X
        iptables -Z

        iptables -A INPUT -i lo -j ACCEPT
        iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        iptables -A INPUT -p icmp -j ACCEPT
        iptables -A INPUT -p tcp --dport $is_ssh_port -j ACCEPT
        iptables -A INPUT -p tcp --dport 443 -j ACCEPT
        iptables -A INPUT -p udp --dport 443 -j ACCEPT

        iptables -P INPUT DROP
        iptables -P FORWARD DROP
        iptables -P OUTPUT ACCEPT

        # ── IPv6: temp ACCEPT → flush → rules → DROP ──
        if command -v ip6tables &>/dev/null; then
            ip6tables -P INPUT ACCEPT
            ip6tables -P FORWARD ACCEPT
            ip6tables -P OUTPUT ACCEPT
            ip6tables -F
            ip6tables -X
            ip6tables -Z

            ip6tables -A INPUT -i lo -j ACCEPT
            ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
            ip6tables -A INPUT -p ipv6-icmp -j ACCEPT
            ip6tables -A INPUT -p tcp --dport $is_ssh_port -j ACCEPT
            ip6tables -A INPUT -p tcp --dport 443 -j ACCEPT
            ip6tables -A INPUT -p udp --dport 443 -j ACCEPT

            ip6tables -P INPUT DROP
            ip6tables -P FORWARD DROP
            ip6tables -P OUTPUT ACCEPT
        fi

        # ── persist rules & enable on boot ──
        if [[ $(type -P netfilter-persistent) ]]; then
            netfilter-persistent save &>/dev/null
            systemctl enable netfilter-persistent &>/dev/null
        elif [[ $(type -P iptables-save) && -d /etc/iptables ]]; then
            iptables-save > /etc/iptables/rules.v4
            [[ $(type -P ip6tables-save) ]] && ip6tables-save > /etc/iptables/rules.v6
        elif [[ $(type -P service) ]]; then
            service iptables save &>/dev/null 2>&1
            service ip6tables save &>/dev/null 2>&1
        fi
        > $is_core_dir/.fw_init_done
    fi
fi

check_dependencies
is_config_json=$is_core_dir/config.json

# core ver
is_core_ver=$($is_core_bin version | head -n1 | cut -d " " -f1-2)

if [[ $(pgrep -f $is_core_bin) ]]; then
    is_core_status="${green}● 运行中${none}"
    is_core_status_short="${green}运行中${none}"
else
    is_core_status="${red}● 已停止${none}"
    is_core_status_short="${red}已停止${none}"
    is_core_stop=1
fi

# ─── Happy Eyeballs migration ────────────────────────────
# Auto-upgrade domainStrategy from UseIPv4 to UseIPv4v6
# This runs on every script load to ensure existing installs get the update
if [[ -f $is_config_json ]] && command -v jq &>/dev/null; then
    _current_ds=$(jq -r '.outbounds[]? | select(.tag == "direct") | .settings.domainStrategy // empty' "$is_config_json" 2>/dev/null)
    if [[ "$_current_ds" == "UseIPv4" ]]; then
        jq '(.outbounds[] | select(.tag == "direct") | .settings.domainStrategy) = "UseIPv4v6"' "$is_config_json" > "${is_config_json}.tmp" && \
        mv -f "${is_config_json}.tmp" "$is_config_json" 2>/dev/null
    fi
    unset _current_ds
fi

if [[ -d $is_conf_dir ]] && command -v jq &>/dev/null; then
    for conf in "$is_conf_dir"/*.json; do
        [[ -f "$conf" && "$conf" != *"custom_rules.json" ]] || continue
        if grep -q "limitFallbackUpload\|tcpCongestion\|serverMaxHeaderBytes" "$conf" 2>/dev/null || grep -q '"noGRPCHeader": false' "$conf" 2>/dev/null || grep -q '""' "$conf" 2>/dev/null; then
            _temp_conf=$(mktemp)
            if jq '
                del(.inbounds[].streamSettings.realitySettings.limitFallbackUpload, .inbounds[].streamSettings.realitySettings.limitFallbackDownload, .inbounds[].streamSettings.sockopt.tcpCongestion) |
                (
                    .inbounds[]? | select(.streamSettings.network == "xhttp") | .streamSettings.xhttpSettings
                ) |= (
                    .noGRPCHeader = true |
                    .noSSEHeader = true |
                    del(.serverMaxHeaderBytes)
                ) |
                (
                    .inbounds[]? | select(.streamSettings.security == "reality") | .streamSettings.realitySettings.shortIds
                ) |= map(select(. != ""))
            ' "$conf" > "$_temp_conf" 2>/dev/null; then
                if [[ -s "$_temp_conf" ]]; then
                    mv -f "$_temp_conf" "$conf"
                fi
            fi
            rm -f "$_temp_conf"
        fi
    done
fi

load core.sh
is_main_menu
