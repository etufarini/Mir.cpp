#!/usr/bin/env bash

ui() (
    # Let curses read the real terminal size and use our own positioning options.
    # Scope this to the dialog child so the caller's environment stays intact.
    unset LINES COLUMNS DIALOGOPTS
    DIALOGRC="${THEME_FILE:-${DIALOGRC:-/dev/null}}" dialog --stdout --no-tags \
        --no-collapse --backtitle 'MIR.CPP / STATION CONTROL' \
        --title " ${UI_TITLE:-Information} " "$@"
)

menu() { ui --ok-label Select --cancel-label Back "$@"; }

message() { UI_TITLE=Information ui --msgbox "$1" 12 76; }

view_log() { UI_TITLE='Server log' ui --exit-label Back --textbox "$LOG_FILE" 22 80 || true; }

# Keep summaries on one line while retaining both ends of long names.
compact_text() {
    local text=${1:-Not selected} width=${2:-58}
    text=${text//$'\n'/ }
    text=${text//$'\r'/ }
    text=${text//$'\t'/ }
    if (( ${#text} > width )); then text="${text:0:width-15}...${text: -12}"; fi
    printf '%s' "$text"
}

display_value() {
    case "$1" in
        auto) printf '%s' "${2:-Auto}" ;;
        none) printf 'CPU only' ;;
        on) printf On ;;
        off) printf Off ;;
        all) printf All ;;
        low-memory) printf 'Low memory' ;;
        large-batch) printf 'Large batch' ;;
        default) printf Default ;;
        focused) printf Focused ;;
        exploratory) printf Exploratory ;;
        min-p) printf Min-P ;;
        custom) printf Custom ;;
        *) printf '%s' "$1" ;;
    esac
}

context_label() {
    if [[ "$CTX_SIZE" == auto ]]; then printf Auto;
    elif [[ "$CTX_SIZE" == 0 ]]; then printf 'Full model context';
    elif (( CTX_SIZE % 1024 == 0 )); then printf '%sK' "$((CTX_SIZE / 1024))";
    else printf '%s tokens' "$CTX_SIZE"; fi
}
