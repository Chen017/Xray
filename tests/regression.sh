#!/bin/bash
# Isolated filesystem, fake service/firewall, real Xray config parser when XRAY_TEST_BIN is supplied.
set -eo pipefail
repo=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
export TEST_STATE="$scratch/state"
mkdir -p "$TEST_STATE"
is_core=xray
is_core_dir="$scratch/install"
is_sh_dir="$repo"
is_conf_dir="$is_core_dir/conf"
is_config_json="$is_core_dir/config.json"
is_log_dir="$scratch/log"
mkdir -p "$is_conf_dir" "$is_log_dir" "$is_core_dir/bin"
if [[ -z ${XRAY_TEST_BIN:-} ]]; then
    echo 'XRAY_TEST_BIN must point to an official Xray test runtime' >&2
    exit 1
fi
is_core_bin="$XRAY_TEST_BIN"
case "$(uname -s)" in
    MINGW*|MSYS*)
        jq() { command jq -b "$@"; }
        export XRAY_LOCATION_ASSET="$(cygpath -w "${is_core_bin%/*}")"
        export TEST_STATE="$(cygpath -m "$TEST_STATE")"
        is_log_dir=$(cygpath -m "$is_log_dir")
        ;;
    *) export XRAY_LOCATION_ASSET="${is_core_bin%/*}" ;;
esac
if ! command -v flock >/dev/null; then
    echo 'NOTE: flock unavailable here; concurrent locking is exercised on Linux CI.'
    flock() { return 0; }
fi
systemctl() {
    case "$1" in
        is-active) [[ -f "$TEST_STATE/active" ]] ;;
        restart|start)
            echo "$1" >> "$TEST_STATE/service.commands"
            if [[ -f "$TEST_STATE/fail-start" ]]; then rm "$TEST_STATE/fail-start"; return 1; fi
            touch "$TEST_STATE/active"
            ;;
        stop) rm -f "$TEST_STATE/active" ;;
        *) return 0 ;;
    esac
}
iptables() { python "$repo/tests/fake_firewall.py" v4 "$@"; }
ip6tables() { python "$repo/tests/fake_firewall.py" v6 "$@"; }
nft() { printf '%s\n' '{"nftables":[]}'; }
. <(sed '/^cmd=/,$d' "$repo/src/init.sh")
for module in runtime firewall core maintenance routing diagnostics status export menus download; do
    # Match init.sh: declarations in a sourced module must survive load() returning.
    load "$module.sh"
done
[[ $(declare -p diagnostic_cache) == 'declare -A '* ]]
[[ $(declare -p diagnostic_time) == 'declare -A '* ]]
cache_test_key='4:us.kjwing.com'
diagnostic_cache["$cache_test_key"]='startup regression sentinel'
[[ ${diagnostic_cache[$cache_test_key]} == 'startup regression sentinel' ]]
unset 'diagnostic_cache[$cache_test_key]'
check() { if ! "$@"; then printf 'FAIL: %s\n' "$*" >&2; exit 1; fi; }
pass() { printf 'PASS: %s\n' "$*"; }
get_ip() { ip=203.0.113.10; }
get_ipv6() { ipv6=2001:db8::10; }
get_port() { tmp_port=443; }
get_pbk
uuid=$("$is_core_bin" uuid)
port=443
v4_sni=us.kjwing.com
v6_sni=example.org
v4_short_ids='["12345678","abcdef1234567890"]'
v6_short_ids='["87654321","1234567890abcdef"]'
v4_path='/api/v3/updates'
# Bootstrap uses the same generator but no interactive installation prompts.
config_staging=1
_create server VLESS-REALITY
_create config.json
config_staging=0
validate_config
touch "$TEST_STATE/active"
firewall_sync
pass 'generated dual-stack REALITY/Vision/XHTTP server is accepted by the real core'

original=$(configuration_content "$is_core_dir")
check config_transaction set_outbound_strategy UseIPv6
check test "$(outbound_strategy)" = UseIPv6
check migrate_installation
check test "$(outbound_strategy)" = UseIPv6
pass 'user outbound choice survives startup migration'
check config_transaction set_outbound_strategy HappyEyeballs4
check test "$(outbound_strategy)" = HappyEyeballs4
check jq -e '.outbounds[] | select(.tag=="direct") | .settings.domainStrategy=="AsIs" and .settings.targetStrategy=="AsIs" and .streamSettings.sockopt.domainStrategy=="UseIP" and .streamSettings.sockopt.happyEyeballs.tryDelayMs==250' "$is_config_json"
pass 'real core accepts dual-stack racing without pre-resolving to a single address'

before=$(configuration_content "$is_core_dir")
touch "$TEST_STATE/fail-start"
if config_transaction set_outbound_strategy UseIPv4; then echo 'FAIL: restart failure was hidden'; exit 1; fi
check test "$before" = "$(configuration_content "$is_core_dir")"
check service_active
pass 'failed restart restores previous config and service'

invalid_change() { printf '{broken json' > "$is_config_json"; }
if config_transaction invalid_change; then echo 'FAIL: invalid config accepted'; exit 1; fi
check test "$before" = "$(configuration_content "$is_core_dir")"
pass 'invalid candidate never replaces the live config'

restarts=$(wc -l < "$TEST_STATE/service.commands")
check config_transaction set_outbound_strategy HappyEyeballs4
check test "$restarts" = "$(wc -l < "$TEST_STATE/service.commands")"
pass 'unchanged operation skips restart'

rule1='{"type":"field","domain":["domain:example.com"],"outboundTag":"direct"}'
rule2='{"type":"field","domain":["full:example.org"],"outboundTag":"block"}'
check config_transaction rules_apply add 0 "$rule1"
check config_transaction rules_apply add 0 "$rule2"
check config_transaction rules_apply move 1 null 0
check jq -e '.[0].domain[0]=="full:example.org"' "$is_custom_rules_file"
check config_transaction rules_apply edit 0 "$rule1"
check config_transaction rules_apply delete 1
check jq -e 'length==1 and .[0].domain[0]=="domain:example.com"' "$is_custom_rules_file"
pass 'routing add/edit/move/delete updates both saved and effective rules'

is_config_file=VLESS-REALITY-443.json
load_node_info
active_uuid="$uuid"
outbound_mode=direct
for mode in single split vision; do
    mihomo_node_json "$mode" 203.0.113.10 example.com 12345678 2001:db8::10 example.org 87654321 > "$scratch/$mode.json"
    check jq -e '.["reality-opts"]["short-id"] | type=="string"' "$scratch/$mode.json"
    render_mihomo < "$scratch/$mode.json" > "$scratch/$mode.yaml"
    check grep -q 'short-id: "12345678"' "$scratch/$mode.yaml"
    export_vless_link "$mode" 203.0.113.10 example.com 12345678 2001:db8::10 example.org 87654321 > "$scratch/$mode.link"
done
check jq -e '.["xhttp-opts"]["reuse-settings"] != null and .["xhttp-opts"]["download-settings"]["reuse-settings"] != null and (.["xhttp-opts"]["download-settings"] | has("sockopt")|not)' "$scratch/split.json"
pass 'all export formats preserve SID string type and XHTTP reuse settings'
check python "$repo/tests/check_exports.py" "$scratch"

get_pbk
transport_uuid=$("$is_core_bin" uuid)
check relay_generate_vlessenc
check config_transaction relay_apply_landing "$transport_uuid" "$vlessenc_decryption" 30001 "$vlessenc_encryption" 203.0.113.10 203.0.113.20
check python -c 'import json,os; from pathlib import Path; s=json.loads((Path(os.environ["TEST_STATE"])/"v4.json").read_text()); c=s["XRAY-SCRIPT"][0][-1]; rules=s[c]; assert rules[0]==["-p","tcp","-s","203.0.113.20/32","--dport","30001","-j","ACCEPT"]; assert rules[1]==["-p","tcp","--dport","30001","-j","DROP"]; assert s["FORWARD"]==[["-j","EXISTING-FORWARD"]]; assert s["OTHER-APP"]==[["-j","RETURN"]]; assert ["-p","tcp","--dport","22","-j","ACCEPT"] in s["INPUT"]'
check config_transaction relay_apply_remove landing
check config_transaction relay_apply_line 203.0.113.20 30001 "$transport_uuid" "$vlessenc_encryption" "$("$is_core_bin" uuid)"
check jq -e '.routing.rules[0].outboundTag=="relay-out"' "$is_config_json"
check config_transaction relay_apply_remove line
pass 'relay setup/removal preserves routing and firewall ownership with source guard'

restarts=$(wc -l < "$TEST_STATE/service.commands")
check close_port 443
check open_port 443
check test "$restarts" = "$(wc -l < "$TEST_STATE/service.commands")"
pass 'manual firewall changes do not restart the proxy'
. "$repo/tests/status_checks.sh"
. "$repo/tests/interactive_checks.sh"
. "$repo/tests/entrypoint_checks.sh"

# Failed DNS is unknown and multiple addresses are only a hint.
dig() { return 1; }
check bash -c 'true'
check test "$(_detect_cdn example.com 4)" = '归属：无法判断（DNS 无结果或查询失败）'
curl() { echo 'test curl must never be called by the homepage' >&2; return 99; }
_get_overview
pass 'homepage has no external network dependency; failed DNS is not marked safe'
unset -f curl dig

# The restored terminal layout keeps the original sections, labels and rich overview.
menu_output="$scratch/homepage.txt"
clear() { :; }
is_core_name=Xray
is_core_ver=26.3.27
is_sh_ver=v2.6.3
is_main_menu <<< 0 > "$menu_output"
for label in '[基础]' '[UUID]' '[ v4 ]' '[ v6 ]' '[高级]' '[状态]' 节点管理 运行控制 杂项 '查看客户端配置' '查看运行状态'; do
    check grep -Fq "$label" "$menu_output"
done
check test "$_ov_uuid" = "$(jq -r '.inbounds[0].settings.clients[0].id' "$is_conf_dir/VLESS-REALITY-443.json")"
check test "$_ov_v4_sni" = us.kjwing.com
unset -f clear
pass 'original terminal overview, sections, numbering and exit behavior are restored'

# Cached diagnostics must be scoped to the domain and address family.
calls="$TEST_STATE/curl.calls"
curl() {
    if [[ $1 == --version ]]; then echo 'Features: HTTP2'; return; fi
    echo call >> "$calls"
    if [[ $* == *ipinfo.io* ]]; then echo 'AS123 example'; else echo -n 2; fi
}
dig() { echo 203.0.113.1; }
diagnose_sni example.com 4 >/dev/null
count=$(wc -l < "$calls")
diagnose_sni example.com 4 >/dev/null
check test "$count" = "$(wc -l < "$calls")"
diagnose_sni example.org 4 >/dev/null
check test "$count" -lt "$(wc -l < "$calls")"
pass 'diagnostic cache invalidates when the SNI changes'
unset -f curl dig

release_fixture='{"tag_name":"v26.3.27","prerelease":false,"draft":false}'
curl() { printf '%s\n' "$release_fixture"; }
check get_latest_version core
check test "$latest_ver" = v26.3.27
release_fixture='{"tag_name":"v26.9.9","prerelease":true,"draft":false}'
if get_latest_version core; then echo 'FAIL: prerelease accepted as stable'; exit 1; fi
release_fixture='{"tag_name":"v26.9.9","prerelease":false,"draft":true}'
if get_latest_version core; then echo 'FAIL: draft accepted as stable'; exit 1; fi
unset -f curl
pass 'stable updater rejects prereleases and drafts'

fetch_file() { return 22; }
before=$(configuration_content "$is_core_dir")
if update_geodata; then echo 'FAIL: failed download reported success'; exit 1; fi
check test "$before" = "$(configuration_content "$is_core_dir")"
pass 'failed geodata download leaves service/config unchanged'

geo_fixture="$scratch/geodata"
mkdir -p "$geo_fixture"
for name in geoip.dat geosite.dat; do
    cp "${XRAY_TEST_BIN%/*}/$name" "$geo_fixture/$name"
    cp "$geo_fixture/$name" "$is_core_dir/bin/$name"
done
fetch_file() {
    case "$1" in
        */releases/latest) echo '{"tag_name":"test-release"}' > "$2" ;;
        *.sha256sum)
            local name="${1##*/}"; name=${name%.sha256sum}
            if [[ ${bad_checksum:-0} == 1 ]]; then printf '%064d\n' 0 > "$2"
            else sha256sum "$geo_fixture/$name" > "$2"; fi ;;
        *.dat) cp "$geo_fixture/${1##*/}" "$2" ;;
        *) return 22 ;;
    esac
}
restarts=$(wc -l < "$TEST_STATE/service.commands")
check update_geodata
check test "$restarts" = "$(wc -l < "$TEST_STATE/service.commands")"
bad_checksum=1
if update_geodata; then echo 'FAIL: corrupt geodata accepted'; exit 1; fi
for name in geoip.dat geosite.dat; do check cmp "$geo_fixture/$name" "$is_core_dir/bin/$name"; done
bad_checksum=0
pass 'unchanged geodata skips restart and bad checksums preserve both data files'

