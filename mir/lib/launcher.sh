#!/usr/bin/env bash
# Definitions only. Keep the same module order for startup and isolated tests.
load_launcher_modules() {
    source "$MIR_ROOT/lib/build.sh"
    source "$MIR_ROOT/lib/config.sh"
    source "$MIR_ROOT/lib/paths.sh"
    source "$MIR_ROOT/lib/profiles.sh"
    source "$MIR_ROOT/lib/processes.sh"
    source "$MIR_ROOT/lib/server.sh"
    source "$MIR_ROOT/lib/memory.sh"
    source "$MIR_ROOT/lib/tui/common.sh"
    source "$MIR_ROOT/lib/tui/folders.sh"
    source "$MIR_ROOT/lib/tui/build.sh"
    source "$MIR_ROOT/lib/tui/settings.sh"
    source "$MIR_ROOT/lib/tui/profiles.sh"
    source "$MIR_ROOT/lib/tui/main.sh"
}
