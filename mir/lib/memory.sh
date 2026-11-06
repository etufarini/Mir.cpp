#!/usr/bin/env bash
# Live memory telemetry; system RAM comes from the platform adapter.

memory_available() {
    platform_memory_snapshot
    declare -gA DEVICE_FREE=()
    GPU_DEVICE_NAMES=()
    if [[ $(platform_memory_style) == margins && "$DEVICE" != none ]]; then server_devices || true; fi
}

memory_gib() {
    printf '%d.%d' "$(( $1 / 1024 ))" "$(( ($1 % 1024) * 10 / 1024 ))"
}

# dialog's 80-column box needs space for borders and horizontal padding.
memory_width() {
    local _ columns width=72
    if [[ -t 0 ]] && read -r _ columns < <(stty size 2>/dev/null) && [[ "$columns" =~ ^[0-9]{1,3}$ ]]; then
        if (( columns > 0 && columns < 80 )); then width=$((columns - 8)); fi
    fi
    (( width >= 16 )) || width=16
    printf '%s' "$width"
}

memory_line() {
    local width=${1:-$(memory_width)} prefix='Free GiB:' line item name value index start gpu=0 hidden=0
    local -a items=()
    [[ "$width" =~ ^[0-9]{1,3}$ ]] || width=72
    (( width >= 16 )) || width=16
    value=N/A
    if [[ -n "$RAM_AVAILABLE" ]]; then value=$(memory_gib "$RAM_AVAILABLE"); fi
    if [[ $(platform_memory_style) != margins ]]; then
        if [[ "$value" != N/A ]]; then value="~$value"; fi
        line="$prefix RAM $value"
        if (( ${#line} > width )); then line="GiB: RAM $value"; fi
        if (( ${#line} > width )); then line='Memory: N/A'; fi
        printf '%s' "$line"; return 0
    fi
    items+=("RAM $value")
    for name in "${GPU_DEVICE_NAMES[@]}"; do
        [[ "$DEVICE" != none ]] || break
        gpu=$((gpu + 1))
        item=GPU
        if (( ${#GPU_DEVICE_NAMES[@]} > 1 )); then item="GPU$gpu"; fi
        items+=("$item $(memory_gib "${DEVICE_FREE[$name]}")")
    done
    if [[ "$DEVICE" == none ]]; then items+=('GPU off');
    elif (( gpu == 0 )); then items+=('GPU N/A'); fi
    line=$prefix
    start=$(( ${MEMORY_PAGE:-0} % ${#items[@]} ))
    for ((index=0; index<${#items[@]}; index++)); do
        item=${items[(start + index) % ${#items[@]}]}
        if [[ "$line" == "$prefix" ]]; then item=" $item"; else item=" | $item"; fi
        # The Next memory button exposes pools omitted from this page.
        if (( ${#line} + ${#item} + 4 > width )); then hidden=$((hidden + 1));
        else line+=$item; fi
    done
    if (( hidden > 0 )); then
        if [[ "$line" == "$prefix" ]]; then line='Memory: next';
        elif (( ${#line} + ${#hidden} + 2 <= width )); then line+=" +$hidden";
        else line='Memory: next'; fi
    fi
    printf '%s' "$line"
}

memory_controls() {
    MEMORY_TEXT=$(memory_line)
    MEMORY_BUTTONS=()
    if [[ "$MEMORY_TEXT" =~ \+[0-9]+$ || "$MEMORY_TEXT" == 'Memory: next' ]]; then
        MEMORY_BUTTONS=(--extra-button --extra-label 'Next memory')
    fi
}
