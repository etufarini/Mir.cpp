#!/usr/bin/env bash
# Build UI preserves the active installation until checks and saving succeed.

monitor_build() (
    local stage=$1 tag=$2 backend=$3 jobs=$4 previous=$5 pid='' identity='' result interrupted=0
    set +m
    stop_build() {
        trap '' INT TERM HUP
        if [[ -n "$pid" && -n "$identity" && $(ps -p "$pid" -o lstart= 2>/dev/null) == "$identity" ]]; then
            kill -TERM -- "-$pid" 2>/dev/null || true
        fi
        [[ -z "$pid" ]] || wait "$pid" 2>/dev/null || true
    }
    trap 'result=$?; stop_build; if (( result != 0 )); then rm -rf -- "$stage"; fi' EXIT
    # Defer exit until the worker identity is known. An interrupted ps must not
    # leave cleanup waiting for a compiler it has no identity to signal.
    trap 'interrupted=130' INT
    trap 'interrupted=143' TERM HUP
    # A separate session lets Cancel terminate the compiler's whole process group.
    platform_start_worker "$BASH" -c 'MIR_ROOT=$1
source "$MIR_ROOT/lib/platform.sh"
load_platform "$2"
source "$MIR_ROOT/lib/build.sh"
build_release "$3" "$4" "$5" "$6" "$7"' \
        mir-build "$MIR_ROOT" "$PLATFORM_LOADED" "$stage" "$tag" "$backend" "$jobs" "$previous" > "$BUILD_LOG" 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if identity=$(ps -p "$pid" -o lstart= 2>/dev/null); then break; fi
    done
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    if (( interrupted != 0 )); then exit "$interrupted"; fi
    while kill -0 "$pid" 2>/dev/null; do
        if DIALOG_TIMEOUT=5 UI_TITLE='Building llama.cpp' ui --yes-label 'View log' --no-label 'Cancel build' --timeout 2 \
            --yesno "Building $tag ($backend) with $jobs compiler jobs.\n\nThe previous build remains active until verification succeeds.\n\nLog: $(compact_text "$BUILD_LOG")" 15 80; then
            UI_TITLE='llama.cpp build log' ui --exit-label Back --textbox "$BUILD_LOG" 22 80 || true
        else
            result=$?
            if (( result != 5 )) && UI_TITLE='Cancel build' ui --yesno 'Cancel this build? The previous installation will be kept.' 9 72; then
                return 130
            fi
        fi
    done
    result=0
    wait "$pid" || result=$?
    pid=''
    return "$result"
)