# Controlled file contents isolate replacement/rollback from protobuf parsing.
(
    validate_config() { return 0; }
    for name in geoip.dat geosite.dat; do printf 'candidate\n' > "$geo_fixture/$name"; done
    touch "$TEST_STATE/fail-start"
    if update_geodata; then echo 'FAIL: geodata restart failure hidden'; exit 1; fi
    for name in geoip.dat geosite.dat; do check cmp "${XRAY_TEST_BIN%/*}/$name" "$is_core_dir/bin/$name"; done
    check service_active
    check update_geodata
    for name in geoip.dat geosite.dat; do
        check cmp "$geo_fixture/$name" "$is_core_dir/bin/$name"
        check cmp "${XRAY_TEST_BIN%/*}/$name" "$is_core_dir/bin/$name.previous"
    done
) || exit 1
for name in geoip.dat geosite.dat; do cp "${XRAY_TEST_BIN%/*}/$name" "$is_core_dir/bin/$name"; done
pass 'geodata replacement keeps previous files and rolls back a failed service restart'

# The updater is exercised offline with intentional failure injection.
unset -f fetch_file
fixture="$scratch/fixtures"
check python "$repo/tests/update_fixtures.py" "$fixture" "$repo"
fetch_file() {
    case "$1" in
        *.zip.dgst) cp "$fixture/core.dgst" "$2" ;;
        *Xray-linux-*.zip) cp "$fixture/core.zip" "$2" ;;
        *code.zip) cp "$fixture/${script_fixture:-sh.zip}" "$2" ;;
        *) return 22 ;;
    esac
}
real_bin="$is_core_bin"
is_core_bin="$is_core_dir/bin/xray"
cp "$real_bin" "$is_core_bin"
chmod +x "$is_core_bin"
is_core_arch=64
is_core_repo=XTLS/Xray-core
is_sh_repo=Chen017/Xray
is_sh_ver=v2.5.4
old_hash=$(sha256sum "$is_core_bin" | cut -d' ' -f1)
touch "$TEST_STATE/fail-start"
if safe_update core v99.0.1; then echo 'FAIL: update restart failure hidden'; exit 1; fi
check test "$old_hash" = "$(sha256sum "$is_core_bin" | cut -d' ' -f1)"
check test "$old_hash" = "$(sha256sum "$is_core_bin.previous" | cut -d' ' -f1)"
check service_active
check safe_update core v99.0.1
check grep -q '99.0.1' "$is_core_bin"
check test "$old_hash" = "$(sha256sum "$is_core_bin.previous" | cut -d' ' -f1)"
pass 'core update validates checksums, keeps previous binary and rolls back failed restart'
is_core_bin="$real_bin"

