#!/usr/bin/env bash
# Explicit imports prevent adapters from overwriting each other's functions.
load_test_core() {
    if [[ "$1" == fake ]]; then
        source "$MIR_ROOT/tests/helpers/fake.sh"
        PLATFORM_LOADED=fake
    else
        source "$MIR_ROOT/lib/platform.sh"
        load_platform "$1"
    fi
    source "$MIR_ROOT/lib/launcher.sh"
    load_launcher_modules
}
