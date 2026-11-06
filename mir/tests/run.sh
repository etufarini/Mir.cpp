#!/usr/bin/env bash
set -euo pipefail
MIR_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$MIR_ROOT/lib/runtime.sh"
configure_runtime check
if [[ "$RUNTIME_BASH" != "$BASH" ]]; then exec "$RUNTIME_BASH" "${BASH_SOURCE[0]}" "$@"; fi
# Test subprocesses use the same compatible interpreter as this runner.
export PATH="${BASH%/*}:$PATH"
suite=${1:-all}
case "$suite" in common|linux|macos|all) ;; *) printf 'Usage: bash mir/tests/run.sh [common|linux|macos|all]\n' >&2; exit 1 ;; esac
if (( $# > 1 )); then exit 1; fi
lint_adapter() {
    "$BASH" -n "$MIR_ROOT/lib/platform/$1.sh"
    if command -v shellcheck >/dev/null; then shellcheck "$MIR_ROOT/lib/platform/$1.sh"; fi
}
run() { printf '\nChecking %s\n' "$1"; "$BASH" "$MIR_ROOT/tests/$1" "${@:2}"; }
if [[ "$suite" == common || "$suite" == all ]]; then
    run architecture.sh
    test_scripts=("$MIR_ROOT"/tests/*.sh "$MIR_ROOT"/tests/helpers/*.sh "$MIR_ROOT"/tests/platform/*.sh "$MIR_ROOT"/tests/native/*.sh)
    lint_pid=''
    if command -v shellcheck >/dev/null; then
        # Static analysis only reads repository files; fixtures use temporary directories.
        shellcheck -x -P "$MIR_ROOT" -P SCRIPTDIR "$MIR_ROOT/mir.sh" "$MIR_ROOT/sh/install.sh" "$MIR_ROOT/sh/build-install.sh" "${test_scripts[@]}" &
        lint_pid=$!
    fi
    for file in "$MIR_ROOT/mir.sh" "$MIR_ROOT"/lib/*.sh "$MIR_ROOT"/lib/tui/*.sh "$MIR_ROOT/sh/install.sh" "${test_scripts[@]}"; do "$BASH" -n "$file"; done
    run config.sh
    run storage.sh
    run regression.sh
    run portability.sh
    run memory.sh
    run tui.sh
    if [[ -n "$lint_pid" ]]; then wait "$lint_pid"; fi
fi
if [[ "$suite" == linux || "$suite" == all ]]; then
    lint_adapter linux
    run platform/linux.sh
    run build.sh
    run installation.sh Linux
    run native/linux.sh
fi
if [[ "$suite" == macos || "$suite" == all ]]; then
    lint_adapter macos
    run platform/macos.sh
    run platform/macos-build.sh
    run build.sh macos
    run installation.sh Darwin
    run native/macos.sh
fi