is_sh_dir="$is_core_dir/sh"
is_sh_bin="$scratch/xray-command"
mkdir -p "$is_sh_dir"
echo 'is_sh_ver=v2.5.4' > "$is_sh_dir/xray.sh"
echo 'external patch sentinel' > "$is_sh_dir/ipquality_patch.sh"
ln -s "$is_sh_dir/xray.sh" "$is_sh_bin"
script_fixture=bad-sh.zip
if safe_update sh v2.6.3; then echo 'FAIL: invalid script accepted'; exit 1; fi
check grep -q v2.5.4 "$is_sh_dir/xray.sh"
script_fixture=incomplete-sh.zip
if safe_update sh v2.6.3; then echo 'FAIL: incomplete script package accepted'; exit 1; fi
check grep -q v2.5.4 "$is_sh_dir/xray.sh"
script_fixture=sh.zip
check safe_update sh v2.6.3
check grep -q v2.6.3 "$is_sh_dir/xray.sh"
check grep -q 'external patch sentinel' "$is_sh_dir/ipquality_patch.sh"
check grep -q v2.5.4 "$is_core_dir/.previous/sh/xray.sh"
pass 'script update rejects bad syntax, keeps previous scripts and preserves external patch files'

(
    . <(sed -n '/^download() {/,/^# get server ip/p' "$repo/install.sh")
    tmpcore="$scratch/bootstrap.zip"
    is_core_ok="$scratch/bootstrap.ok"
    is_core_ver=''
    _wget() {
        if [[ $* == *api.github.com* ]]; then echo '{"tag_name":"v99.0.1"}'; return; fi
        local target="${@: -1}"
        if [[ $* == *.dgst* ]]; then
            if [[ ${bootstrap_bad:-0} == 1 ]]; then printf 'SHA2-256= %064d\n' 0 > "$target"
            else cp "$fixture/core.dgst" "$target"; fi
        else
            [[ $* == *releases/download/v99.0.1/Xray-linux-64.zip* ]] || return 1
            cp "$fixture/core.zip" "$target"
        fi
    }
    check download core
    check cmp "$fixture/core.zip" "$is_core_ok"
    rm "$is_core_ok"
    bootstrap_bad=1
    if download core; then echo 'FAIL: bootstrap accepted bad checksum'; exit 1; fi
    check test ! -f "$is_core_ok"
) || exit 1
pass 'bootstrap pins the core release and rejects an incorrect checksum'

