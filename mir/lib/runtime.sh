#!/usr/bin/env bash
# Bootstrap dispatch only; all code here must parse in Bash 3.2.
detect_platform() {
    case "$(uname -s)" in
        Linux) PLATFORM_ID=linux ;;
        Darwin) PLATFORM_ID=macos ;;
        *) printf 'Unsupported operating system. See README.md.\n' >&2; return 1 ;;
    esac
}

configure_runtime() {
    local candidate
    local -a candidates=("$(command -v bash || true)")
    detect_platform || return 1
    if [[ "$PLATFORM_ID" == macos ]]; then
        if ! declare -F bootstrap_macos >/dev/null; then
            source "$MIR_ROOT/lib/platform/macos-bootstrap.sh" || return 1
        fi
        bootstrap_macos
        candidates+=("$RUNTIME_CANDIDATE")
    fi
    RUNTIME_BASH=$BASH
    if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )); then return 0; fi
    for candidate in "${candidates[@]}"; do
        [[ -n "$candidate" && -x "$candidate" ]] || continue
        if "$candidate" -c '(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) ))' 2>/dev/null; then
            RUNTIME_BASH=$candidate
            return 0
        fi
    done
    if [[ "$PLATFORM_ID" == macos && "${1:-}" == install ]]; then
        macos_install_packages bash || return 1
        # Retry discovery without installation permission to avoid prompt loops.
        configure_runtime check
        return $?
    fi
    printf 'Mir.cpp requires Bash 4.4 or newer.\n' >&2
    if [[ "$PLATFORM_ID" == macos ]]; then macos_dependency_hint >&2; fi
    printf 'Install a compatible Bash and retry the same command. See README.md.\n' >&2
    return 1
}
