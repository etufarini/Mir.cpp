#!/usr/bin/env bash

server_capabilities() {
    [[ "${CAPABILITIES_SERVER:-}" != "$SERVER" ]] || return 0
    SERVER_HELP=$(platform_timeout 15 "$SERVER" --help) || SERVER_HELP=''
    CAPABILITIES_SERVER=$SERVER
}

supports_option() {
    local pattern="(^|[[:space:],])$1([[:space:]=,]|$)"
    [[ "$SERVER_HELP" =~ $pattern ]]
}

split_modes() {
    local line mode
    local -a modes
    while IFS= read -r line; do
        [[ "$line" == *--split-mode* && "$line" == *\{*\}* ]] || continue
        line=${line#*\{}; line=${line%%\}*}
        IFS=, read -r -a modes <<< "$line"
        for mode in "${modes[@]}"; do
            if [[ "$mode" =~ ^[a-z][a-z0-9_-]*$ ]]; then printf '%s\n' "$mode"; fi
        done
        break
    done <<< "$SERVER_HELP"
}

# Keep wrapped K/V value lists separate from draft-cache options.
cache_types() {
    local option="--cache-type-${1,,}" help=${2-$SERVER_HELP} line word active=false values=false
    local pattern="(^|[[:space:],])$option([[:space:]=,]|$)"
    local -a words
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*- ]]; then
            if [[ "$line" =~ $pattern ]]; then active=true;
            elif "$active"; then break; fi
        fi
        "$active" || continue
        if [[ "$line" == *'allowed values:'* ]]; then
            line=${line#*allowed values:}
            values=true
        elif ! "$values"; then continue; fi
        read -r -a words <<< "${line//,/ }"
        for word in "${words[@]}"; do
            valid_cache_type "$word" || return 0
            printf '%s\n' "$word"
        done
    done <<< "$help"
}

listed_value() {
    local value
    while IFS= read -r value; do
        [[ "$value" != "$1" ]] || return 0
    done <<< "$2"
    return 1
}

