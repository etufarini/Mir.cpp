#!/usr/bin/env bash
# Canonical installer logic; bundled by build-install.sh for curl delivery.
main() {
    set -euo pipefail

    fail() { printf 'Installation failed: %s\n' "$*" >&2; exit 1; }
    (( $# == 0 )) || fail 'This installer takes no arguments.'
    configure_runtime
    if [[ "$RUNTIME_BASH" != "$BASH" ]]; then
        # Replace this process so interruption cannot leave a bootstrap parent
        # and a child installer holding the installation lock.
        exec "$RUNTIME_BASH" -c "$(declare -f detect_platform configure_runtime bootstrap_macos macos_dependency_hint load_platform check_dependencies runtime_files main)"$'\nmain "$@"' mir-installer "$@"
    fi
    load_platform "$PLATFORM_ID"
    check_dependencies install || exit 1
    BROWSER=$(platform_browser_command)
    if ! command -v "$BROWSER" >/dev/null; then
        printf 'WARNING: %s is missing; automatic browser opening will be unavailable.\nOpen the server address manually.\n' "$BROWSER" >&2
    fi

    INSTALL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/mir.cpp"
    BIN_DIR="$HOME/.local/bin"
    [[ "$INSTALL_DIR" == /* && "$BIN_DIR" == /* ]] || fail 'HOME and XDG_DATA_HOME must be absolute paths.'
    COMMAND="$BIN_DIR/mir"
    MARKER='# Mir.cpp managed launcher'
    mkdir -p -- "$INSTALL_DIR"
    # The lock file stays in place: removing it could let two installers lock
    # different inodes. The kernel releases the lock when this process exits.
    exec 9> "$INSTALL_DIR/.install.flock"
    flock -n 9 || fail 'Another Mir.cpp installation is running. Retry when it finishes.'
    NEW_COMMAND=true
    if [[ -e "$COMMAND" || -L "$COMMAND" ]]; then
        NEW_COMMAND=false
        [[ -f "$COMMAND" && ! -L "$COMMAND" ]] || fail "$COMMAND already exists and is not a managed launcher."
        {
            IFS= read -r _
            IFS= read -r second_line
        } < "$COMMAND" || true
        # The ownership marker survives a damaged exec line or missing permissions.
        [[ "$second_line" == "$MARKER" ]] || fail "$COMMAND already exists and is not a managed launcher."
    fi
    [[ ! -e "$INSTALL_DIR/current" || -L "$INSTALL_DIR/current" ]] ||
        fail "$INSTALL_DIR/current already exists and is not an installation link."
    mkdir -p -- "$INSTALL_DIR/releases" "$BIN_DIR"
    STAGE=''
    WRAPPER=''
    LINK=''
    cleanup() {
        if [[ -n "$STAGE" && ! "$INSTALL_DIR/current" -ef "$STAGE" ]]; then
            rm -rf -- "$STAGE"
            if "$NEW_COMMAND"; then rm -f -- "$COMMAND"; fi
        fi
        [[ -z "$WRAPPER" ]] || rm -f -- "$WRAPPER"
        [[ -z "$LINK" ]] || rm -f -- "$LINK"
    }
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    STAGE=$(mktemp -d "$INSTALL_DIR/releases/install.XXXXXXXX")
    printf 'Downloading Mir.cpp from etufarini/Mir.cpp (main)...\n'
    curl --fail --show-error --silent --location --proto '=https' --tlsv1.2 \
        --connect-timeout 15 --max-time 180 --retry 2 \
        https://codeload.github.com/etufarini/Mir.cpp/tar.gz/refs/heads/main \
        --output "$STAGE/source.tar.gz" 9>&-

    # Extract only the runtime files and documentation, never arbitrary archive paths.
    FILES=()
    while IFS= read -r file; do FILES+=("$file"); done < <(runtime_files)
    MEMBERS=()
    for file in "${FILES[@]}"; do MEMBERS+=("Mir.cpp-main/mir/$file"); done
    # Keep the installed runtime flat so the stable wrapper also works on rollback.
    tar -xzf "$STAGE/source.tar.gz" --no-same-owner --no-same-permissions \
        --strip-components=2 -C "$STAGE" -- "${MEMBERS[@]}" 9>&-
    DOCUMENTS=(README.md mir/docs/guide.md mir/docs/images/logo.png
        mir/docs/screenshots/main-menu.png mir/docs/screenshots/model-settings.png)
    MEMBERS=()
    for file in "${DOCUMENTS[@]}"; do MEMBERS+=("Mir.cpp-main/$file"); done
    tar -xzf "$STAGE/source.tar.gz" --no-same-owner --no-same-permissions \
        --strip-components=1 -C "$STAGE" -- "${MEMBERS[@]}" 9>&-
    rm -- "$STAGE/source.tar.gz"
    for file in "${FILES[@]}" "${DOCUMENTS[@]}"; do
        [[ -f "$STAGE/$file" && ! -L "$STAGE/$file" && -r "$STAGE/$file" ]] || fail "Missing or invalid file: $file"
        if [[ "$file" == *.sh ]]; then "$BASH" -n "$STAGE/$file"; fi
    done
    chmod +x "$STAGE/mir.sh"

    # Use a wrapper rather than a launcher symlink: modules resolve beside the script.
    WRAPPER=$(mktemp "$BIN_DIR/.mir.XXXXXXXX")
    {
        printf '#!/usr/bin/env bash\n%s\n' "$MARKER"
        # shellcheck disable=SC2016 # Expand the argument in the generated wrapper.
        printf 'if [[ ${1:-} == --uninstall ]]; then\n    shift\n'
        printf '    exec %q %q %q %q "$@"\nfi\n' "$BASH" \
            "$INSTALL_DIR/current/sh/uninstall.sh" "$INSTALL_DIR" "$COMMAND"
        printf 'exec %q %q "$@"\n' "$BASH" "$INSTALL_DIR/current/mir.sh"
    } > "$WRAPPER"
    chmod +x "$WRAPPER"
    LINK="$INSTALL_DIR/.current.${STAGE##*/}"
    ln -s -- "releases/${STAGE##*/}" "$LINK"
    # Publish the stable command first; a failed activation preserves the old target.
    platform_move "$WRAPPER" "$COMMAND" replace
    WRAPPER=''
    platform_move "$LINK" "$INSTALL_DIR/current" replace
    LINK=''
    # Delete only installer-created release directories after the new copy is active.
    # Leave unknown files and symlinks untouched, and keep the new release on errors.
    ACTIVE="$STAGE"
    STAGE=''
    CLEAN=true
    for release in "$INSTALL_DIR"/releases/install.*; do
        [[ -d "$release" && ! -L "$release" && "$release" != "$ACTIVE" ]] || continue
        if ! rm -rf -- "$release"; then
            printf 'WARNING: Reinstallation succeeded, but could not remove old files: %s\n' "$release" >&2
            CLEAN=false
        fi
    done
    if "$CLEAN"; then
        printf 'Installation complete. Previous program copies have been cleaned.\n'
    else
        printf 'Installation complete with cleanup warnings.\n'
    fi
    printf 'Start with: %s\n' "$COMMAND"
    case ":$PATH:" in
        *":$BIN_DIR:"*) printf 'You can also run: mir\n' ;;
        *) printf 'To use the mir command, add %s to your PATH.\n' "$BIN_DIR" ;;
    esac
    printf 'Select your existing llama.cpp build and GGUF model folders in the launcher.\n'
}

main "$@"
