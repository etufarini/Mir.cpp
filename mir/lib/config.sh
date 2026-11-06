#!/usr/bin/env bash

fail() { printf '%s\n' "$*" >&2; exit 1; }

# llama.cpp accepts counts as signed 32-bit integers.

valid_count() { [[ "$1" =~ ^(0|[1-9][0-9]{0,9})$ ]] && (( $1 <= 2147483647 )); }

valid_threads() { [[ "$1" == auto ]] || { valid_count "$1" && [[ "$1" != 0 ]]; }; }

valid_context() { [[ "$1" == auto ]] || valid_count "$1"; }

valid_device() { [[ "$1" =~ ^[a-zA-Z0-9_.:-]+(,[a-zA-Z0-9_.:-]+)*$ ]]; }

valid_layers() { [[ "$1" == auto || "$1" == all ]] || valid_count "$1"; }

valid_split_mode() { case "$1" in auto|none|layer|row|tensor) return 0 ;; *) return 1 ;; esac; }

# Ratios may contain decimals; memory margins are whole MiB. Never evaluate input.
valid_gpu_list() {
    local kind=$1 value nonzero=false
    [[ "$2" == auto ]] && return 0
    [[ "$2" =~ ^[0-9]+(\.[0-9]+)?(,[0-9]+(\.[0-9]+)?)*$ ]] || return 1
    local -a values
    IFS=, read -r -a values <<< "$2"
    for value in "${values[@]}"; do
        if [[ "$kind" == ratios ]]; then
            [[ "$value" =~ ^(0|[1-9][0-9]{0,9})(\.[0-9]{1,9})?$ ]] || return 1
            valid_count "${value%%.*}" || return 1
            if [[ ! "$value" =~ ^0(\.0+)?$ ]]; then nonzero=true; fi
        else
            valid_count "$value" || return 1
        fi
    done
    [[ "$kind" != ratios ]] || "$nonzero"
}

valid_cache_type() { [[ "$1" =~ ^[a-z][a-z0-9_]{0,31}$ ]]; }

valid_port() { [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 )); }

# The first seven fields are sampling settings; seed and length stay separate.
generation_preset_values() {
    case "$1" in
        default) printf 'auto auto auto auto auto auto auto' ;;
        focused) printf '0.6 0.95 20 0 1 0 0' ;;
        exploratory) printf '1 0.95 20 0 1 0 0' ;;
        min-p) printf '1 1 0 0.05 1 0 0' ;;
        *) return 1 ;;
    esac
}

set_generation_preset() {
    local values i
    local -a fields
    values=$(generation_preset_values "$1") || return 1
    read -r -a fields <<< "$values"
    for i in "${!fields[@]}"; do GENERATION[${GENERATION_KEYS[i]}]=${fields[i]}; done
}

generation_preset() {
    local preset values='' key
    for key in "${GENERATION_KEYS[@]:0:7}"; do values+="${GENERATION[$key]} "; done
    for preset in default focused exploratory min-p; do
        if [[ "${values% }" == "$(generation_preset_values "$preset")" ]]; then printf '%s' "$preset"; return; fi
    done
    printf custom
}

valid_generation_value() {
    local key=$1 value=$2 magnitude=${2#-}
    [[ "$value" != auto ]] || return 0
    case "$key" in
        seed) [[ "$value" == -1 ]] || { [[ "$value" =~ ^(0|[1-9][0-9]{0,9})$ ]] && (( value <= 4294967295 )); }; return ;;
        max_tokens) [[ "$value" == -1 ]] || valid_count "$value"; return ;;
        top_k) valid_count "$value"; return ;;
    esac
    # Reject expressions, infinities and excessive precision before arithmetic.
    [[ "$value" =~ ^-?(0|[1-9][0-9]{0,9})(\.[0-9]{1,9})?$ ]] || return 1
    valid_count "${magnitude%%.*}" || return 1
    case "$key" in
        top_p|min_p) [[ "$value" != -* && ( "$value" == 0 || "$value" == 0.* || "$value" =~ ^1(\.0+)?$ ) ]] ;;
        temperature) [[ "$value" != -* ]] ;;
        repeat_penalty) [[ "$value" != -* && ! "$value" =~ ^0(\.0+)?$ ]] ;;
        presence_penalty|frequency_penalty) return 0 ;;
        *) return 1 ;;
    esac
}

# Preserve explicit empty MIR_* values; callers supply legacy LLAMA_* defaults.
read_launcher_control() {
    local control="MIR_$2"
    if [[ -v "$control" ]]; then
        printf -v "$1" '%s' "${!control}"
    else
        printf -v "$1" '%s' "$3"
    fi
}

