#!/usr/bin/env bash
set -euo pipefail
MIR_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$MIR_ROOT/lib/runtime.sh"
configure_runtime check
if [[ "$RUNTIME_BASH" != "$BASH" ]]; then exec "$RUNTIME_BASH" "${BASH_SOURCE[0]}" "$@"; fi

source "$MIR_ROOT/lib/platform.sh"
load_platform "$PLATFORM_ID"
source "$MIR_ROOT/lib/launcher.sh"
load_launcher_modules

initialize_config "$@"
if (( $# > 0 )); then shift; fi
validate_config
if "$TUI"; then configure_tui;
else prepare_server "$@" || fail "$LAUNCH_ERROR"; fi
run_server
