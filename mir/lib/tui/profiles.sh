#!/usr/bin/env bash

save_profile() {
    local name file result UI_TITLE='Save configuration'
    if [[ "${1:-}" == update ]]; then
        if [[ -z "$CURRENT_PROFILE" ]]; then message 'No current configuration. Use Save as first.'; return; fi
        file="$CURRENT_PROFILE"
        name="${file##*/}"; name="${name%.conf}"
        UI_TITLE='Update configuration'
        ui --yesno "Update configuration '$name' with the current settings?" 10 76 || return 0
    else
        name=$(ui --inputbox 'Configuration name (letters, numbers, spaces, dots, underscores or hyphens)' 10 78) || return 0
        if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9\ ._-]{0,79}$ ]]; then
            message 'Use 1-80 characters, starting with a letter or number.'
            return
        fi
        file="$PROFILES_DIR/$name.conf"
        if [[ -e "$file" ]]; then
            ui --yesno "Replace configuration '$name'?" 9 76 || return 0
        fi
    fi
    if [[ ! -f "$MODEL" || "${MODEL,,}" != *.gguf ]]; then message 'Select an existing GGUF model before saving.'; return; fi
    # One value per line; filenames containing line breaks cannot be stored.
    if [[ "$MODEL" == *$'\n'* || "$DEVICE" == *$'\n'* ]]; then
        message 'Cannot save values containing line breaks.'
        return
    fi
    if write_profile "$file"; then
        message "Configuration '$name' saved."
    else
        result=$?
        case "$result" in
            2) message 'Cannot create the configurations folder.' ;;
            3) message 'Cannot create configuration file.' ;;
            *) message 'Cannot save configuration.' ;;
        esac
    fi
}

configurations_menu() {
    local action=load file choice selected UI_TITLE='Saved configurations'
    local -a files options
    while true; do
        action=$(menu --default-item "$action" --menu "Configuration  $(compact_text "$(profile_status)" 53)\n\nLoad settings for review, or save the current settings." 15 76 5 \
            load 'Load configuration' update 'Update current' save 'Save as new configuration' delete 'Delete configuration' back Back) || return 0
        case "$action" in
            save) save_profile ;;
            update) save_profile update ;;
            load|delete)
                files=(); options=()
                if [[ -d "$PROFILES_DIR" ]]; then
                    mapfile -d '' -t files < <(find "$PROFILES_DIR" -maxdepth 1 -type f -name '*.conf' -print0 | sort -z)
                fi
                if (( ${#files[@]} == 0 )); then message 'No saved configurations.'; continue; fi
                selected=0
                for file in "${!files[@]}"; do
                    if [[ "${files[file]}" == "$CURRENT_PROFILE" ]]; then selected=$file; fi
                    choice="${files[file]##*/}"
                    options+=("$file" "${choice%.conf}")
                done
                if [[ "$action" == delete ]]; then choice='Delete configuration'; else choice='Load configuration'; fi
                choice=$(UI_TITLE="$choice" menu --default-item "$selected" --menu 'Select a saved configuration' 20 80 12 "${options[@]}") || continue
                file="${files[choice]}"
                if [[ "$action" == delete ]]; then
                    if UI_TITLE='Delete configuration' ui --yesno "Delete configuration '${file##*/}'?" 9 76; then
                        if rm -- "$file"; then
                            if [[ "$file" == "$CURRENT_PROFILE" ]]; then CURRENT_PROFILE=""; SAVED_PROFILE=""; fi
                        else message 'Cannot delete configuration.'; fi
                    fi
                elif load_profile "$file"; then
                    return 0
                else
                    message 'Cannot load configuration: missing model, invalid values or unreadable file. Current settings were kept.'
                fi ;;
            back) return 0 ;;
        esac
    done
}
