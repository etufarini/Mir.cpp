#!/usr/bin/env bash
# These functions must parse in macOS Bash 3.2. Importing them has no effects.
# shellcheck disable=SC2034 # RUNTIME_CANDIDATE is consumed by runtime.sh.
bootstrap_macos() {
    local brew prefix
    RUNTIME_CANDIDATE=''; RUNTIME_BREW=''
    for brew in "$(command -v brew || true)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ -n "$brew" && -x "$brew" ]] || continue
        prefix=$("$brew" --prefix 2>/dev/null) || continue
        [[ "$prefix" == /* && -d "$prefix/bin" && "$prefix" != *$'\n'* ]] || continue
        case ":$PATH:" in *":$prefix/bin:"*) ;; *) export PATH="$PATH:$prefix/bin" ;; esac
        RUNTIME_BREW=$brew
        RUNTIME_CANDIDATE="$prefix/bin/bash"
        break
    done
}

macos_dependency_hint() {
    printf 'On macOS, install the launcher dependencies and retry:\n  brew install bash coreutils findutils dialog flock\n'
}

# Shared by the Bash 3.2 installer bootstrap and the modern build menus.
macos_install_packages() {
    local answer brew=${RUNTIME_BREW:-brew}
    printf 'Missing dependency packages: %s\n' "$*" >&2
    if ! command -v "$brew" >/dev/null; then
        printf 'Homebrew is required. Install it, then run: brew install %s\n' "$*" >&2
        return 1
    fi
    if [[ ! -r /dev/tty || ! -w /dev/tty ]] || ! { printf 'Install these packages with Homebrew? [y/N] ' > /dev/tty; } 2>/dev/null; then
        printf 'A terminal is required to approve installation. Run: brew install %s\n' "$*" >&2
        return 1
    fi
    IFS= read -r answer < /dev/tty || return 1
    case "$answer" in y|Y|yes|YES) ;; *) printf 'Dependency installation canceled.\n' >&2; return 1 ;; esac
    HOMEBREW_NO_AUTO_UPDATE=1 "$brew" install --formula "$@" < /dev/tty || {
        printf 'Homebrew installation failed. Check its output and retry. The existing installation was kept.\n' >&2
        return 1
    }
}