initialize_config() {
    local key legacy value preset
    CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mir.cpp"
    migrate_config || fail 'Cannot import previous launcher settings. The original settings were kept; check configuration folder permissions and retry.'
    PATHS_FILE="$CONFIG_DIR/paths.conf"
    LLAMA_CPP_PATH=""
    MODELS_DIR=""
    PATHS_WARNING=""
    if [[ -e "$PATHS_FILE" ]] && ! load_paths; then PATHS_WARNING='Saved paths could not be read. Set them again in Folders.'; fi
    read_launcher_control LLAMA_CPP_PATH LLAMA_CPP_DIR "${LLAMA_CPP_DIR:-$LLAMA_CPP_PATH}"
    read_launcher_control MODELS_DIR MODELS_DIR "${LLAMA_MODELS_DIR:-$MODELS_DIR}"
    SERVER=$(server_path "$LLAMA_CPP_PATH")
    MODEL="${1:-}"
    read_launcher_control CTX_SIZE CTX_SIZE "${LLAMA_CTX_SIZE:-auto}"
    read_launcher_control PORT PORT "${LLAMA_PORT:-9931}"
    read_launcher_control DEVICE DEVICE "${LLAMA_DEVICE:-auto}"
    read_launcher_control THREADS THREADS "${LLAMA_THREADS:-auto}"
    read_launcher_control GPU_LAYERS GPU_LAYERS "${LLAMA_GPU_LAYERS:-auto}"
    read_launcher_control SPLIT_MODE SPLIT_MODE auto
    read_launcher_control TENSOR_SPLIT TENSOR_SPLIT auto
    read_launcher_control FIT_TARGET FIT_TARGET auto
    read_launcher_control PROMPT_PROCESSING PROMPT_PROCESSING "${LLAMA_PROMPT_PROCESSING:-auto}"
    read_launcher_control CACHE_TYPE_K CACHE_TYPE_K "${LLAMA_ARG_CACHE_TYPE_K-q4_0}"
    read_launcher_control CACHE_TYPE_V CACHE_TYPE_V "${LLAMA_ARG_CACHE_TYPE_V-q4_0}"
    declare -ga GENERATION_KEYS=(temperature top_p top_k min_p repeat_penalty presence_penalty frequency_penalty seed max_tokens)
    declare -gA GENERATION=([seed]=auto [max_tokens]=auto)
    read_launcher_control preset GENERATION_PRESET "${LLAMA_GENERATION_PRESET:-default}"
    set_generation_preset "$preset" || fail 'MIR_GENERATION_PRESET must be default, focused, exploratory or min-p.'
    for key in "${GENERATION_KEYS[@]}"; do
        legacy="LLAMA_${key^^}"
        value=${GENERATION[$key]}
        if [[ -v "$legacy" ]]; then value=${!legacy}; fi
        read_launcher_control value "${key^^}" "$value"
        GENERATION[$key]=$value
    done
    read_launcher_control SERVER_HOST HOST "${LLAMA_HOST:-}"
    PROFILES_DIR="$CONFIG_DIR/profiles"
    declare -ga MEMORY_NAMES=() MEMORY_MIB=()
    declare -gA DEVICE_FREE=()
    MEMORY_KEY=""
    MEMORY_PAGE=0
    declare -ga MEMORY_BUTTONS=()
    CURRENT_PROFILE=""
    SAVED_PROFILE=""
    CAPABILITIES_SERVER=""
    SERVER_HELP=""
    TUI=false
    if (( $# == 0 )); then TUI=true; fi
}

validate_config() {
    local key control
    valid_port "$PORT" || fail 'Port must be an integer between 1 and 65535.'
    PORT=$((10#$PORT))
    valid_context "$CTX_SIZE" || fail 'MIR_CTX_SIZE must be auto or an integer from 0 to 2147483647 (0 requests the full model context).'
    valid_device "$DEVICE" || fail 'MIR_DEVICE must be auto, none or a comma-separated list of device names.'
    valid_threads "$THREADS" || fail 'MIR_THREADS must be auto or a positive integer (up to 2147483647).'
    valid_layers "$GPU_LAYERS" || fail 'MIR_GPU_LAYERS must be auto, all or a nonnegative integer (up to 2147483647).'
    valid_split_mode "$SPLIT_MODE" || fail 'MIR_SPLIT_MODE must be auto, none, layer, row or tensor.'
    valid_gpu_list ratios "$TENSOR_SPLIT" || fail 'MIR_TENSOR_SPLIT must be auto or comma-separated nonnegative proportions, with at least one positive value.'
    valid_gpu_list margins "$FIT_TARGET" || fail 'MIR_FIT_TARGET must be auto or comma-separated nonnegative MiB integers (up to 2147483647).'
    for key in K V; do
        control="CACHE_TYPE_$key"
        valid_cache_type "${!control}" || fail "MIR_$control must be a lowercase cache type advertised by llama-server (for example q4_0, q8_0 or f16)."
    done
    case "$PROMPT_PROCESSING" in
        auto|low-memory|large-batch) ;;
        *) fail 'MIR_PROMPT_PROCESSING must be auto, low-memory or large-batch.' ;;
    esac
    for key in "${GENERATION_KEYS[@]}"; do
        valid_generation_value "$key" "${GENERATION[$key]}" || fail "Invalid MIR_${key^^}. Use auto or a valid generation value."
    done
    check_dependencies runtime || exit 1
}
