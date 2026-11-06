#!/usr/bin/env bash

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
        max_tokens) hint='Integer from 0 to 2147483647, or -1 for no fixed limit.\n0 evaluates input only. A short limit can cut off an answer.' ;;
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
        action=$(menu --default-item "$action" --menu 'Adjust server defaults for generated text.\nModel recommendations take priority over generic presets.' 22 80 8 "${options[@]}" back Back) || return 0
        [[ "$action" != back ]] || return 0
        edit_generation_value "$action"
    done
}

generation_menu() {
    local action=preset choice UI_TITLE=Generation
    while true; do
        action=$(menu --default-item "$action" --menu 'Presets change sampling only; seed and output limit stay separate.\nBrowser chat settings can override these server defaults.\nUse server defaults in the chat to follow this selection.' 20 80 5 \
            preset "Preset                 $(display_value "$(generation_preset)")" \
            sampling 'Sampling parameters    View or customize values' \
            seed "Seed                   $(display_value "${GENERATION[seed]}" Default)" \
            max_tokens "Maximum output tokens  $(display_value "${GENERATION[max_tokens]}" Default)" back Back) || return 0
        case "$action" in
            preset)
                if choice=$(UI_TITLE='Generation preset' menu --default-item "$(generation_preset)" --menu 'Starting points to test, not guarantees of quality.\nNo preset changes context or hardware settings.' 18 80 5 \
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
        if (( ${#DEVICE_NAMES[@]} > 1 )); then options+=(multiple 'Select multiple devices'); fi
    else
        message 'Could not list devices within the time limit, or probing is unavailable.\nCheck the llama.cpp folder and drivers. Auto and CPU only remain available.'
    fi
    local selected=$DEVICE
    if [[ "$selected" == *,* ]]; then selected=multiple; fi
    if choice=$(menu --default-item "$selected" --menu 'Auto lets llama.cpp choose, including multiple GPUs.\nChoose a device or select several explicitly.' 19 80 10 "${options[@]}"); then
        if [[ "$choice" == multiple ]]; then select_multiple_devices; else DEVICE="$choice"; fi
    fi
}

select_multiple_devices() {
    local name i state choice
    local -a names options=()
    local -A selected_names=()
    IFS=, read -r -a names <<< "$DEVICE"
    names+=("${DEVICE_NAMES[@]}")
    # Keep selected devices in their saved order: ratios follow this order.
    for name in "${names[@]}"; do
        [[ ! -v "selected_names[$name]" ]] || continue
        selected_names[$name]=1
        for i in "${!DEVICE_NAMES[@]}"; do
            [[ "$name" == "${DEVICE_NAMES[i]}" ]] || continue
            state=off
            if [[ ",$DEVICE," == *",$name,"* ]]; then state=on; fi
            options+=("$name" "$(compact_text "$name: ${DEVICE_DESCRIPTIONS[i]}" 60)" "$state")
            break
        done
    done
    if choice=$(UI_TITLE='Select devices' ui --ok-label Apply --cancel-label Back --separate-output --checklist \
        'Space selects a device; Enter applies. Select at least one.\nProportions and memory margins follow the listed device order.' 20 80 10 "${options[@]}"); then
        choice=${choice//$'\n'/,}
        if [[ -n "$choice" ]] && valid_device "$choice"; then DEVICE=$choice;
        else message 'Select at least one device. The previous selection was kept.'; fi
    fi
}

gpu_memory_menu() {
    local action=margin choice mode flag count=0 UI_TITLE='GPU memory'
    local -a options modes
    if [[ "$DEVICE" == none ]]; then
        message 'GPU memory settings are inactive with CPU only.\nPrevious values are kept for GPU use.'
        return 0
    fi
    server_capabilities
    if [[ "$DEVICE" == auto ]]; then
        if server_devices; then count=${#DEVICE_NAMES[@]}; fi
    else
        IFS=, read -r -a modes <<< "$DEVICE"
        count=${#modes[@]}
    fi
    while true; do
        options=(margin "Memory margin (MiB)  $(compact_text "$(display_value "$FIT_TARGET")" 45)")
        if (( count > 1 )); then
            options+=(mode "Split mode           $(display_value "$SPLIT_MODE")" \
                proportions "GPU proportions      $(compact_text "$(display_value "$TENSOR_SPLIT")" 45)")
        fi
        action=$(menu --default-item "$action" --menu "Devices: $(compact_text "$(display_value "$DEVICE")" 58)\nAuto preserves native llama.cpp settings.\nMemory margin applies to automatic fitting, not total process RAM." 18 80 4 "${options[@]}" back Back) || return 0
        case "$action" in
            mode)
                modes=(auto 'Auto: native default')
                while IFS= read -r mode; do
                    case "$mode" in
                        none) modes+=(none 'Single GPU: use one GPU only') ;;
                        layer) modes+=(layer 'Layer: distribute layers and KV cache') ;;
                        row) modes+=(row 'Row: parallel distribution of weight rows') ;;
                        tensor) modes+=(tensor 'Tensor: parallel weights and KV (experimental)') ;;
                    esac
                done < <(split_modes)
                if choice=$(UI_TITLE='GPU split mode' menu --default-item "$SPLIT_MODE" --menu \
                    'Only advertised modes are offered; Auto omits the launcher option.\nModel/backend restrictions apply. No mode guarantees better speed.' 17 80 6 "${modes[@]}" back Back); then
                    if [[ "$choice" != back ]]; then SPLIT_MODE=$choice; fi
                fi ;;
            proportions|margin)
                if [[ "$action" == proportions ]]; then
                    mode=TENSOR_SPLIT
                    choice='Relative proportions in device order, e.g. 2,1 (not GiB).\nUse auto, or nonnegative numbers with at least one positive value.\nActual placement also depends on split mode and native fitting.'
                else
                    mode=FIT_TARGET
                    choice='Free-memory target for automatic fitting, in MiB.\nUse auto, one integer for all GPUs, or one per GPU in device order.\nThis does not limit total memory or guarantee an allocation succeeds.'
                fi
                flag=${mode,,}; flag=${flag//_/-}
                if choice=$(UI_TITLE='GPU memory setting' ui --cancel-label Back --inputbox "$choice" 14 80 "${!mode}"); then
                    if [[ "$choice" != auto ]] && ! supports_option "--$flag"; then
                        message "This llama-server does not advertise --$flag. Choose auto or select another build. Current values were kept."
                    elif { [[ "$mode" == TENSOR_SPLIT ]] && valid_gpu_list ratios "$choice"; } || { [[ "$mode" == FIT_TARGET ]] && valid_gpu_list margins "$choice"; }; then
                        printf -v "$mode" '%s' "$choice"
                    else message 'Invalid value. Use auto or a comma-separated list of valid values.\nProportions must include a positive value; margins are whole MiB.'; fi
                fi ;;
            back) return 0 ;;
        esac
    done
}

