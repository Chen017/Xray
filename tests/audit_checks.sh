#!/bin/bash
# Security report regressions; all files and processes belong to the fixture.
(
    old_node="$is_conf_dir/VLESS-REALITY-443.json"
    is_core_dir="$scratch/audit-nodes"
    is_conf_dir="$is_core_dir/conf"
    is_config_json="$is_core_dir/config.json"
    mkdir -p "$is_conf_dir"
    cp "$old_node" "$is_conf_dir/first.json"
    jq '(.inbounds[] | select(.streamSettings.security=="reality")) |=
        (.port=8443 | .tag |= sub("443";"8443")) |
        (.inbounds[] | select(.streamSettings.network=="xhttp")) |=
        (.settings.clients[0].id="a633c6c5-9319-43b4-a7f0-c2f058971910" |
         .streamSettings.xhttpSettings.path="/independent-second")' "$old_node" > "$is_conf_dir/second.json"
    for file in "$is_conf_dir"/*.json; do
        json=$(jq '(.inbounds[] | select(.streamSettings.network=="xhttp")) |= (.tag="local_xhttp_stream_up" | .listen="@xhttp_inner") |
            (.inbounds[] | .settings.fallbacks[]?).dest="@xhttp_inner"' "$file")
        printf '%s\n' "$json" > "$file"
    done
    cp "$scratch/install/config.json" "$is_config_json"
    check migrate_node_entrypoints
    check jq -es '[.[] | .inbounds[] | select(.streamSettings.network=="xhttp") | .tag] | unique | length==2' "$is_conf_dir"/*.json
    check jq -es '[.[] | .inbounds[] | select(.streamSettings.network=="xhttp") | .listen] | unique | length==2' "$is_conf_dir"/*.json
    for file in "$is_conf_dir"/*.json; do
        check jq -e '.inbounds[2].listen as $socket | all(.inbounds[0:2][]; .settings.fallbacks[0].dest==$socket)' "$file"
    done
    check validate_config
    before=$(configuration_content "$is_core_dir")
    check migrate_node_entrypoints
    check test "$before" = "$(configuration_content "$is_core_dir")"
) || exit 1
pass 'legacy multi-node XHTTP migration is independent, preserves settings and is idempotent'

(
    fake_core="$scratch/diagnostic-core"
    printf '#!/bin/bash\nexec sleep 30\n' > "$fake_core"
    chmod +x "$fake_core"
    is_core_bin="$fake_core"
    timeout() { return 0; }
    mktemp() {
        local directory
        directory=$(command mktemp -d "$scratch/diagnostic.XXXXXX") || return 1
        printf '%s\n' "$directory" >> "$scratch/diagnostic-dirs"
        printf '%s\n' "$directory"
    }
    curl() { printf 'ip=198.51.100.1\n'; }
    trap 'printf original > "$scratch/diagnostic-parent-trap"' EXIT
    before=$(trap -p EXIT)
    check _do_single_relay_test 198.51.100.1 24443 "$transport_uuid" "$vlessenc_encryption" test
    check test "$before" = "$(trap -p EXIT)"
    curl() { return 1; }
    if _do_single_relay_test 198.51.100.1 24443 "$transport_uuid" "$vlessenc_encryption" test; then
        echo 'FAIL: failed diagnostic returned success'; exit 1
    fi
    check test "$before" = "$(trap -p EXIT)"
    while IFS= read -r directory; do check test ! -e "$directory"; done < "$scratch/diagnostic-dirs"
) || exit 1
check test -f "$scratch/diagnostic-parent-trap"
pass 'successful and failed relay diagnostics clean temporary files and preserve caller traps'
