#!/usr/bin/env bash
# Optional native memory estimates. Never evaluate output as shell commands.

memory_available() {
    local line
    platform_memory_snapshot
    DEVICE_FREE=()
    # Shared/system-only memory comes from the OS, never a GPU probe process.
    [[ $(platform_memory_style) == margins ]] || return 0
    if server_devices; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]+([^[:space:]:]+):.*\(([0-9]{1,10})[[:space:]]MiB,[[:space:]]([0-9]{1,10})[[:space:]]MiB[[:space:]]free\)$ ]]; then
                if (( 10#${BASH_REMATCH[2]} > 0 )); then
                    DEVICE_FREE[${BASH_REMATCH[1]}]=$((10#${BASH_REMATCH[3]}))
                fi
            fi
        done <<< "$DEVICE_OUTPUT"
    fi
    return 0
}

memory_estimate() {
    local helper="${SERVER%/*}/llama-fit-params" output help flag value name model context compute extra parallel unified
    local -a fitted=() words=() estimator_args=()
    local -A pool_seen=()
    MEMORY_NAMES=(); MEMORY_MIB=()
    [[ -x "$helper" && -f "$MODEL" ]] || return 0
    help=$(platform_timeout 20 "$helper" --help) || return 0
    [[ "$help" == *--fit-print* ]] || return 0
    build_model_args
    estimator_args=("${MODEL_ARGS[@]}")
    # Estimate only layouts the helper can represent, including server-only
    # defaults and native environment controls that older helpers may ignore.
    server_capabilities
    [[ -n "$SERVER_HELP" ]] || return 0
    parallel=${LLAMA_ARG_N_PARALLEL-}
    if [[ ! -v LLAMA_ARG_N_PARALLEL ]]; then
        if [[ "$SERVER_HELP" == *'default: -1, -1 = auto'* ]]; then parallel=-1;
        elif [[ "$SERVER_HELP" == *'number of server slots (default: 1)'* ]]; then parallel=1;
        else return 0; fi
    fi
    [[ "$parallel" =~ ^(-?)([0-9]{1,10})$ ]] || return 0
    value=$((10#${BASH_REMATCH[2]}))
    (( value > 0 && value <= 2147483647 )) || return 0
    if [[ "${BASH_REMATCH[1]}" == - ]]; then value=$((-value)); fi
    parallel=$value
    unified=${LLAMA_ARG_KV_UNIFIED-false}
    if [[ -v LLAMA_ARG_NO_KV_UNIFIED ]]; then unified=false; fi
    case "$unified" in
        on|enabled|true|1) unified=true ;;
        off|disabled|false|0) unified=false ;;
        *) return 0 ;;
    esac
    if (( parallel < 0 )); then
        [[ "$SERVER_HELP" == *'default: -1, -1 = auto'* ]] || return 0
        parallel=4
        unified=true
    fi
    if (( parallel != 1 )) || [[ -v LLAMA_ARG_N_PARALLEL ]]; then
        [[ "$help" == *--parallel* ]] || return 0
        estimator_args+=(--parallel "$parallel")
    fi
    if "$unified"; then
        [[ "$help" == *--kv-unified* ]] || return 0
        estimator_args+=(--kv-unified)
    elif [[ "$help" == *--no-kv-unified* ]]; then estimator_args+=(--no-kv-unified);
    elif [[ "$help" == *--kv-unified* ]]; then return 0;
    fi
    # Fitting is advisory only. Its output is passed as literal argument pairs.
    if output=$(platform_timeout 20 "$helper" "${estimator_args[@]}" --fit-print off); then
        [[ "$output" != *$'\n'* ]] || return 0
        read -r -a words <<< "$output"
        (( ${#words[@]} > 0 && ${#words[@]} % 2 == 0 )) || return 0
    elif [[ "$GPU_LAYERS" == auto && "$DEVICE" != none ]]; then
        return 0
    fi
    # Explicit placement can still be measured when fitting reports insufficient
    # memory. This is precisely where showing a negative margin is useful.
    while (( ${#words[@]} )); do
        flag=${words[0]}; value=${words[1]}; words=("${words[@]:2}")
        case "$flag" in
            -c) [[ "$value" =~ ^[0-9]+$ ]] || return 0 ;;
            -ngl) [[ "$value" =~ ^-?[0-9]+$ ]] || return 0 ;;
            -ts) [[ "$value" =~ ^[0-9]+(,[0-9]+)*$ ]] || return 0 ;;
            -ot)
                value=${value#\"}; value=${value%\"}
                [[ -n "$value" && "$value" != *\"* && "$value" != *\'* ]] || return 0 ;;
            *) return 0 ;;
        esac
        fitted+=("$flag" "$value")
    done
    output=$(platform_timeout 20 "$helper" "${estimator_args[@]}" "${fitted[@]}" --fit-print on) || return 0
    while read -r name model context compute extra; do
        [[ "$name" =~ ^[[:alnum:]_.-]+$ && "$model" =~ ^[0-9]{1,10}$ && "$context" =~ ^[0-9]{1,10}$ && "$compute" =~ ^[0-9]{1,10}$ && -z "$extra" ]] || { MEMORY_NAMES=(); MEMORY_MIB=(); return 0; }
        if [[ -v "pool_seen[$name]" ]]; then MEMORY_NAMES=(); MEMORY_MIB=(); return 0; fi
        pool_seen[$name]=1
        if [[ "$name" == Host ]]; then
            MEMORY_NAMES=("$name" "${MEMORY_NAMES[@]}")
            MEMORY_MIB=("$((10#$model + 10#$context + 10#$compute))" "${MEMORY_MIB[@]}")
        else
            MEMORY_NAMES+=("$name")
            MEMORY_MIB+=("$((10#$model + 10#$context + 10#$compute))")
        fi
    done <<< "$output"
    [[ " ${MEMORY_NAMES[*]} " == *' Host '* ]] || { MEMORY_NAMES=(); MEMORY_MIB=(); return 0; }
}

memory_gib() {
    local mib=$1 sign=''
    if (( mib < 0 )); then sign=-; mib=$((-mib)); fi
    printf '%s%d.%d' "$sign" "$((mib / 1024))" "$(((mib % 1024) * 10 / 1024))"
}

# dialog's 80-column box needs space for borders and horizontal padding.
memory_width() {
    local rows columns width=72
    if [[ -t 0 ]] && read -r rows columns < <(stty size 2>/dev/null) && [[ "$columns" =~ ^[0-9]{1,3}$ ]]; then
        if (( columns > 0 && columns < 80 )); then width=$((columns - 8)); fi
    fi
    (( width >= 16 )) || width=16
    printf '%s' "$width"
}

memory_line() {
    local mode=$1 width=${2:-$(memory_width)} prefix='Est. free GiB:' line item name available value style i index start gpu=0 hidden=0
    local -a items=()
    [[ "$width" =~ ^[0-9]{1,3}$ ]] || width=72
    (( width >= 16 )) || width=16
    style=$(platform_memory_style)
    if [[ "$style" != margins ]]; then
        value=$RAM_AVAILABLE
        if [[ "$mode" == live ]]; then prefix='Free GiB:';
        elif [[ -n "$value" && ${#MEMORY_NAMES[@]} -gt 0 ]]; then
            for i in "${!MEMORY_NAMES[@]}"; do
                # A separate accelerator cannot be charged to system RAM.
                if [[ "$style" != shared && "${MEMORY_NAMES[i]}" != Host ]] && (( MEMORY_MIB[i] > 0 )); then
                    value=''; break
                fi
                value=$((value - MEMORY_MIB[i]))
            done
        else value=''; fi
        if [[ -n "$value" ]]; then value="~$(memory_gib "$value")"; else value=N/A; fi
        line="$prefix RAM $value"
        if (( ${#line} > width )); then line="GiB: RAM $value"; fi
        if (( ${#line} > width )); then line='Memory: N/A'; fi
        printf '%s' "$line"; return 0
    elif [[ "$mode" == live ]]; then
        prefix='Free GiB:'
        value=N/A
        [[ -z "$RAM_AVAILABLE" ]] || value=$(memory_gib "$RAM_AVAILABLE")
        items+=("RAM $value")
        for name in "${!DEVICE_FREE[@]}"; do
            [[ "$DEVICE" != none ]] || break
            gpu=$((gpu + 1))
            item=GPU
            if (( ${#DEVICE_FREE[@]} > 1 )); then item="GPU$gpu"; fi
            items+=("$item $(memory_gib "${DEVICE_FREE[$name]}")")
        done
        if [[ "$DEVICE" == none ]]; then items+=('GPU off');
        elif (( gpu == 0 )); then items+=('GPU N/A'); fi
    else
        if (( ${#MEMORY_NAMES[@]} == 0 )); then
            line='Est. free: unavailable'
            if (( ${#line} > width )); then line='Est.: N/A'; fi
            printf '%s' "$line"; return 0
        fi
        for i in "${!MEMORY_NAMES[@]}"; do
            name=${MEMORY_NAMES[i]}; available=${DEVICE_FREE[$name]:-}; item=RAM
            if [[ "$name" == Host ]]; then available=$RAM_AVAILABLE;
            else
                gpu=$((gpu + 1)); item=GPU
                if (( ${#MEMORY_NAMES[@]} > 2 )); then item="GPU$gpu"; fi
            fi
            value=N/A
            [[ -z "$available" ]] || value=$(memory_gib "$((available - MEMORY_MIB[i]))")
            items+=("$item $value")
        done
    fi
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

refresh_memory() {
    local key
    # Reuse expensive model planning until settings change; refresh free budgets.
    key=$(printf '%s\n' "$SERVER" "$MODEL" "$CTX_SIZE" "$DEVICE" "$THREADS" "$GPU_LAYERS" "$PROMPT_PROCESSING" \
        "${LLAMA_ARG_N_PARALLEL+x}:${LLAMA_ARG_N_PARALLEL-}" \
        "${LLAMA_ARG_KV_UNIFIED+x}:${LLAMA_ARG_KV_UNIFIED-}" \
        "${LLAMA_ARG_NO_KV_UNIFIED+x}:${LLAMA_ARG_NO_KV_UNIFIED-}")
    if [[ "$key" != "${MEMORY_KEY:-}" ]]; then memory_estimate; MEMORY_KEY=$key; fi
    memory_available
}

memory_controls() {
    MEMORY_TEXT=$(memory_line "$1")
    MEMORY_BUTTONS=()
    if [[ "$MEMORY_TEXT" =~ \+[0-9]+$ || "$MEMORY_TEXT" == 'Memory: next' ]]; then
        MEMORY_BUTTONS=(--extra-button --extra-label 'Next memory')
    fi
}
