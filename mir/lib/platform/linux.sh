#!/usr/bin/env bash
# Linux operations. Definitions only; no probing or configuration on import.
# shellcheck disable=SC2034 # REQUIRED_TOOLS is an output consumed by the loader.
platform_required_tools() { REQUIRED_TOOLS=(curl ss); }
platform_browser_command() { printf xdg-open; }
platform_open_url() { xdg-open "$1"; }
platform_find_models() { find -H "$1" \( -type f -o -xtype f \) -iname '*.gguf' ! -name '._*' -print0; }
platform_move() {
    case "$3" in
        replace) mv -fT -- "$1" "$2" ;;
        no-clobber)
            # Older GNU mv returns failure when a directory appeared meanwhile.
            mv -Tn -- "$1" "$2" || [[ ( -e "$1" || -L "$1" ) && ( -e "$2" || -L "$2" ) ]] ;;
        *) return 2 ;;
    esac
}
platform_timeout() {
    command -v timeout >/dev/null || return 1
    timeout --kill-after=1 "$@" 2>/dev/null
}
platform_memory_style() { printf margins; }
# shellcheck disable=SC2034 # RAM_AVAILABLE is an output consumed by shared memory code.
platform_memory_snapshot() {
    local key value rest
    RAM_AVAILABLE=''
    if [[ -r /proc/meminfo ]]; then
        while read -r key value rest; do
            if [[ "$key" == MemAvailable: && "$value" =~ ^[0-9]+$ ]]; then RAM_AVAILABLE=$((value / 1024)); break; fi
        done < /proc/meminfo
    fi
}
platform_listeners() {
    local pid
    LISTENERS=$(ss -H -ltnp "sport = :$1") || return 1
    PIDS=()
    while IFS= read -r pid; do
        [[ -z "$pid" ]] || PIDS+=("$pid")
    done < <(printf '%s' "$LISTENERS" | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -un)
}
platform_dependency_hint() {
    local tool package
    local -A packages=()
    for tool in "$@"; do
        case "$tool" in
            bash|curl|tar|gzip|dialog|grep) package="$tool" ;;
            flock) package=util-linux ;;
            ss) package=iproute2 ;;
            ps) package=procps ;;
            find) package=findutils ;;
            *) package=coreutils ;;
        esac
        packages[$package]=1
    done
    printf 'On Ubuntu/Debian, install the missing packages and retry:\n  sudo apt install'
    printf ' %s' "${!packages[@]}"
    printf '\n'
}
