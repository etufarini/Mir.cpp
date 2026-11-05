#!/usr/bin/env bash
# Test-only services use isolated fixture commands, never the host platform.
source "$MIR_ROOT/lib/platform.sh"
platform_required_tools() { REQUIRED_TOOLS=(curl ss); }
platform_dependency_hint() { printf 'Missing fixture commands: %s\n' "$*"; }
platform_browser_command() { printf xdg-open; }
platform_open_url() { xdg-open "$1"; }
platform_memory_style() { printf margins; }
platform_memory_snapshot() { RAM_AVAILABLE=${TEST_RAM_AVAILABLE:-16384}; }
platform_timeout() {
    command -v timeout >/dev/null || return 1
    timeout --kill-after=1 "$@" 2>/dev/null
}
platform_find_models() { find -H "$1" \( -type f -o -xtype f \) -iname '*.gguf' ! -name '._*' -print0; }
platform_move() {
    if [[ "$3" == no-clobber ]]; then
        mv -Tn -- "$1" "$2" || [[ ( -e "$1" || -L "$1" ) && ( -e "$2" || -L "$2" ) ]];
    else mv -fT -- "$1" "$2"; fi
}
platform_listeners() {
    local remaining
    LISTENERS=$(ss -H -ltnp "sport = :$1") || return 1
    PIDS=()
    remaining=$LISTENERS
    while [[ "$remaining" =~ pid=([0-9]+) ]]; do
        PIDS+=("${BASH_REMATCH[1]}")
        remaining=${remaining#*"pid=${BASH_REMATCH[1]}"}
    done
}
