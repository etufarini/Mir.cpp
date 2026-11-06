#!/usr/bin/env bash

configuration_summary() {
    local port_status=${PORT_STATUS%%$'\n'*}
    printf '%-14s%s\n' Configuration "$(compact_text "$(profile_status)")" \
        Model "$(compact_text "${MODEL##*/}")" Context "$(context_label)" \
        Device "$(compact_text "$(display_value "$DEVICE")")" \
        Port "${port_status#Port }"
}

server_menu() {
    local action=port choice UI_TITLE='Server & port'
    while true; do
        check_port
        action=$(menu --default-item "$action" --menu "${PORT_STATUS%%$'\n'*}\n\nChoose a port or inspect its listeners before stopping them." 17 80 5 \
            port "Port                     $PORT" check 'Refresh port status' \
            details 'View process details' stop 'Stop process using port' back Back) || return 0
        case "$action" in
            port)
                if choice=$(UI_TITLE='TCP port' ui --cancel-label Back --inputbox 'TCP port (1-65535)' 9 60 "$PORT"); then
                    if valid_port "$choice"; then PORT=$((10#$choice)); else message 'Invalid port. Enter an integer between 1 and 65535.'; fi
                fi ;;
            stop) stop_listener ;;
            details) UI_TITLE='Port process details' ui --ok-label Back --scrollbar --msgbox "$PORT_STATUS\n\nUse Up/Down to scroll; Back/Esc returns." 22 80 || true ;;
            back) return 0 ;;
        esac
    done
}

configure_tui() {
    local ACTION UI_TITLE='Main menu'
    [[ -t 0 && -t 1 ]] || fail 'The TUI needs a terminal. For direct startup, pass a GGUF path.'
    check_dependencies tui || exit 1
    THEME_FILE="$MIR_ROOT/dialogrc"
    [[ -z "$PATHS_WARNING" ]] || message "$PATHS_WARNING"
    scan_models
    if [[ -d "$MODELS_DIR" ]] && (( ${#MODELS[@]} == 0 )); then message 'No GGUF models found. Add models or choose another folder in Folders.'; fi
    if [[ ! -f "$SERVER" || ! -x "$SERVER" || ! -d "$MODELS_DIR" ]]; then
        message 'In Folders, install/build llama.cpp or choose an existing build, then select your models folder. You can change these later.'
        paths_menu
    fi
    ACTION=launch
    while true; do
        check_port
        ACTION=$(menu --cancel-label Quit --default-item "$ACTION" --menu "$(configuration_summary)" 22 80 7 \
            launch 'Launch server' \
            model 'Model settings           Model and generation' \
            performance 'Performance              Device, threads, input' \
            server 'Server & port            Port and processes' \
            configurations 'Saved configurations     Load, update, save, delete' \
            paths 'Folders                  llama.cpp and models' \
            quit 'Quit') || exit 0
        case "$ACTION" in
            model) model_menu ;;
            performance) performance_menu ;;
            server) server_menu ;;
            configurations) configurations_menu ;;
            paths) paths_menu ;;
            launch)
                if prepare_server; then return 0;
                else message "$LAUNCH_ERROR\n\nReview Model settings, Performance, Server & port or Folders before retrying."; fi ;;
            quit) exit 0 ;;
        esac
    done
}

running_screen() {
    local STATE RESULT
    STATE=Loading
    if "$OPENED"; then STATE=Ready; fi
    memory_available
    memory_controls
    # Give refresh timeouts a distinct status from Escape (255).
    if DIALOG_TIMEOUT=5 UI_TITLE='Server running' ui "${MEMORY_BUTTONS[@]}" --yes-label 'Stop server' --no-label 'View log' --timeout 2 \
        --yesno "Status     $STATE\nModel      $(compact_text "${MODEL##*/}")\nAddress    $URL\n\n$MEMORY_TEXT\nStop server also exits the launcher." 22 80; then
        exit 0
    else
        RESULT=$?
        case "$RESULT" in
            1) view_log ;;
            3) MEMORY_PAGE=$((MEMORY_PAGE + 1)); return 0 ;;
            5) return 0 ;;
            255) exit 0 ;;
        esac
    fi
}