select_cache_type() {
    local component=$1 current=$2 choice type types selected UI_TITLE="KV Cache: $1"
    local -a primary=() other=()
    [[ -x "$SERVER" && -f "$SERVER" ]] || { message 'Select a llama.cpp folder before choosing cache types.'; return 0; }
    server_capabilities
    types=$(cache_types "$component")
    [[ -n "$types" ]] || { message 'Could not read supported cache types from llama-server help.\nCheck the selected build in Folders. Current values were kept.'; return 0; }
    for type in q4_0 q8_0 f16; do
        listed_value "$type" "$types" || continue
        case "$type" in
            q4_0) primary+=("$type" 'Q4_0   Lower memory use (Mir.cpp default)') ;;
            q8_0) primary+=("$type" 'Q8_0   Less aggressive quantization') ;;
            f16) primary+=("$type" 'F16    Unquantized, higher memory use') ;;
        esac
    done
    while IFS= read -r type; do
        case "$type" in q4_0|q8_0|f16) ;; *) other+=("$type" "${type^^}") ;; esac
    done <<< "$types"
    if (( ${#other[@]} > 0 )); then primary+=(other 'Other formats'); fi
    selected=$current
    case "$current" in q4_0|q8_0|f16) ;; *) selected=other ;; esac
    if choice=$(menu --default-item "$selected" --menu "Cache $component: current ${current^^}. Available types come from this build.\nLower precision saves memory and may affect quality.\nModel and backend compatibility is checked by llama.cpp." 18 80 5 "${primary[@]}" back Back); then
        if [[ "$choice" == other ]]; then
            choice=$(menu --default-item "$current" --menu "Other cache $component formats advertised by this llama-server.\nSupport during inference depends on the model and backend." 20 80 10 "${other[@]}" back Back) || return 0
        fi
        [[ "$choice" != back ]] || return 0
        listed_value "$choice" "$types" || return 0
        printf -v "CACHE_TYPE_$component" '%s' "$choice"
    fi
}

cache_menu() {
    local action=k UI_TITLE='KV Cache'
    while true; do
        action=$(menu --default-item "$action" --menu 'K stores keys; V stores values. Both default to Q4_0.\nQuantized V requires Flash Attention. Mixed types may be unsupported\nor slower; use matching types when unsure.' 17 80 3 \
            k "K (keys)       ${CACHE_TYPE_K^^}" v "V (values)     ${CACHE_TYPE_V^^}" back Back) || return 0
        case "$action" in
            k) select_cache_type K "$CACHE_TYPE_K" ;;
            v) select_cache_type V "$CACHE_TYPE_V" ;;
            back) return 0 ;;
        esac
    done
}

