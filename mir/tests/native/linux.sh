#!/usr/bin/env bash
set -euo pipefail
TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
"$BASH" "$TEST_DIR/ports.sh" linux
if [[ $(uname -s) == Linux ]]; then
    MIR_ROOT="$(cd -- "$TEST_DIR/../.." && pwd)"
    source "$MIR_ROOT/tests/helpers/core.sh"
    load_test_core linux
    work=$(mktemp -d)
    trap 'rm -rf -- "$work"' EXIT
    mkdir "$work/source" "$work/target"
    printf original > "$work/target/data"
    platform_move "$work/source" "$work/target" no-clobber
    [[ -d "$work/source" && $(cat "$work/target/data") == original ]]
    printf 'PASS: native Linux no-clobber activation preserves an existing directory\n'
fi
