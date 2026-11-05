#!/usr/bin/env bash
# The installed wrapper supplies its original paths, independently of XDG changes.
main() {
    set -euo pipefail
    fail() { printf 'Uninstallation failed: %s\n' "$*" >&2; exit 1; }
    (( $# >= 2 )) || fail 'Use mir --uninstall [--yes].'
    INSTALL_DIR=$1
    COMMAND=$2
    shift 2
    YES=false
    if [[ ${1:-} == --yes ]]; then YES=true; shift; fi
    (( $# == 0 )) || fail 'Use mir --uninstall [--yes].'

    [[ "$INSTALL_DIR" == /*/mir.cpp && -d "$INSTALL_DIR" && ! -L "$INSTALL_DIR" &&
        -d "$INSTALL_DIR/releases" && ! -L "$INSTALL_DIR/releases" ]] ||
        fail 'The installation directory is not a managed Mir.cpp installation.'
    SCRIPT_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
    [[ -L "$INSTALL_DIR/current" && "$INSTALL_DIR/current" -ef "$SCRIPT_ROOT" ]] ||
        fail 'Run the command from the active installed copy.'
    [[ -f "$INSTALL_DIR/.install.flock" && ! -L "$INSTALL_DIR/.install.flock" ]] ||
        fail 'The installation lock is missing or invalid.'
    exec 9< "$INSTALL_DIR/.install.flock"
    flock -n 9 || fail 'Another Mir.cpp installation or removal is running. Retry when it finishes.'

    # Check both the ownership marker and original target before removing a command.
    [[ "$COMMAND" == /*/mir && -f "$COMMAND" && ! -L "$COMMAND" ]] ||
        fail 'The installed command is missing or has been replaced.'
    printf -v EXPECTED_EXEC 'exec %q "$@"' "$INSTALL_DIR/current/mir.sh"
    {
        IFS= read -r _
        IFS= read -r marker
    } < "$COMMAND" || fail 'The installed command is incomplete.'
    if [[ "$marker" != '# Mir.cpp managed launcher' ]] || ! grep -Fxq -- "$EXPECTED_EXEC" "$COMMAND"; then
        fail 'The command does not belong to this installation.'
    fi

    RELEASES=()
    ACTIVE_FOUND=false
    for release in "$INSTALL_DIR"/releases/install.*; do
        [[ "${release##*/}" =~ ^install\.[[:alnum:]]{8}$ && -d "$release" && ! -L "$release" ]] || continue
        RELEASES+=("$release")
        if [[ "$release" -ef "$SCRIPT_ROOT" ]]; then ACTIVE_FOUND=true; fi
    done
    "$ACTIVE_FOUND" || fail 'The active release is not an installer-managed directory.'
    printf 'Remove Mir.cpp command: %s\nProgram releases: %s/releases/install.*\n' "$COMMAND" "$INSTALL_DIR"
    printf 'Models, llama.cpp, saved settings and unrelated files will be kept.\n'
    printf 'Close the launcher and stop its server before continuing.\n'
    if ! "$YES"; then
        [[ -t 0 ]] || fail 'Confirmation requires a terminal. Use --yes for non-interactive removal.'
        read -r -p 'Remove Mir.cpp? [y/N] ' answer || answer=''
        case "$answer" in
            y|Y|yes|YES) ;;
            *) printf 'Uninstallation canceled.\n'; return 0 ;;
        esac
    fi

    # Keep the command and active release available if old-release cleanup fails.
    for release in "${RELEASES[@]}"; do
        [[ "$release" -ef "$SCRIPT_ROOT" ]] && continue
        rm -rf -- "$release" || fail "Could not remove $release. Check permissions and retry."
    done
    rm -rf -- "$SCRIPT_ROOT" || fail 'Could not remove the active release. Check permissions and reinstall to repair.'
    rm -- "$INSTALL_DIR/current" "$COMMAND" || fail 'Could not remove the installation links or command. Check permissions.'
    # Keep the lock inode so concurrent installers cannot acquire a different lock.
    printf 'Uninstallation complete. Saved settings and the installation lock file have been kept.\n'
}

main "$@"