performance_menu() {
    local action=device choice layers_label UI_TITLE=Performance
    while true; do
        layers_label=$(display_value "$GPU_LAYERS")
        if [[ "$DEVICE" == none ]]; then layers_label='Ignored (CPU only)'; fi
        action=$(menu --default-item "$action" --menu 'Auto and Default use llama.cpp defaults.\nFlash Attention stays automatic.' 19 80 6 \
            device "Device             $(compact_text "$(display_value "$DEVICE")" 53)" threads "CPU threads        $(display_value "$THREADS")" \
            layers "GPU layers         $layers_label" prompt "Prompt processing  $(display_value "$PROMPT_PROCESSING" Default)" \
            gpu 'GPU memory         Advanced distribution and margin' back 'Back') || return 0
        case "$action" in
            device) select_device ;;
            gpu) gpu_memory_menu ;;
            threads)
                if choice=$(UI_TITLE='CPU threads' ui --cancel-label Back --inputbox 'CPU threads: auto or a positive integer.\nMore threads are not always faster.' 11 76 "$THREADS"); then
                    if valid_threads "$choice"; then THREADS="$choice"; else message 'Enter auto or a positive integer up to 2147483647.'; fi
                fi ;;
            layers)
                if choice=$(UI_TITLE='GPU layers' ui --cancel-label Back --inputbox 'GPU layers: auto, all or a nonnegative integer.\nAuto adapts to available device memory. All may exceed it.' 11 76 "$GPU_LAYERS"); then
                    if valid_layers "$choice"; then GPU_LAYERS="$choice"; else message 'Enter auto, all or an integer from 0 to 2147483647.'; fi
                fi ;;
            prompt)
                if choice=$(UI_TITLE='Prompt processing' menu --default-item "$PROMPT_PROCESSING" --menu 'Tune processing of input text. Generation speed may not improve.\nLarge batch needs more memory; use Default if unsure.' 14 80 3 \
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
        action=$(menu --default-item "$action" --menu 'Context includes input and output. Larger contexts need more memory.\nContext size and cache types depend on model and backend support.' 18 80 5 \
            model "Model         $(compact_text "${MODEL##*/}")" context "Context       $(context_label)" \
            cache "KV Cache      K ${CACHE_TYPE_K^^} / V ${CACHE_TYPE_V^^}" \
            generation "Generation    $(display_value "$(generation_preset)")" back Back) || return 0
        case "$action" in
            model)
                if (( ${#MODELS[@]} == 0 )); then message "No GGUF models available. Choose a models folder in Folders."; continue; fi
                selected=0
                for i in "${!MODELS[@]}"; do
                    if [[ "${MODELS[i]}" == "$MODEL" ]]; then selected="$i"; break; fi
                done
                if choice=$(UI_TITLE='Select model' menu --default-item "$selected" --menu 'Select a GGUF model' 22 80 14 "${MODEL_OPTIONS[@]}"); then MODEL="${MODELS[choice]}"; fi ;;
            context)
                selected=$CTX_SIZE
                case "$selected" in auto|4096|8192|16384|24576|32768|49152|65536|131072|262144) ;; *) selected=custom ;; esac
                if choice=$(UI_TITLE='Context size' menu --default-item "$selected" --menu 'Auto lets llama.cpp choose. Fixed values need model support and memory.\nCustom accepts smaller contexts too. 1K = 1024 tokens.' 22 80 11 \
                    auto 'Auto: native model and memory choices' custom "Custom: enter tokens (current: $(context_label))" \
                    4096 4K 8192 8K 16384 16K 24576 24K 32768 32K 49152 48K 65536 64K 131072 128K 262144 256K); then
                    if [[ "$choice" == custom ]]; then
                        if choice=$(UI_TITLE='Custom context size' ui --cancel-label Back --inputbox 'Enter auto or 1-2147483647 tokens.\n0 requests the full model context and can need much more memory.\nAuto leaves native llama.cpp environment settings in effect.' 12 80 "$CTX_SIZE"); then
                            if valid_context "$choice"; then CTX_SIZE=$choice; else message 'Enter auto or an integer from 0 to 2147483647.'; fi
                        fi
                    else CTX_SIZE=$choice; fi
                fi ;;
            cache) cache_menu ;;
            generation) generation_menu ;;
            back) return 0 ;;
        esac
    done
}
