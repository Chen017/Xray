#!/bin/bash
# Run xray.sh -> init.sh -> load() -> startup probes -> menu in a fresh Bash process.
# Only installation paths and dependency installation are redirected for the fixture.
(
    entry_root="$scratch/entrypoint"
    mkdir -p "$entry_root/sh" "$entry_root/conf"
    cp -a "$repo/src" "$entry_root/sh/src"
    cp "$is_config_json" "$entry_root/config.json"
    cp -a "$is_conf_dir/." "$entry_root/conf/"
    printf '1\n' > "$entry_root/.schema-version"
    printf '2\n' > "$entry_root/.maintenance-version"
    sed -e "s@is_core_dir=/usr/local/etc/\$is_core@is_core_dir=$entry_root@" \
        -e 's@is_core_bin=$is_core_dir/bin/$is_core@is_core_bin=$XRAY_TEST_BIN@' \
        -e 's@^is_pkg=.*@is_pkg=""@' \
        "$repo/src/init.sh" > "$entry_root/sh/src/init.sh"
    sed "s@. /usr/local/etc/xray/sh/src/init.sh@. $entry_root/sh/src/init.sh@" "$repo/xray.sh" > "$entry_root/xray.sh"
    {
        printf 'repo=%q\n' "$repo"
        declare -f systemctl iptables ip6tables nft
        if [[ $(type -t jq) == function ]]; then declare -f jq; fi
        cat <<'ENV'
arch() { echo x86_64; }
clear() { :; }
ip() {
    if [[ $* == *2606:* ]]; then echo '2606:4700:4700::1111 dev eth0 src 2001:db8::10'
    else echo '1.1.1.1 dev eth0 src 203.0.113.10'; fi
}
wget() { echo 'ip=203.0.113.10'; }
timeout() { shift; "$@"; }
ping() { echo ping >> "$TEST_STATE/entry-ping.calls"; return 0; }
dig() { if [[ $* == *AAAA* ]]; then echo 2001:db8::1; else echo 203.0.113.1; fi; }
curl() {
    if [[ $1 == --version ]]; then echo 'Features: HTTP2'; return; fi
    echo curl >> "$TEST_STATE/entry-curl.calls"
    if [[ $* == *ipinfo.io* ]]; then echo 'AS123 example'; else echo -n 2; fi
}
ENV
    } > "$entry_root/environment.sh"
    for launch in 1 2; do
        check env BASH_ENV="$entry_root/environment.sh" bash "$entry_root/xray.sh" \
            <<< $'2\n1\n2\n\n0' > "$scratch/entrypoint-$launch.txt"
        check grep -q '^vless://' "$scratch/entrypoint-$launch.txt"
        check grep -q 'GFW放行: .*✓' "$scratch/entrypoint-$launch.txt"
        check test "$(wc -l < "$TEST_STATE/entry-ping.calls")" = "$((launch*2))"
        check test "$(wc -l < "$TEST_STATE/entry-curl.calls")" = "$((launch*4))"
    done
) || exit 1
pass 'fresh real entrypoint launches refresh network/SNI probes and can export a client configuration'
