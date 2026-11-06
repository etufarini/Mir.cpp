#!/usr/bin/env bash
# Storage failures must preserve files, active settings and profile association.
set -euo pipefail
TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
for variable in ${!MIR_@} ${!LLAMA_@} ${!XDG_@}; do unset "$variable"; done
MIR_ROOT=$TEST_ROOT
source "$MIR_ROOT/tests/helpers/core.sh"
load_test_core fake
work=$(mktemp -d)
trap 'command rm -rf -- "$work"' EXIT
export HOME="$work/home" XDG_CONFIG_HOME="$work/config"
mkdir -p "$HOME" "$work/bin" "$work/models" "$work/empty" "$work/other-models" \
    "$work/llama/bin" "$work/other-llama/build/bin"
for tool in find mv; do
    executable=$(command -v "g$tool" || command -v "$tool")
    ln -s "$executable" "$work/bin/$tool"
done
export PATH="$work/bin:$PATH"
cd -- "$work"
touch "$work/models/first.gguf" "$work/models/selected.gguf" "$work/other-models/new.gguf" \
    "$work/llama/bin/llama-server" "$work/other-llama/build/bin/llama-server"
chmod +x "$work/llama/bin/llama-server" "$work/other-llama/build/bin/llama-server"
initialize_config "$work/models/selected.gguf"
LLAMA_CPP_PATH="$work/llama" MODELS_DIR="$work/models"
SERVER=$(server_path "$LLAMA_CPP_PATH")
save_paths
cp "$PATHS_FILE" "$work/paths.before"
write_profile "$PROFILES_DIR/Saved.conf"
profile_snapshot=$(profile_data)
association=$CURRENT_PROFILE
tracking=$SAVED_PROFILE

# Malformed path files must not partially apply an earlier valid field.
for data in \
    '' \
    'llama_dir=changed' \
    $'llama_dir=changed\nmodels_dir=new\nunknown=value' \
    $'llama_dir=changed\nllama_dir=duplicate\nmodels_dir=new' \
    $'llama_dir=changed\nmalformed'; do
    printf '%s\n' "$data" > "$PATHS_FILE"
    if load_paths; then printf 'FAIL: malformed paths accepted\n' >&2; exit 1; fi
    [[ $LLAMA_CPP_PATH == "$work/llama" && $MODELS_DIR == "$work/models" ]]
done
literal_path="\$(touch executed)"
printf 'llama_dir=%s\nmodels_dir=literal value' "$literal_path" > "$PATHS_FILE"
load_paths
[[ $LLAMA_CPP_PATH == "$literal_path" && $MODELS_DIR == 'literal value' && ! -e executed ]]
LLAMA_CPP_PATH="$work/llama" MODELS_DIR="$work/models"
cp "$work/paths.before" "$PATHS_FILE"
load_paths
printf 'PASS: path data parsing, duplicate/unknown/malformed rejection and unterminated literal values\n'

# File-backed responses survive the subshells used by menus.
menu() {
    local choice
    IFS= read -r choice < "$work/queue" || return 255
    tail -n +2 "$work/queue" > "$work/queue.next"
    command mv -- "$work/queue.next" "$work/queue"
    printf '%s' "$choice"
}
select_folder() { printf '%s\n' "$FOLDER_CHOICE"; }
message() { printf '%s\n' "$*" >> "$work/messages"; }
ui() { return "$CONFIRM_STATUS"; }

for action in llama models; do
    if [[ $action == llama ]]; then FOLDER_CHOICE="$work/other-llama";
    else FOLDER_CHOICE="$work/other-models"; fi
    printf '%s\nback\n' "$action" > "$work/queue"
    mv() { return 1; }
    paths_menu
    unset -f mv
    cmp -s "$PATHS_FILE" "$work/paths.before"
    [[ $LLAMA_CPP_PATH == "$work/llama" && $MODELS_DIR == "$work/models" ]]
    [[ $SERVER == "$work/llama/bin/llama-server" && $(profile_data) == "$profile_snapshot" ]]
    [[ $CURRENT_PROFILE == "$association" && $SAVED_PROFILE == "$tracking" ]]
    [[ $(profile_status) == Saved && ! -s "$work/queue" ]]
    temporary=("$CONFIG_DIR"/.paths.*)
    [[ ! -e ${temporary[0]} ]]
done
[[ $(cat "$work/messages") == *'Cannot save paths'* ]]
printf 'PASS: failed atomic path replacement preserves both folders, server, profile and saved file\n'

FOLDER_CHOICE="$work/empty"
printf 'llama\nback\n' > "$work/queue"
paths_menu
cmp -s "$PATHS_FILE" "$work/paths.before"
[[ $LLAMA_CPP_PATH == "$work/llama" && $(profile_data) == "$profile_snapshot" ]]

FOLDER_CHOICE="$work/models"
printf 'models\nback\n' > "$work/queue"
paths_menu
[[ $MODEL == "$work/models/selected.gguf" && ${#MODELS[@]} == 2 && $(profile_status) == Saved ]]
FOLDER_CHOICE="$work/other-models"
printf 'models\nback\n' > "$work/queue"
paths_menu
[[ $MODEL == "$work/other-models/new.gguf" && ${#MODELS[@]} == 1 && $(profile_status) == 'Saved (Modified)' ]]
LLAMA_CPP_PATH='' MODELS_DIR=''
load_paths
[[ $LLAMA_CPP_PATH == "$work/llama" && $MODELS_DIR == "$work/other-models" ]]
FOLDER_CHOICE="$work/empty"
printf 'models\nback\n' > "$work/queue"
paths_menu
[[ -z $MODEL && ${#MODELS[@]} == 0 && ! -s "$work/queue" ]]
[[ $(cat "$work/messages") == *'No GGUF models found'* ]]
load_profile "$association"
printf 'PASS: invalid server folders, accepted model-folder refresh, selection retention and empty-folder recovery\n'

for operation in cancel failure success; do
    printf 'delete\n0\nback\n' > "$work/queue"
    CONFIRM_STATUS=0
    case "$operation" in
        cancel) CONFIRM_STATUS=1 ;;
        failure) rm() { return 1; } ;;
    esac
    configurations_menu
    unset -f rm
    [[ $(profile_data) == "$profile_snapshot" && ! -s "$work/queue" ]]
    if [[ $operation == success ]]; then
        [[ ! -e $association && -z $CURRENT_PROFILE && -z $SAVED_PROFILE ]]
        [[ $(profile_status) == 'Not saved' ]]
    else
        [[ -f $association && $CURRENT_PROFILE == "$association" && $SAVED_PROFILE == "$tracking" ]]
        [[ $(profile_status) == Saved ]]
        cmp -s "$association" <(printf '%s\n' "$profile_snapshot")
    fi
done
[[ $(cat "$work/messages") == *'Cannot delete configuration'* ]]
printf 'PASS: canceled/failed profile deletion preserves association; successful deletion clears it without changing settings\n'
