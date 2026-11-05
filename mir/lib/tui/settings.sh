#!/usr/bin/env bash
# Model and performance settings menus.

generation_label() {
    case "$1" in
        temperature) printf Temperature ;;
        top_p) printf Top-P ;;
        top_k) printf Top-K ;;
        min_p) printf Min-P ;;
        repeat_penalty) printf 'Repeat penalty' ;;
        presence_penalty) printf 'Presence penalty' ;;
        frequency_penalty) printf 'Frequency penalty' ;;
        seed) printf Seed ;;
        max_tokens) printf 'Maximum output tokens' ;;
    esac
}

edit_generation_value() {
    local key=$1 hint choice UI_TITLE
    UI_TITLE=$(generation_label "$key")
    case "$key" in
        temperature) hint='Nonnegative decimal. Lower values reduce randomness.' ;;
        top_p|min_p) hint='Decimal from 0 to 1. Top-P: 1 disables; Min-P: 0 disables.' ;;
        top_k) hint='Integer from 0 to 2147483647; 0 disables the filter.' ;;
        repeat_penalty) hint='Positive decimal; 1 disables. Large penalties can harm output.' ;;
        presence_penalty|frequency_penalty) hint='Signed decimal; 0 disables. Penalties can harm useful repetition.' ;;
        seed) hint='Integer from 0 to 4294967295; -1 or 4294967295 selects random.\nIdentical output across devices or runs is not guaranteed.' ;;
        max_tokens) hint='Integer from 0 to 2147483647, or -1 for no fixed limit.\n0 evaluates input only. A short limit can cut off thinking or answers.' ;;
    esac
    if choice=$(ui --cancel-label Back --inputbox "$hint\n\nUse auto to leave the llama.cpp default unchanged." 13 80 "${GENERATION[$key]}"); then
        if valid_generation_value "$key" "$choice"; then GENERATION[$key]=$choice;
        else message "Invalid value. $hint\n\nUse auto or a number; decimals need a leading digit, a dot and at most nine decimal places."; fi
    fi
}

sampling_menu() {
    local action=temperature key label UI_TITLE='Custom sampling'
    local -a options
    while true; do
        options=()
        for key in "${GENERATION_KEYS[@]:0:7}"; do
            printf -v label '%-19s%s' "$(generation_label "$key")" "$(display_value "${GENERATION[$key]}" Default)"
            options+=("$key" "$label")
        done
        action=$(ui --cancel-label Back --default-item "$action" --menu 'Adjust server defaults for generated text.\nModel recommendations take priority over generic presets.' 22 80 8 "${options[@]}" back Back) || return 0
        [[ "$action" != back ]] || return 0
        edit_generation_value "$action"
    done
}

generation_menu() {
    local action=preset choice UI_TITLE=Generation
    while true; do
        action=$(ui --cancel-label Back --default-item "$action" --menu 'Presets change sampling only; seed and output limit stay separate.\nBrowser chat settings can override these server defaults.\nUse server defaults in the chat to follow this selection.' 20 80 5 \
            preset "Preset                 $(display_value "$(generation_preset)")" \
            sampling 'Sampling parameters    View or customize values' \
            seed "Seed                   $(display_value "${GENERATION[seed]}" Default)" \
            max_tokens "Maximum output tokens  $(display_value "${GENERATION[max_tokens]}" Default)" back Back) || return 0
        case "$action" in
            preset)
                if choice=$(UI_TITLE='Generation preset' ui --cancel-label Back --default-item "$(generation_preset)" --menu 'Starting points to test, not guarantees of quality.\nNo preset changes context, reasoning or hardware settings.' 18 80 5 \
                    default 'Default       Keep native sampling defaults' \
                    focused 'Focused       Temp 0.6; Top-P 0.95; Top-K 20' \
                    exploratory 'Exploratory   Temp 1; Top-P 0.95; Top-K 20' \
                    min-p 'Min-P         Temp 1; Min-P 0.05; Top-P/K off' \
                    custom 'Custom        Edit individual sampling parameters'); then
                    if [[ "$choice" == custom ]]; then sampling_menu; else set_generation_preset "$choice"; fi
                fi ;;
            sampling) sampling_menu ;;
            seed|max_tokens) edit_generation_value "$action" ;;
            back) return 0 ;;
        esac
    done
}

select_device() {
    local choice i UI_TITLE=Device
    local -a options=(auto 'Auto: let llama.cpp choose' none 'CPU only')
    if [[ -f "$SERVER" && -x "$SERVER" ]] && server_devices; then
        for i in "${!DEVICE_NAMES[@]}"; do options+=("${DEVICE_NAMES[i]}" "${DEVICE_DESCRIPTIONS[i]}"); done
    else
        message 'Could not list devices within the time limit, or probing is unavailable.\nCheck the llama.cpp folder and drivers. Auto and CPU only remain available.'
    fi
    if choice=$(ui --cancel-label Back --default-item "$DEVICE" --menu 'Choose a device supported by your llama.cpp build' 18 80 10 "${options[@]}"); then
        DEVICE="$choice"
    fi
}

