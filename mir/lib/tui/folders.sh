#!/usr/bin/env bash
# Folder browser and settings; navigation is saved only after confirmation.

select_folder() {
    local current="${1:-$HOME}" choice candidate entry label selected=use show_hidden=false UI_TITLE='Browse folders'
    local -a folders options
    [[ -d "$current" && -r "$current" && -x "$current" ]] || current="$HOME"
    current=$(cd -- "$current" && pwd -P) || return 1
    while true; do
        folders=(); options=(use 'Use this folder   Confirm selection' parent 'Parent folder     Go up one level' path 'Enter path        Type or paste a location')
        if "$show_hidden"; then label='Hide hidden folders'; else label='Show hidden folders'; fi
        options+=(hidden "$label")
        # Include directory symlinks, but never recurse while listing children.
        while IFS= read -r -d '' entry; do
            [[ -d "$entry" ]] || continue
            if ! "$show_hidden" && [[ "${entry##*/}" == .* ]]; then continue; fi
            folders+=("$entry")
            options+=("${#folders[@]}" "${entry##*/}/")
        done < <(find "$current" -mindepth 1 -maxdepth 1 -print0 | sort -z)
        choice=$(menu --default-item "$selected" \
            --menu "Current folder: $current\n\nActions above; folders below. Enter opens a folder or runs an action.\nChoose Use this folder to confirm; Back/Esc cancels." 22 80 12 "${options[@]}") || return 1
        selected="$choice"
        case "$choice" in
            use) printf '%s\n' "$current"; return 0 ;;
            hidden) if "$show_hidden"; then show_hidden=false; else show_hidden=true; fi; continue ;;
            parent) candidate="$(dirname -- "$current")" ;;
            path)
                candidate=$(ui --cancel-label Back --inputbox 'Enter a folder path. Spaces and ~/ are supported.' 10 78 "$current") || continue
                # shellcheck disable=SC2088 # Match a literal tilde entered by the user.
                if [[ "$candidate" == '~' ]]; then candidate="$HOME"; elif [[ "$candidate" == '~/'* ]]; then candidate="$HOME/${candidate:2}"; fi ;;
            *) candidate="${folders[choice-1]}" ;;
        esac
        if [[ "$candidate" == *$'\n'* || ! -d "$candidate" || ! -r "$candidate" || ! -x "$candidate" ]]; then
            message 'Choose an existing, readable folder without line breaks.'; continue
        fi
        candidate=$(cd -- "$candidate" && pwd -P) || continue
        if [[ "$candidate" != "$current" ]]; then current="$candidate"; selected=use; fi
    done
}

paths_menu() {
    local action=llama choice initial previous candidate UI_TITLE=Folders
    while true; do
        action=$(menu --default-item "$action" --menu "llama.cpp     $(compact_text "${LLAMA_CPP_PATH:-Not configured}")\nModels        $(compact_text "${MODELS_DIR:-Not configured}")\n\nChoose a folder. Valid changes are saved automatically." 17 80 3 \
            llama 'llama.cpp folder' models 'Models folder' back Back) || return 0
        [[ "$action" != back ]] || return 0
        if [[ "$action" == llama ]]; then initial="$LLAMA_CPP_PATH"; else initial="$MODELS_DIR"; fi
        choice=$(select_folder "$initial") || continue
        if [[ "$action" == llama ]]; then
            candidate=$(server_path "$choice")
            if [[ ! -f "$candidate" || ! -x "$candidate" ]]; then
                message 'This folder must contain executable build/bin/llama-server or bin/llama-server. Select the llama.cpp folder after building it.'; continue
            fi
            previous="$LLAMA_CPP_PATH"; LLAMA_CPP_PATH="$choice"
        else
            previous="$MODELS_DIR"; MODELS_DIR="$choice"
        fi
        if ! save_paths; then
            if [[ "$action" == llama ]]; then LLAMA_CPP_PATH="$previous"; else MODELS_DIR="$previous"; fi
            message 'Cannot save paths. The previous folder was kept.'; continue
        fi
        SERVER=$(server_path "$LLAMA_CPP_PATH")
        if [[ "$action" == models ]]; then
            scan_models
            if (( ${#MODELS[@]} == 0 )); then message 'No GGUF models found. The folder was saved; add models or choose another folder.'; fi
        fi
    done
}
