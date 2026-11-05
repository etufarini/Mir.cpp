#!/usr/bin/env bash
# Main navigation, port menu and running session display.

configuration_summary() {
    local port_status=${PORT_STATUS%%$'\n'*}
    printf '%-14s%s\n' Configuration "$(compact_text "$(profile_status)")" \
        Model "$(compact_text "${MODEL##*/}")"
    printf '%-14s%-24sReasoning  %s\n' Context "$(context_label)" "$(display_value "$REASONING")"
    printf '%-14s%s\n' Device "$(compact_text "$(display_value "$DEVICE")")" \
        Port "${port_status#Port }"
    printf '%s' "$MEMORY_TEXT"
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
    local ACTION CHOICE RESULT UI_TITLE='Main menu'
    [[ -t 0 && -t 1 ]] || fail 'The TUI needs a terminal. For direct startup, pass a GGUF path.'
    command -v dialog >/dev/null || fail 'Install the TUI dependency: sudo apt install dialog'
    THEME_FILE="$MIR_ROOT/dialogrc"
    [[ -z "$PATHS_WARNING" ]] || message "$PATHS_WARNING"
    scan_models
    if [[ -d "$MODELS_DIR" ]] && (( ${#MODELS[@]} == 0 )); then message 'No GGUF models found. Add models or choose another folder in Folders.'; fi
    if [[ ! -f "$SERVER" || ! -x "$SERVER" || ! -d "$MODELS_DIR" ]]; then
        message 'Choose your llama.cpp and models folders in Folders. You can change them later from the main menu.'
        paths_menu
    fi
    ACTION=launch
    while true; do
        check_port
        refresh_memory
        memory_controls estimate
        if CHOICE=$(menu --cancel-label Quit "${MEMORY_BUTTONS[@]}" --default-item "$ACTION" --menu "$(configuration_summary)" 22 80 7 \
            launch 'Launch server' \
            model 'Model settings           Model and generation' \
            performance 'Performance              Device, threads, input' \
            server 'Server & port            Port and processes' \
            configurations 'Saved configurations     Load, update, save, delete' \
            paths 'Folders                  llama.cpp and models' \
            quit 'Quit'); then ACTION=$CHOICE;
        else
            RESULT=$?
            if (( RESULT == 3 )); then MEMORY_PAGE=$((MEMORY_PAGE + 1)); continue; fi
            exit 0
        fi
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
    memory_controls live
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