performance_menu() {
    local action=device choice layers_label UI_TITLE=Performance
    while true; do
        layers_label=$(display_value "$GPU_LAYERS")
        if [[ "$DEVICE" == none ]]; then layers_label='Ignored (CPU only)'; fi
        action=$(ui --cancel-label Back --default-item "$action" --menu 'Auto and Default use llama.cpp defaults.\nFlash Attention stays automatic.' 18 80 5 \
            device "Device             $(compact_text "$(display_value "$DEVICE")" 53)" threads "CPU threads        $(display_value "$THREADS")" \
            layers "GPU layers         $layers_label" prompt "Prompt processing  $(display_value "$PROMPT_PROCESSING" Default)" back 'Back') || return 0
        case "$action" in
            device) select_device ;;
            threads)
                if choice=$(UI_TITLE='CPU threads' ui --cancel-label Back --inputbox 'CPU threads: auto or a positive integer.\nMore threads are not always faster.' 11 76 "$THREADS"); then
                    if valid_threads "$choice"; then THREADS="$choice"; else message 'Enter auto or a positive integer up to 2147483647.'; fi
                fi ;;
            layers)
                if choice=$(UI_TITLE='GPU layers' ui --cancel-label Back --inputbox 'GPU layers: auto, all or a nonnegative integer.\nAuto adapts to available device memory. All may exceed it.' 11 76 "$GPU_LAYERS"); then
                    if valid_layers "$choice"; then GPU_LAYERS="$choice"; else message 'Enter auto, all or an integer from 0 to 2147483647.'; fi
                fi ;;
            prompt)
                if choice=$(UI_TITLE='Prompt processing' ui --cancel-label Back --default-item "$PROMPT_PROCESSING" --menu 'Tune processing of input text. Generation speed may not improve.\nLarge batch needs more memory; use Default if unsure.' 14 80 3 \
                    auto 'Default: let llama.cpp choose' \
                    low-memory 'Low memory: smaller chunks of input text' \
                    large-batch 'Large batch: try larger chunks of input text'); then PROMPT_PROCESSING="$choice"; fi ;;
            back) return 0 ;;
        esac
    done
}

model_menu() {
    local action=model choice selected i UI_TITLE='Model settings'
    while true; do
        action=$(ui --cancel-label Back --default-item "$action" --menu 'Context includes input and output. Larger contexts need more memory.\nContext size and reasoning depend on model support.' 18 80 5 \
            model "Model         $(compact_text "${MODEL##*/}")" context "Context       $(context_label)" \
            reasoning "Reasoning     $(display_value "$REASONING")" \
            generation "Generation    $(display_value "$(generation_preset)")" back Back) || return 0
        case "$action" in
            model)
                if (( ${#MODELS[@]} == 0 )); then message "No GGUF models available. Choose a models folder in Folders."; continue; fi
                selected=0
                for i in "${!MODELS[@]}"; do
                    if [[ "${MODELS[i]}" == "$MODEL" ]]; then selected="$i"; break; fi
                done
                if choice=$(UI_TITLE='Select model' ui --cancel-label Back --default-item "$selected" --menu 'Select a GGUF model' 22 80 14 "${MODEL_OPTIONS[@]}"); then MODEL="${MODELS[choice]}"; fi ;;
            context)
                selected=$CTX_SIZE
                case "$selected" in auto|4096|8192|16384|24576|32768|49152|65536|131072|262144) ;; *) selected=custom ;; esac
                if choice=$(UI_TITLE='Context size' ui --cancel-label Back --default-item "$selected" --menu 'Auto lets llama.cpp choose. Fixed values need model support and memory.\nCustom accepts smaller contexts too. 1K = 1024 tokens.' 22 80 11 \
                    auto 'Auto: native model and memory choices' custom "Custom: enter tokens (current: $(context_label))" \
                    4096 4K 8192 8K 16384 16K 24576 24K 32768 32K 49152 48K 65536 64K 131072 128K 262144 256K); then
                    if [[ "$choice" == custom ]]; then
                        if choice=$(UI_TITLE='Custom context size' ui --cancel-label Back --inputbox 'Enter auto or 1-2147483647 tokens.\n0 requests the full model context and can need much more memory.\nAuto leaves native llama.cpp environment settings in effect.' 12 80 "$CTX_SIZE"); then
                            if valid_context "$choice"; then CTX_SIZE=$choice; else message 'Enter auto or an integer from 0 to 2147483647.'; fi
                        fi
                    else CTX_SIZE=$choice; fi
                fi ;;
            reasoning)
                if choice=$(UI_TITLE=Reasoning ui --cancel-label Back --default-item "$REASONING" --menu 'Reasoning depends on model support' 12 64 3 auto Automatic off Off on On); then REASONING="$choice"; fi ;;
            generation) generation_menu ;;
            back) return 0 ;;
        esac
    done
}
