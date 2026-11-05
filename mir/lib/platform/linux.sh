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
    local -A hint_packages=()
    for tool in "$@"; do
        case "$tool" in
            bash|curl|tar|gzip|dialog|grep) package="$tool" ;;
            flock) package=util-linux ;;
            ss) package=iproute2 ;;
            ps) package=procps ;;
            find) package=findutils ;;
            *) package=coreutils ;;
        esac
        hint_packages[$package]=1
    done
    printf 'On Ubuntu/Debian, install the missing packages and retry:\n  sudo apt install'
    printf ' %s' "${!hint_packages[@]}"
    printf '\n'
}

debian_package_manager() {
    local key value distribution='' related=''
    if [[ -r /etc/os-release ]]; then
        while IFS='=' read -r key value; do
            value=${value#\"}; value=${value%\"}
            case "$key" in ID) distribution=$value ;; ID_LIKE) related=$value ;; esac
        done < /etc/os-release
    fi
    [[ " $distribution $related " == *' debian '* || " $distribution $related " == *' ubuntu '* ]] &&
        command -v apt-get >/dev/null && command -v dpkg-query >/dev/null
}

platform_ensure_dependencies() {
    local group=$1 tool package
    local -a tools packages missing=()
    case "$group" in
        launcher)
            tools=(bash curl tar gzip mktemp chmod mkdir mv ln rm flock dialog ss ps find sort grep cut dirname sleep cp)
            packages=(bash curl tar gzip coreutils coreutils coreutils coreutils coreutils coreutils util-linux dialog iproute2 procps findutils coreutils grep coreutils coreutils coreutils coreutils) ;;
        build)
            tools=(git cmake make cc c++ python3 setsid timeout)
            packages=(git cmake build-essential build-essential build-essential python3 util-linux coreutils) ;;
        vulkan) tools=(glslc vulkaninfo); packages=(glslc vulkan-tools) ;;
        cuda) tools=(nvcc); packages=(nvidia-cuda-toolkit) ;;
        *) printf 'Unknown dependency group: %s\n' "$group" >&2; return 1 ;;
    esac
    for tool in "${!tools[@]}"; do
        if ! command -v "${tools[tool]}" >/dev/null && [[ " ${missing[*]} " != *" ${packages[tool]} "* ]]; then
            missing+=("${packages[tool]}")
        fi
    done
    if debian_package_manager; then
        # Headers and certificates cannot be checked by looking for commands.
        case "$group" in
            launcher) packages=(ca-certificates) ;;
            build) packages=(libssl-dev libcurl4-openssl-dev) ;;
            vulkan) packages=(libvulkan-dev spirv-headers mesa-vulkan-drivers) ;;
            *) packages=() ;;
        esac
        for package in "${packages[@]}"; do
            [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null) == 'install ok installed' ]] || missing+=("$package")
        done
    elif (( ${#missing[@]} )); then
        printf 'Missing tools for %s: %s\nAutomatic dependency installation supports Ubuntu/Debian. Install the equivalent packages for your distribution and retry.\n' "$group" "${tools[*]}" >&2
        return 1
    fi
    (( ${#missing[@]} )) || return 0
    if [[ -n ${2:-} ]]; then
        "$2" install_dependency_packages "$group" "${missing[@]}"
    else
        install_dependency_packages "$group" "${missing[@]}"
    fi
}

install_dependency_packages() {
    local group=$1 answer
    shift
    local -a missing=("$@") command_prefix=()
    printf 'Missing dependency packages: %s\n' "${missing[*]}" >&2
    if [[ ! -r /dev/tty || ! -w /dev/tty ]] || ! { printf 'Install these packages with apt-get? [y/N] ' > /dev/tty; } 2>/dev/null; then
        printf 'A terminal is required to approve installation. Run: sudo apt-get install %s\n' "${missing[*]}" >&2
        return 1
    fi
    IFS= read -r answer < /dev/tty || return 1
    case "$answer" in y|Y|yes|YES) ;; *) printf 'Dependency installation canceled.\n' >&2; return 1 ;; esac
    if (( EUID != 0 )); then
        command -v sudo >/dev/null || { printf 'sudo is unavailable. Ask your administrator to install: %s\n' "${missing[*]}" >&2; return 1; }
        command_prefix=(sudo)
    fi
    "${command_prefix[@]}" apt-get update < /dev/tty || return 1
    # Prefer NVIDIA's toolkit when its repository is already configured.
    if [[ "$group" == cuda ]] && apt-cache show cuda-toolkit >/dev/null 2>&1; then missing=(cuda-toolkit); fi
    "${command_prefix[@]}" apt-get install --no-remove -y "${missing[@]}" < /dev/tty || {
        printf 'Dependency installation failed. Check your package repositories and retry. GPU drivers are configured separately.\n' >&2
        return 1
    }
}

platform_build_backends() { printf '%s\n' cpu CPU vulkan Vulkan cuda 'CUDA (NVIDIA; hardware validation pending)'; }
platform_build_flags() {
    BUILD_FLAGS=(-DGGML_METAL=OFF)
    case "$1" in cpu) ;; vulkan) BUILD_FLAGS+=(-DGGML_VULKAN=ON) ;; cuda) BUILD_FLAGS+=(-DGGML_CUDA=ON) ;; *) return 1 ;; esac
}
platform_start_worker() { exec setsid "$@"; }
platform_build_probe() { timeout --foreground --kill-after=2 30 "$@"; }