server_devices() {
    local line name description total available
    DEVICE_NAMES=(); DEVICE_DESCRIPTIONS=()
    GPU_DEVICE_NAMES=()
    declare -gA DEVICE_FREE=()
    DEVICE_OUTPUT=$(platform_timeout 15 "$SERVER" --list-devices) || return 1
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]+([^[:space:]:]+):[[:space:]]+(.+)$ ]]; then
            DEVICE_NAMES+=("${BASH_REMATCH[1]}")
            DEVICE_DESCRIPTIONS+=("${BASH_REMATCH[2]}")
            name=${BASH_REMATCH[1]}; description=${BASH_REMATCH[2]}
            # Native device lists may include CPU accelerators with no GPU pool.
            if [[ "$name" =~ ^[a-zA-Z0-9_.-]+$ && "$description" =~ \(([0-9]{1,10})[[:space:]]MiB,[[:space:]]([0-9]{1,10})[[:space:]]MiB[[:space:]]free\)$ ]]; then
                total=$((10#${BASH_REMATCH[1]})); available=$((10#${BASH_REMATCH[2]}))
                if (( total > 0 && available <= total )) && [[ ! -v "DEVICE_FREE[$name]" ]]; then
                    GPU_DEVICE_NAMES+=("$name")
                    DEVICE_FREE[$name]=$available
                fi
            fi
        fi
    done <<< "$DEVICE_OUTPUT"
}

multi_gpu_available() {
    platform_multi_gpu_ui && (( ${#GPU_DEVICE_NAMES[@]} >= 2 ))
}

gpu_settings_active() {
    multi_gpu_available || return 1
    local device=${DEVICE:-auto} name
    local -a selected
    local -A unique=()
    if [[ "$device" == auto ]]; then device=${LLAMA_ARG_DEVICE:-auto}; fi
    [[ "$device" != auto ]] || return 0
    IFS=, read -r -a selected <<< "$device"
    for name in "${selected[@]}"; do
        [[ " ${GPU_DEVICE_NAMES[*]} " == *" $name "* ]] || return 1
        unique[$name]=1
    done
    (( ${#unique[@]} >= 2 ))
}

refresh_gpu_settings() {
    GPU_SETTINGS_ACTIVE=false
    if platform_multi_gpu_ui && server_devices && gpu_settings_active; then GPU_SETTINGS_ACTIVE=true; fi
}

launch_error() { LAUNCH_ERROR=$*; return 1; }

# Read overrides for safety checks without rewriting pass-through arguments.
resolve_endpoint() {
    local host=${SERVER_HOST:-${LLAMA_ARG_HOST:-127.0.0.1}} argument address line pattern count
    EFFECTIVE_DEVICE=${LLAMA_ARG_DEVICE:-auto}
    EFFECTIVE_CACHE_TYPE_K=$CACHE_TYPE_K
    EFFECTIVE_CACHE_TYPE_V=$CACHE_TYPE_V
    EFFECTIVE_SPLIT_MODE=${LLAMA_ARG_SPLIT_MODE-auto}
    CURL_ARGS=(--noproxy '*' --globoff)
    UNIX_SOCKET=''
    while (( $# )); do
        argument=$1
        case "$argument" in
            --port|--host|--device|-dev|--cache-type-k|-ctk|--cache-type-v|-ctv|--split-mode|-sm|--tensor-split|-ts|--fit-target|-fitt)
                (( $# >= 2 )) || { launch_error "Missing value for $argument."; return 1; }
                case "$argument" in
                    --port) PORT=$2 ;;
                    --host) host=$2 ;;
                    --cache-type-k|-ctk) EFFECTIVE_CACHE_TYPE_K=$2 ;;
                    --cache-type-v|-ctv) EFFECTIVE_CACHE_TYPE_V=$2 ;;
                    --split-mode|-sm) EFFECTIVE_SPLIT_MODE=$2 ;;
                    --tensor-split|-ts|--fit-target|-fitt) : ;;
                    *) EFFECTIVE_DEVICE=$2 ;;
                esac
                shift ;;
            --port=*) PORT=${argument#*=} ;;
            --host=*) host=${argument#*=} ;;
            --device=*|-dev=*) EFFECTIVE_DEVICE=${argument#*=} ;;
            --cache-type-k=*|-ctk=*) EFFECTIVE_CACHE_TYPE_K=${argument#*=} ;;
            --cache-type-v=*|-ctv=*) EFFECTIVE_CACHE_TYPE_V=${argument#*=} ;;
            --split-mode=*|-sm=*) EFFECTIVE_SPLIT_MODE=${argument#*=} ;;
            -*)
                # Infer value counts from native help so --alias '--port' stays
                # data. Leave unknown switches for llama.cpp to interpret.
                if [[ "$argument" =~ ^--?[a-zA-Z0-9_-]+$ ]]; then
                    pattern="(^|[[:space:],])$argument([,[:space:]]+--?[a-zA-Z0-9_-]+)*[[:space:]]([A-Z<\[{][^[:space:]]*)([[:space:]]([A-Z][^[:space:]]*))?"
                    while IFS= read -r line; do
                        if [[ "$line" =~ $pattern ]]; then
                            count=1
                            if [[ -n "${BASH_REMATCH[5]}" ]]; then count=2; fi
                            if [[ "${BASH_REMATCH[3]}" == \[* && "${2:--}" == -* ]]; then count=0; fi
                            (( $# > count )) || { launch_error "Missing value for $argument."; return 1; }
                            shift "$count"
                            break
                        fi
                    done <<< "${SERVER_HELP:-}"
                fi ;;
        esac
        shift
    done
    valid_port "$PORT" || { launch_error 'The effective TCP port must be between 1 and 65535.'; return 1; }
    PORT=$((10#$PORT))
    [[ -n "$host" ]] || { launch_error 'The server bind address cannot be empty.'; return 1; }
    # Use the first TCP address. A socket-only bind is checked through curl.
    local -a addresses
    IFS=, read -r -a addresses <<< "$host"
    host=''
    for address in "${addresses[@]}"; do
        address=${address#"${address%%[![:space:]]*}"}
        address=${address%"${address##*[![:space:]]}"}
        if [[ "$address" == *.sock ]]; then
            if [[ -z "$UNIX_SOCKET" ]]; then UNIX_SOCKET=$address; fi
        elif [[ -n "$address" ]]; then host=$address; break; fi
    done
    if [[ -z "$host" && -n "$UNIX_SOCKET" ]]; then
        CURL_ARGS+=(--unix-socket "$UNIX_SOCKET")
        URL="Unix socket: $UNIX_SOCKET"
        HEALTH_URL=http://localhost
        return 0
    fi
    UNIX_SOCKET=''
    case "$host" in
        0.0.0.0) host=127.0.0.1 ;;
        ::|'[::]') host=::1 ;;
        '') launch_error 'No usable server bind address.'; return 1 ;;
    esac
    if [[ "$host" == *:* && "$host" != \[*\] ]]; then host="[$host]"; fi
    URL="http://$host:$PORT"
    HEALTH_URL=$URL
}

prepare_server() {
    local key flag name found types value
    LAUNCH_ERROR=''
    [[ -f "$SERVER" && -x "$SERVER" ]] || { launch_error 'llama-server not found. Set the llama.cpp folder in Folders, or use MIR_LLAMA_CPP_DIR.'; return 1; }
    [[ -z "$PATHS_WARNING" || "$TUI" == true ]] || printf '%s\n' "$PATHS_WARNING" >&2
    [[ -f "$MODEL" && -r "$MODEL" ]] || { launch_error "GGUF model missing or unreadable: $MODEL"; return 1; }
    if "$TUI"; then refresh_gpu_settings; fi
    build_model_args
    ARGS=("${MODEL_ARGS[@]}" --port "$PORT")
    if [[ -n "$SERVER_HOST" ]]; then ARGS+=(--host "$SERVER_HOST"); fi
    # Sampling sets server defaults; browser requests may override them.
    for key in "${GENERATION_KEYS[@]}"; do
        [[ "${GENERATION[$key]}" != auto ]] || continue
        flag=${key//_/-}
        if [[ "$key" == max_tokens ]]; then flag=n-predict; fi
        ARGS+=("--$flag" "${GENERATION[$key]}")
    done
    server_capabilities
    if [[ -n "$SERVER_HELP" ]]; then
        for flag in "${ARGS[@]}"; do
            [[ "$flag" == --* ]] || continue
            if ! supports_option "$flag"; then
                if [[ "$flag" == --cache-type-* ]]; then
                    launch_error "This llama-server does not advertise $flag. Select a llama.cpp build supporting KV cache types in Folders."
                    return 1
                fi
                launch_error "This llama-server does not advertise $flag. Use Auto/Default for that setting or a build supporting it."
                return 1
            fi
        done
    else
        printf 'WARNING: Could not inspect llama-server options. Startup errors will be reported by the server.\n' >&2
    fi
    ARGS+=("$@")
    resolve_endpoint "${ARGS[@]}" || return 1
    types=$(split_modes)
    if [[ "$EFFECTIVE_DEVICE" != none && "$EFFECTIVE_SPLIT_MODE" != auto && -n "$types" ]] && ! listed_value "$EFFECTIVE_SPLIT_MODE" "$types"; then
        launch_error "GPU split mode '$EFFECTIVE_SPLIT_MODE' is not advertised by this llama-server. Review Performance > GPU memory."
        return 1
    fi
    for key in K V; do
        name="EFFECTIVE_CACHE_TYPE_$key"
        value=${!name}
        valid_cache_type "$value" || { launch_error "Invalid KV cache $key type: $value."; return 1; }
        types=$(cache_types "$key")
        if [[ -n "$types" ]] && ! listed_value "$value" "$types"; then
            launch_error "KV cache $key type '$value' is not advertised by this llama-server. Choose a supported type under Model settings > KV Cache."
            return 1
        fi
    done
    if [[ "$EFFECTIVE_DEVICE" != auto && "$EFFECTIVE_DEVICE" != none ]] && server_devices && [[ "$DEVICE_OUTPUT" == *'Available devices:'* ]]; then
        local -a selected_devices
        IFS=, read -r -a selected_devices <<< "$EFFECTIVE_DEVICE"
        for key in "${selected_devices[@]}"; do
            found=false
            for name in "${DEVICE_NAMES[@]}"; do if [[ "$name" == "$key" ]]; then found=true; break; fi; done
            if ! "$found"; then
                launch_error "Device '$key' is unavailable in this llama.cpp build. Choose Auto, CPU only or a detected device under Performance."
                return 1
            fi
        done
    fi
    if [[ -z "$UNIX_SOCKET" ]]; then
        check_port
        [[ -z "$LISTENERS" ]] || { launch_error "$PORT_STATUS"; return 1; }
    fi
}

build_model_args() {
    local setting flag
    MODEL_ARGS=(--model "$MODEL" --cache-type-k "$CACHE_TYPE_K" --cache-type-v "$CACHE_TYPE_V")
    # Omit automatic settings so llama.cpp can adapt to the available hardware.
    if [[ "$CTX_SIZE" != auto ]]; then MODEL_ARGS+=(--ctx-size "$CTX_SIZE"); fi
    if [[ "$THREADS" != auto ]]; then MODEL_ARGS+=(--threads "$THREADS"); fi
    if [[ "$DEVICE" != auto ]]; then MODEL_ARGS+=(--device "$DEVICE"); fi
    if [[ "$DEVICE" == none ]]; then MODEL_ARGS+=(--gpu-layers 0);
    elif [[ "$GPU_LAYERS" != auto ]]; then MODEL_ARGS+=(--gpu-layers "$GPU_LAYERS"); fi
    if [[ "$DEVICE" != none ]] && { ! "$TUI" || "$GPU_SETTINGS_ACTIVE"; }; then
        for setting in SPLIT_MODE TENSOR_SPLIT FIT_TARGET; do
            flag=${setting,,}; flag=${flag//_/-}
            if [[ "${!setting}" != auto ]]; then MODEL_ARGS+=("--$flag" "${!setting}"); fi
        done
    fi
    case "$PROMPT_PROCESSING" in
        low-memory) MODEL_ARGS+=(--batch-size 512 --ubatch-size 128) ;;
        large-batch) MODEL_ARGS+=(--batch-size 2048 --ubatch-size 1024) ;;
    esac
}

# Called by the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
    if [[ -n "${SERVER_PID:-}" ]]; then
        kill -TERM "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    [[ -z "$LOG_FILE" ]] || rm -f -- "$LOG_FILE"
}

run_server() {
    local OPENED RESULT
    LOG_FILE=""
    trap 'cleanup' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    if "$TUI"; then
        LOG_FILE=$(mktemp "${TMPDIR:-/tmp}/mir.cpp.XXXXXXXX")
        "$SERVER" "${ARGS[@]}" >"$LOG_FILE" 2>&1 &
    else
        printf 'Model: %s\nContext: %s\nWeb UI: %s\n' "$MODEL" "$(context_label)" "$URL"
        printf 'KV cache: K %s | V %s\n' "$EFFECTIVE_CACHE_TYPE_K" "$EFFECTIVE_CACHE_TYPE_V"
        printf 'Device: %s | CPU threads: %s | GPU layers: %s | Prompt processing: %s\nStop with Ctrl+C.\n' \
            "$DEVICE" "$THREADS" "$GPU_LAYERS" "$PROMPT_PROCESSING"
        "$SERVER" "${ARGS[@]}" &
    fi
    SERVER_PID=$!
    OPENED=false
    while kill -0 "$SERVER_PID" 2>/dev/null; do
        if ! "$OPENED" && curl "${CURL_ARGS[@]}" --silent --fail --max-time 2 "$HEALTH_URL/health" >/dev/null; then
            if [[ -z "$UNIX_SOCKET" ]]; then
                platform_open_url "$URL" >/dev/null 2>&1 || true
            fi
            OPENED=true
        fi
        if "$TUI"; then
            running_screen
        else
            sleep 2
        fi
    done
    RESULT=0
    wait "$SERVER_PID" || RESULT=$?
    SERVER_PID=""
    if "$TUI" && (( RESULT != 0 )); then view_log; fi
    exit "$RESULT"
}
