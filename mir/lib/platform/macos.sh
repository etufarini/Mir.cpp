#!/usr/bin/env bash
# macOS operations. Definitions only; bootstrap discovery lives separately.
# shellcheck disable=SC2034 # REQUIRED_TOOLS is an output consumed by the loader.
platform_required_tools() { REQUIRED_TOOLS=(curl gfind gmv lsof netstat); }
platform_browser_command() { printf open; }
platform_open_url() { open "$1"; }
platform_find_models() { gfind -H "$1" \( -type f -o -xtype f \) -iname '*.gguf' ! -name '._*' -print0; }
platform_move() {
    case "$3" in
        replace) gmv -fT -- "$1" "$2" ;;
        no-clobber)
            # Older GNU mv returns failure when a directory appeared meanwhile.
            gmv -Tn -- "$1" "$2" || [[ ( -e "$1" || -L "$1" ) && ( -e "$2" || -L "$2" ) ]] ;;
        *) return 2 ;;
    esac
}
platform_timeout() {
    local timer=gtimeout
    if ! command -v "$timer" >/dev/null; then timer=timeout; fi
    command -v "$timer" >/dev/null || return 1
    "$timer" --kill-after=1 "$@" 2>/dev/null
}
# Apple Silicon uses one physical pool for native CPU/Metal allocations.
# Other Macs expose system RAM only; accelerator forecasts remain unknown.
platform_memory_style() {
    if [[ $(sysctl -n hw.optional.arm64 2>/dev/null) == 1 ]]; then printf shared;
    else printf system; fi
}
# shellcheck disable=SC2034 # RAM_AVAILABLE is consumed by shared memory code.
platform_memory_snapshot() {
    local output line page_size='' free='' inactive='' speculative='' name value
    RAM_AVAILABLE=''
    output=$(LC_ALL=C vm_stat 2>/dev/null) || return 0
    while IFS= read -r line; do
        case "$line" in
            'Mach Virtual Memory Statistics:'*)
                [[ -z "$page_size" && "$line" =~ \(page[[:space:]]size[[:space:]]of[[:space:]]([0-9]{1,7})[[:space:]]bytes\) ]] || return 0
                page_size=$((10#${BASH_REMATCH[1]}))
                (( page_size > 0 && page_size <= 1048576 && (page_size & (page_size - 1)) == 0 )) || return 0 ;;
            'Pages free:'*|'Pages inactive:'*|'Pages speculative:'*)
                [[ "$line" =~ ^Pages[[:space:]](free|inactive|speculative):[[:space:]]+([0-9]{1,10})\.$ ]] || return 0
                name=${BASH_REMATCH[1]}; value=$((10#${BASH_REMATCH[2]}))
                case "$name" in
                    free) [[ -z "$free" ]] || return 0; free=$value ;;
                    inactive) [[ -z "$inactive" ]] || return 0; inactive=$value ;;
                    speculative) [[ -z "$speculative" ]] || return 0; speculative=$value ;;
                esac ;;
        esac
    done <<< "$output"
    [[ -n "$page_size" && -n "$free" && -n "$inactive" && -n "$speculative" ]] || return 0
    # vm_stat subtracts speculative pages from its displayed free count.
    # Add them once to match the free + inactive estimate used by psutil.
    RAM_AVAILABLE=$(((free + inactive + speculative) * page_size / 1048576))
}
platform_dependency_hint() { macos_dependency_hint; }
platform_listeners() {
    local pid line sockets proto address state _
    PIDS=()
    # netstat sees listeners even when lsof cannot disclose their processes.
    sockets=$(netstat -an -p tcp) || return 1
    LISTENERS=''
    while read -r proto _ _ address _ state _; do
        if [[ "$proto" == tcp* && "$state" == LISTEN && "${address##*.}" == "$1" ]]; then
            LISTENERS+="$proto $address $state"$'\n'
        fi
    done <<< "$sockets"
    if [[ -n "$LISTENERS" ]]; then
        # Exit 1 means no visible matches, not necessarily a free port.
        if line=$(lsof -nP -a -iTCP:"$1" -sTCP:LISTEN -Fp 2>/dev/null); then
            while IFS= read -r pid; do
                [[ "$pid" =~ ^p([0-9]+)$ ]] && PIDS+=("${BASH_REMATCH[1]}")
            done < <(printf '%s\n' "$line" | sort -u)
        fi
    fi
}

platform_ensure_dependencies() {
    local group=$1 index tool
    local -a tools=() formulas=() missing=()
    case "$group" in
        metal) return 0 ;;
        launcher) tools=(gmv gfind dialog flock); formulas=(coreutils findutils dialog flock) ;;
        build) tools=(cmake python3 gtimeout); formulas=(cmake python coreutils) ;;
        *) printf 'Unknown dependency group: %s\n' "$group" >&2; return 1 ;;
    esac
    if [[ "$group" == build ]]; then
        if ! xcode-select -p >/dev/null 2>&1 || ! xcrun --find clang >/dev/null 2>&1 ||
            ! xcrun --find clang++ >/dev/null 2>&1 || ! xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1; then
            printf 'Apple command line tools and a macOS SDK are required. Run xcode-select --install, finish installation, then retry.\n' >&2
            return 1
        fi
        for tool in git make cc c++; do
            command -v "$tool" >/dev/null || { printf 'Required developer tool not found: %s. Check your Apple command line tools installation.\n' "$tool" >&2; return 1; }
        done
    fi
    for index in "${!tools[@]}"; do
        command -v "${tools[index]}" >/dev/null || missing+=("${formulas[index]}")
    done
    if (( ${#missing[@]} > 0 )); then
        if [[ -n ${2:-} ]]; then
            "$2" macos_install_packages "${missing[@]}" || return 1
        else
            macos_install_packages "${missing[@]}" || return 1
        fi
        for tool in "${tools[@]}"; do
            command -v "$tool" >/dev/null || { printf 'Required command still unavailable after installation: %s\n' "$tool" >&2; return 1; }
        done
    fi
    if [[ "$group" == launcher ]]; then check_dependencies install || return 1; fi
    return 0
}

platform_build_backends() { printf '%s\n' cpu CPU metal 'Metal (GPU)'; }
platform_build_flags() {
    case "$1" in
        cpu) BUILD_FLAGS=(-DGGML_METAL=OFF) ;;
        metal) BUILD_FLAGS=(-DGGML_METAL=ON) ;;
        *) return 1 ;;
    esac
}
platform_start_worker() {
    # Python supplies setsid on macOS without an extra runtime package.
    exec python3 -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$@"
}
platform_build_probe() {
    local timer=gtimeout
    if ! command -v "$timer" >/dev/null; then timer=timeout; fi
    "$timer" --foreground --kill-after=2 30 "$@"
}
