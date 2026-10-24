#!/bin/bash
set -euo pipefail
repo=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
. "$repo/src/network_probe.sh"
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
export PROBE_TEST_LOG="$scratch/calls"
timeout() {
    local target=${!#}
    printf '%s\n' "$target" >> "$PROBE_TEST_LOG"
    case "$target" in
        sh-*.ip.zstaticcdn.com) [[ $domestic_ok == true ]] ;;
        1.1.1.1|1.0.0.1) [[ $global_ok == true ]] && { [[ $2 == bash ]] || [[ $ping_ok == true ]]; } ;;
        *) echo 'unexpected destination' >&2; return 1 ;;
    esac
}
for domestic_ok in true false; do
    for global_ok in true false; do
        ping_ok=false
        result=$(probe_network)
        [[ $result == *"\"domestic\":$domestic_ok"* && $result == *"\"global\":$global_ok"* ]]
        case "$domestic_ok/$global_ok" in
            true/true) [[ $result == *'"code":"ok"'* ]] ;;
            false/true) [[ $result == *'"code":"domestic_unreachable"'* ]] ;;
            true/false) [[ $result == *'"code":"global_unreachable"'* ]] ;;
            false/false) [[ $result == *'"code":"network_unreachable"'* ]] ;;
        esac
    done
done
domestic_ok=false; global_ok=true; ping_ok=true
: > "$PROBE_TEST_LOG"
result=$(probe_network)
[[ $(wc -l < "$PROBE_TEST_LOG") == 4 ]] # all three domestic targets + first successful Cloudflare ping
[[ $result == *'"global":true'* ]]
domestic_ok=true; global_ok=true; ping_ok=false
: > "$PROBE_TEST_LOG"
probe_network >/dev/null
[[ $(wc -l < "$PROBE_TEST_LOG") == 3 ]] # first domestic success, failed ping, successful TCP fallback
printf 'PASS shared connectivity: four states, all domestic failures, first success, Cloudflare ping and TCP fallback\n'
