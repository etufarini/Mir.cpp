#!/usr/bin/env bash
set -euo pipefail
(( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )) || {
    printf 'Mir.cpp requires Bash 4.4 or newer.\n' >&2
    exit 1
}

# Run without arguments for the TUI, or pass a GGUF path for direct startup.
MIR_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Modules define functions only. Configuration and runtime state are shared in
# this shell; only the entry point enables strict mode and starts the server.
source "$MIR_ROOT/lib/config.sh"
source "$MIR_ROOT/lib/paths.sh"
source "$MIR_ROOT/lib/profiles.sh"
source "$MIR_ROOT/lib/processes.sh"
source "$MIR_ROOT/lib/server.sh"
source "$MIR_ROOT/lib/memory.sh"
source "$MIR_ROOT/lib/tui/common.sh"
source "$MIR_ROOT/lib/tui/folders.sh"
source "$MIR_ROOT/lib/tui/settings.sh"
source "$MIR_ROOT/lib/tui/profiles.sh"
source "$MIR_ROOT/lib/tui/main.sh"

initialize_config "$@"
if (( $# > 0 )); then shift; fi
validate_config
if "$TUI"; then configure_tui;
else prepare_server "$@" || fail "$LAUNCH_ERROR"; fi
run_server