install_build() {
    local tag=$1 backend=$2 jobs=$3 root stage previous='' lockfd result=0
    root=$(build_root)
    [[ "$root" == /* && "$root" != *$'\n'* ]] || { message 'HOME and XDG_DATA_HOME must be absolute paths without line breaks.'; return 1; }
    mkdir -p -- "$root/builds" || { message 'Cannot create the llama.cpp installation folder.'; return 1; }
    exec {lockfd}> "$root/.build.lock" || return 1
    if ! flock -n "$lockfd"; then
        exec {lockfd}>&-
        message 'Another llama.cpp build is running. Retry when it finishes.'
        return 1
    fi
    if read_build "$LLAMA_CPP_PATH"; then previous=${LLAMA_CPP_PATH##*/}; fi
    stage=$(mktemp -d "$root/builds/build.XXXXXXXX") || { exec {lockfd}>&-; return 1; }
    BUILD_LOG="$root/build.log"
    monitor_build "$stage" "$tag" "$backend" "$jobs" "$previous" || result=$?
    if (( result == 0 )) && activate_build "$stage"; then
        message "llama.cpp $tag ($backend) is ready. Its path was saved automatically.\n\nReview your model and device settings before launching."
    else
        # The monitor removes failed/interrupted stages; only activation can
        # fail after it has handed back a successfully verified build.
        if (( result == 0 )); then rm -rf -- "$stage"; fi
        if (( result == 130 || result == 143 )); then message 'Build canceled. The previous installation was kept.';
        else message 'Build or activation failed. The previous installation was kept. Open View build log for details.'; fi
        result=1
    fi
    exec {lockfd}>&-
    return "$result"
}

dependency_terminal() (
    local terminal_fd result=0 answer clear_screen=$'\033[0m\033[2J\033[H'
    exec {terminal_fd}<> /dev/tty || return 1
    # Leave no dialog or command output behind, including on interruption.
    trap 'printf "%s" "$clear_screen" >&"$terminal_fd"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM HUP
    printf '%s' "$clear_screen" >&"$terminal_fd"
    "$@" <&"$terminal_fd" >&"$terminal_fd" 2>&1 || result=$?
    printf '\nPress Enter to return to Mir.cpp. ' >&"$terminal_fd"
    IFS= read -r -u "$terminal_fd" answer || true
    return "$result"
)

prepare_build_dependencies() {
    if platform_ensure_dependencies build dependency_terminal &&
        { [[ "$1" == cpu ]] || platform_ensure_dependencies "$1" dependency_terminal; }; then return 0; fi
    message 'Build dependencies are unavailable. Check the terminal output, package repositories and GPU setup.'
    return 1
}

choose_build() {
    local backend=cpu tag choice UI_TITLE='Install llama.cpp'
    local -a backends=()
    mapfile -t backends < <(platform_build_backends)
    (( ${#backends[@]} > 0 )) || { message 'Managed llama.cpp builds are not available on this platform yet. Select an existing build in Folders.'; return 0; }
    if read_build "$LLAMA_CPP_PATH"; then backend=$BUILD_BACKEND; fi
    backend=$(menu --default-item "$backend" --menu 'Choose the backend to compile. GPU builds require working drivers.\nCPU remains available in GPU builds.' 15 80 4 \
        "${backends[@]}" back Back) || return 0
    [[ "$backend" != back ]] || return 0
    prepare_build_dependencies "$backend" || return 0
    choice=$(menu --menu 'Choose the llama.cpp source version. Published releases may include pre-releases.' 13 80 3 \
        latest 'Latest published release' tag 'Specific release tag' back Back) || return 0
    case "$choice" in
        latest)
            ui --infobox 'Checking published llama.cpp releases...' 5 64
            tag=$(latest_build_tag) || { message 'Cannot check releases. Check your network connection or enter a release tag.'; return 0; } ;;
        tag) tag=$(ui --cancel-label Back --inputbox 'Enter an official llama.cpp release tag, for example b12128.' 10 78) || return 0 ;;
        *) return 0 ;;
    esac
    confirm_build "$tag" "$backend"
}

confirm_build() {
    local tag=$1 backend=$2 jobs UI_TITLE='Build llama.cpp'
    valid_build_tag "$tag" || { message 'Invalid release tag. Use letters, digits, dots, underscores or hyphens; start with a letter or digit.'; return 0; }
    jobs=$(ui --cancel-label Back --inputbox 'Parallel compiler jobs (1-64). More jobs use more RAM.\nThis does not change inference CPU threads.' 10 78 2) || return 0
    [[ "$jobs" =~ ^([1-9]|[1-5][0-9]|6[0-4])$ ]] || { message 'Enter an integer between 1 and 64.'; return 0; }
    ui --yesno "Download and compile llama.cpp $tag ($backend)?\n\nInstallation: $(compact_text "$(build_root)")\nCompiler jobs: $jobs\n\nThe path is saved after verification. Existing external builds are kept." 15 80 || return 0
    install_build "$tag" "$backend" "$jobs" || true
}

build_menu() {
    local action=install summary tag backend previous UI_TITLE='llama.cpp setup'
    while true; do
        summary='Using an external build, or no build selected.'
        if read_build "$LLAMA_CPP_PATH"; then summary="Selected: $BUILD_TAG ($BUILD_BACKEND)\nCommit: ${BUILD_COMMIT:0:12}"; fi
        action=$(menu --default-item "$action" --menu "$summary\n\nBuilds are installed for your user. GPU drivers are configured separately." 19 80 5 \
            install 'Install / change build' update 'Check for updates' restore 'Restore previous build' log 'View build log' back Back) || return 0
        case "$action" in
            install) choose_build ;;
            update)
                if ! read_build "$LLAMA_CPP_PATH"; then message 'Updates apply to builds installed by Mir.cpp. Choose Install / change build first.'; continue; fi
                backend=$BUILD_BACKEND
                prepare_build_dependencies "$backend" || continue
                ui --infobox 'Checking published llama.cpp releases...' 5 64
                tag=$(latest_build_tag) || { message 'Cannot check releases. Check your network connection and retry.'; continue; }
                if [[ "$tag" == "$BUILD_TAG" ]]; then message "llama.cpp $tag is already the latest published release."; continue; fi
                confirm_build "$tag" "$backend" ;;
            restore)
                if ! read_build "$LLAMA_CPP_PATH" || [[ -z "$BUILD_PREVIOUS" ]]; then message 'No previous managed build is available.'; continue; fi
                previous="$(build_root)/builds/$BUILD_PREVIOUS"
                if ! read_build "$previous"; then message 'The previous build is missing or invalid.'; continue; fi
                ui --yesno "Restore llama.cpp $BUILD_TAG ($BUILD_BACKEND)?\n\nCurrent model and profile settings will be kept." 10 76 || continue
                activate_build "$previous" && message 'Previous build restored.' || message 'Cannot restore the previous build. Current paths were kept.' ;;
            log)
                previous="$(build_root)/build.log"
                if [[ -f "$previous" ]]; then UI_TITLE='llama.cpp build log' ui --exit-label Back --textbox "$previous" 22 80 || true;
                else message 'No build log is available yet.'; fi ;;
            back) return 0 ;;
        esac
    done
}
