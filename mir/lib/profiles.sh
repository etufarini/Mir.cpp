#!/usr/bin/env bash

profile_data() {
    local key
    printf 'model=%s\ncontext=%s\nreasoning=%s\nport=%s\ndevice=%s\nthreads=%s\ngpu_layers=%s\nprompt_processing=%s\n' \
        "$MODEL" "$CTX_SIZE" "$REASONING" "$PORT" "$DEVICE" "$THREADS" "$GPU_LAYERS" "$PROMPT_PROCESSING"
    for key in "${GENERATION_KEYS[@]}"; do printf '%s=%s\n' "$key" "${GENERATION[$key]}"; done
}

profile_status() {
    local name
    if [[ -z "$CURRENT_PROFILE" ]]; then printf 'Not saved'; return; fi
    name="${CURRENT_PROFILE##*/}"
    printf '%s' "${name%.conf}"
    if [[ "$(profile_data)" != "$SAVED_PROFILE" ]]; then printf ' (Modified)'; fi
}

load_profile() {
    local file="$1" key line
    [[ -r "$file" ]] || return 1
    local -A settings=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == *=* ]] || return 1
        key="${line%%=*}"
        case "$key" in
            model|context|reasoning|port|device|threads|gpu_layers|prompt_processing|temperature|top_p|top_k|min_p|repeat_penalty|presence_penalty|frequency_penalty|seed|max_tokens) ;;
            *) return 1 ;;
        esac
        [[ ! -v "settings[$key]" ]] || return 1
        settings[$key]="${line#*=}"
    done < "$file"
    # Legacy profiles contain eight fields. New profiles require the full block.
    if (( ${#settings[@]} == 8 )); then
        for key in "${GENERATION_KEYS[@]}"; do
            [[ ! -v "settings[$key]" ]] || return 1
            settings[$key]=auto
        done
    fi
    (( ${#settings[@]} == 17 )) || return 1
    [[ -f "${settings[model]}" && "${settings[model],,}" == *.gguf ]] || return 1
    valid_context "${settings[context]}" || return 1
    case "${settings[reasoning]}" in auto|on|off) ;; *) return 1 ;; esac
    valid_port "${settings[port]}" || return 1
    valid_device "${settings[device]}" || return 1
    valid_threads "${settings[threads]}" || return 1
    valid_layers "${settings[gpu_layers]}" || return 1
    case "${settings[prompt_processing]}" in auto|low-memory|large-batch) ;; *) return 1 ;; esac
    for key in "${GENERATION_KEYS[@]}"; do valid_generation_value "$key" "${settings[$key]}" || return 1; done
    MODEL="${settings[model]}"
    CTX_SIZE="${settings[context]}"
    REASONING="${settings[reasoning]}"
    PORT=$((10#${settings[port]}))
    DEVICE="${settings[device]}"
    THREADS="${settings[threads]}"
    GPU_LAYERS="${settings[gpu_layers]}"
    PROMPT_PROCESSING="${settings[prompt_processing]}"
    for key in "${GENERATION_KEYS[@]}"; do GENERATION[$key]=${settings[$key]}; done
    CURRENT_PROFILE="$file"
    SAVED_PROFILE=$(profile_data)
}

# Persist atomically and update tracking only after a successful write.
# Return 2 for directory errors, 3 for temporary-file errors, 1 for write errors.
write_profile() {
    local file="$1" temporary
    mkdir -p -- "$PROFILES_DIR" || return 2
    temporary=$(mktemp "$PROFILES_DIR/.profile.XXXXXXXX") || return 3
    if profile_data > "$temporary" && mv -f -- "$temporary" "$file"; then
        CURRENT_PROFILE="$file"
        SAVED_PROFILE=$(profile_data)
    else
        rm -f -- "$temporary"
        return 1
    fi
}
