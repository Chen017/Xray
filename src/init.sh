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
_line() { echo -e "${gray}────────────────────────────────────────────────${none}"; }
_section() { echo -e "${cyan} ── $@ ──${none}"; }
_menu() { printf "  ${green}%2s.${none} %s\n" "$1" "$2"; }
_kv() { printf "  ${gray}%-14s${none}%b\n" "$1" "$2"; }
_ok() { echo -e "  ${green}[✓]${none} $@"; }
_fail() { echo -e "  ${red}[✗]${none} $@"; }
_info() { echo -e "  ${cyan}[i]${none} $@"; }
_step() { echo -e "  ${blue}>>>${none} $@"; }

is_err="${red}[错误]${none}"
is_warn="${yellow}[警告]${none}"

err() {
    echo -e "\n  ${red}[错误]${none} $@\n"
    [[ $is_dont_auto_exit ]] && return
    exit 1
}

warn() {
    echo -e "\n  ${yellow}[警告]${none} $@\n"
}

# pause
pause() {
    echo
    echo -ne "  ${gray}按 ${green}Enter${gray} 继续, 或 ${red}Ctrl+C${gray} 取消 ...${none}"
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

load core.sh
is_main_menu
