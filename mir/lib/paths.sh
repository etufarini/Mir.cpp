#!/usr/bin/env bash

# Source builds take precedence over package-manager layouts.
server_path() {
    local folder=$1 candidate
    [[ -n "$folder" ]] || return 0
    for candidate in "$folder/build/bin/llama-server" "$folder/bin/llama-server"; do
        if [[ -f "$candidate" && -x "$candidate" ]]; then printf '%s' "$candidate"; return 0; fi
    done
    printf '%s/build/bin/llama-server' "$folder"
}

# Stage beside the destination so migration can activate atomically.
migrate_config() {
    local legacy="${CONFIG_DIR%/*}/llama-launcher" temporary
    if [[ -e "$CONFIG_DIR" || -L "$CONFIG_DIR" ]]; then return 0; fi
    [[ -d "$legacy" ]] || return 0
    mkdir -p -- "${CONFIG_DIR%/*}" || return 1
    temporary=$(mktemp -d "${CONFIG_DIR%/*}/.mir-migration.XXXXXXXX") || return 1
    if cp -a -- "$legacy/." "$temporary/" && platform_move "$temporary" "$CONFIG_DIR" no-clobber; then
        # With no-clobber, a concurrently created destination leaves the stage.
        [[ ! -d "$temporary" ]] || rm -rf -- "$temporary"
        return 0
    fi
    rm -rf -- "$temporary"
    return 1
}

load_paths() {
    local line key
    local -A paths=()
    [[ -r "$PATHS_FILE" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == *=* ]] || return 1
        key="${line%%=*}"
        case "$key" in llama_dir|models_dir) ;; *) return 1 ;; esac
        [[ ! -v "paths[$key]" ]] || return 1
        paths[$key]="${line#*=}"
    done < "$PATHS_FILE"
    (( ${#paths[@]} == 2 )) || return 1
    LLAMA_CPP_PATH="${paths[llama_dir]}"
    MODELS_DIR="${paths[models_dir]}"
}

save_paths() {
    local temporary
    mkdir -p -- "$CONFIG_DIR" || return 1
    temporary=$(mktemp "$CONFIG_DIR/.paths.XXXXXXXX") || return 1
    if printf 'llama_dir=%s\nmodels_dir=%s\n' "$LLAMA_CPP_PATH" "$MODELS_DIR" > "$temporary" &&
        mv -f -- "$temporary" "$PATHS_FILE"; then return 0; fi
    rm -f -- "$temporary"
    return 1
}

scan_models() {
    local i found=false helper="${BASH_SOURCE[0]%/*}/gguf.py"
    local -a roles=() available=()
    MODELS=(); MODEL_OPTIONS=()
    if [[ -d "$MODELS_DIR" && -r "$MODELS_DIR" && -x "$MODELS_DIR" ]]; then
        # Follow file symlinks, without descending through linked directories.
        mapfile -d '' -t MODELS < <(platform_find_models "$MODELS_DIR" | sort -z)
    fi
    if (( ${#MODELS[@]} )) && [[ -r "$helper" ]] && command -v python3 >/dev/null; then
        mapfile -d '' -t roles < <(printf '%s\0' "${MODELS[@]}" | python3 "$helper")
        for i in "${!MODELS[@]}"; do
            case "${roles[i]:-unknown}" in component|continuation) ;; *) available+=("${MODELS[i]}") ;; esac
        done
        MODELS=("${available[@]}")
    fi
    for i in "${!MODELS[@]}"; do
        MODEL_OPTIONS+=("$i" "${MODELS[i]#"$MODELS_DIR"/}")
        if [[ "${MODELS[i]}" == "$MODEL" ]]; then found=true; fi
    done
    if ! "$found"; then MODEL="${MODELS[0]:-}"; fi
}
