#!/usr/bin/env bash
set -euo pipefail
# Run without arguments for the TUI, or pass a GGUF path for direct startup.
MIR_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$MIR_ROOT/lib/runtime.sh"
configure_runtime
if [[ "$RUNTIME_BASH" != "$BASH" ]]; then exec "$RUNTIME_BASH" "${BASH_SOURCE[0]}" "$@"; fi

# Modules define functions only. Configuration and runtime state are shared in
# this shell; only the entry point enables strict mode and starts the server.
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