# Stopped service and unsupported-core behavior must not be changed by settings.
systemctl stop xray
check config_transaction set_outbound_strategy UseIPv4
if service_active; then echo 'FAIL: stopped service was started'; exit 1; fi
touch "$TEST_STATE/active"
before=$(configuration_content "$is_core_dir")
old_binary="$scratch/old-core"
printf '#!/bin/bash\necho "Xray 1.8.4"\n' > "$old_binary"
chmod +x "$old_binary"
is_core_bin="$old_binary"
if config_transaction set_outbound_strategy HappyEyeballs4; then echo 'FAIL: old core accepted racing'; exit 1; fi
check test "$before" = "$(configuration_content "$is_core_dir")"
is_core_bin="$real_bin"
pass 'settings respect stopped service and reject unsupported Happy Eyeballs cores'

# Repair can regenerate deleted units even when the installation marker exists.
export XRAY_SYSTEMD_DIR="$scratch/units" XRAY_LOGROTATE_DIR="$scratch/logrotate"
crontab() {
    if [[ $1 == -l ]]; then cat "$TEST_STATE/cron"; else cat > "$TEST_STATE/cron"; fi
}
printf '0 4 * * * %s/update_geodata.sh\n0 5 * * * /other/update_geodata.sh\n' "$is_sh_dir" > "$TEST_STATE/cron"
logrotate() { return 0; }
check install_maintenance
check grep -q '/other/update_geodata.sh' "$TEST_STATE/cron"
if grep -q "$is_sh_dir/update_geodata.sh" "$TEST_STATE/cron"; then echo 'FAIL: old cron retained'; exit 1; fi
rm "$XRAY_SYSTEMD_DIR/xray-geodata.timer"
check install_maintenance force
check test -s "$XRAY_SYSTEMD_DIR/xray-geodata.timer"
check test -s "$XRAY_LOGROTATE_DIR/xray-script"
pass 'maintenance repair recreates units and removes only the owned cron job'

if [[ $(type -t flock) == file ]]; then
    (
        exec 9>"$is_core_dir/.operation.lock"
        flock 9
        touch "$TEST_STATE/locked"
        sleep 10
    ) &
    locker=$!
    for ((n=0; n<100; n++)); do [[ ! -f "$TEST_STATE/locked" ]] || break; sleep 0.05; done
    check test -f "$TEST_STATE/locked"
    before=$(configuration_content "$is_core_dir")
    if config_transaction set_outbound_strategy UseIPv6; then kill "$locker"; echo 'FAIL: concurrent write accepted'; exit 1; fi
    check test "$before" = "$(configuration_content "$is_core_dir")"
    kill "$locker"
    wait "$locker" 2>/dev/null || true
    pass 'real flock prevents a concurrent configuration write'
fi
echo 'All isolated regression checks passed.'
