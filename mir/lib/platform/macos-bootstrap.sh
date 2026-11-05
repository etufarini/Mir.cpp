#!/usr/bin/env bash
# These functions must parse in macOS Bash 3.2. Importing them has no effects.
# shellcheck disable=SC2034 # RUNTIME_CANDIDATE is consumed by runtime.sh.
bootstrap_macos() {
    local brew prefix
    RUNTIME_CANDIDATE=''
    for brew in "$(command -v brew || true)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ -n "$brew" && -x "$brew" ]] || continue
        prefix=$("$brew" --prefix 2>/dev/null) || continue
        [[ "$prefix" == /* && -d "$prefix/bin" && "$prefix" != *$'\n'* ]] || continue
        case ":$PATH:" in *":$prefix/bin:"*) ;; *) export PATH="$PATH:$prefix/bin" ;; esac
        RUNTIME_CANDIDATE="$prefix/bin/bash"
        break
    done
}

macos_dependency_hint() {
    printf 'On macOS, install the launcher dependencies and retry:\n  brew install bash coreutils findutils dialog flock\n'
}
