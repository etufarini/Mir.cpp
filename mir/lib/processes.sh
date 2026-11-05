#!/usr/bin/env bash
# Port status and listener shutdown with confirmation and PID identity checks.

check_port() {
    local pid
    LISTENERS=$(ss -H -ltnp "sport = :$PORT") || fail 'Unable to inspect listening ports.'
    PIDS=()
    while IFS= read -r pid; do
        [[ -z "$pid" ]] || PIDS+=("$pid")
    done < <(printf '%s' "$LISTENERS" | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -un)
    PORT_STATUS="Port $PORT: FREE"
    if [[ -n "$LISTENERS" ]]; then
        PORT_STATUS="Port $PORT: IN USE"
        if (( ${#PIDS[@]} > 0 )); then PORT_STATUS+=$'\n    PID USER     PROCESS'; fi
        for pid in "${PIDS[@]}"; do
            PORT_STATUS+=$'\n'"$(ps -p "$pid" -o pid=,user=,comm= || true)"
        done
        if (( ${#PIDS[@]} == 0 )); then
            PORT_STATUS+=$'\nProcess details unavailable; it cannot be stopped here.'
        fi
    fi
}

stop_listener() {
    check_port
    if [[ -z "$LISTENERS" ]] || (( ${#PIDS[@]} == 0 )); then
        message "$PORT_STATUS"
        return
    fi
    # Keep process start times before confirmation to detect recycled PIDs.
    local pid identity details _
    local -A targets=()
    for pid in "${PIDS[@]}"; do
        identity=$(ps -p "$pid" -o lstart=) || continue
        targets[$pid]="$identity"
    done
    UI_TITLE='Stop processes' ui --scrollbar --yesno "Send SIGTERM to these processes? Other services may be affected.\nUse Up/Down to scroll through the process details.\n\n$PORT_STATUS" 22 80 || return 0
    for pid in "${!targets[@]}"; do
        if [[ "$(ps -p "$pid" -o lstart= || true)" == "${targets[$pid]}" ]]; then
            kill -TERM "$pid" 2>/dev/null || message "Cannot stop PID $pid. It may belong to another user."
        fi
    done
    for _ in {1..20}; do
        for pid in "${!targets[@]}"; do
            if [[ "$(ps -p "$pid" -o lstart= || true)" != "${targets[$pid]}" ]]; then unset 'targets[$pid]'; fi
        done
        (( ${#targets[@]} > 0 )) || break
        sleep 0.1
    done
    if (( ${#targets[@]} > 0 )); then
        details='    PID USER     PROCESS'
        for pid in "${!targets[@]}"; do
            details+=$'\n'"$(ps -p "$pid" -o pid=,user=,comm= || true)"
        done
        if UI_TITLE='Force stop processes' ui --scrollbar --yesno "Force stop these processes with SIGKILL?\nUse Up/Down to scroll through the process details.\n\nStill running: ${!targets[*]}\n$details" 22 80; then
            for pid in "${!targets[@]}"; do
                if [[ "$(ps -p "$pid" -o lstart= || true)" == "${targets[$pid]}" ]]; then
                    kill -KILL "$pid" 2>/dev/null || message "Cannot force stop PID $pid."
                fi
            done
        fi
    fi
    check_port
    message "$PORT_STATUS"
}
