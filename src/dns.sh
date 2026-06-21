is_dns_list=(
    1.1.1.1
    8.8.8.8
)
dns_set() {
    if [[ $1 ]]; then
        case ${1,,} in
        11 | 1111 | 1.1.1.1)
            is_dns_use=${is_dns_list[0]}
            ;;
        88 | 8888 | 8.8.8.8)
            is_dns_use=${is_dns_list[1]}
            ;;
        *)
            err "无法识别 DNS 参数: $@, 目前仅支持 11 (1.1.1.1) 或 88 (8.8.8.8)"
            ;;
        esac
    else
        is_tmp_list=(${is_dns_list[@]})
        ask list is_dns_use null "\n请选择 DNS:\n"
    fi
    cat <<<$(jq '.dns.servers=["'${is_dns_use}'"]' $is_config_json) >$is_config_json
    manage restart &
    msg "\n已更新 DNS 为: $(_green $is_dns_use)\n"
}