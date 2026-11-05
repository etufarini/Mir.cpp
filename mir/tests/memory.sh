#!/usr/bin/env bash
# Native planner fixtures and memory-budget edge cases; no model allocation.
set -euo pipefail
TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TEST_ROOT/lib/server.sh"
source "$TEST_ROOT/lib/memory.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/build/bin"
SERVER="$work/build/bin/llama-server"
MODEL="$work/model with spaces.gguf"
touch "$MODEL"
CTX_SIZE=4096 THREADS=auto DEVICE=auto GPU_LAYERS=auto PROMPT_PROCESSING=auto
export MEMORY_TEST_WORK="$work"
cat > "$SERVER" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
    --help) echo 'number of server slots (default: 1)' ;;
    --list-devices)
        echo '  Accelerator0: Test device (16384 MiB, 10240 MiB free)'
        echo '  Accelerator1: Unknown budget (0 MiB, 0 MiB free)' ;;
    *) exit 1 ;;
esac
MOCK
cat > "$work/build/bin/llama-fit-params" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == --help ]]; then echo '--fit-print'; exit 0; fi
printf '%s\0' "$@" >> "$MEMORY_TEST_WORK/args"
if [[ "${*: -1}" == off ]]; then
    [[ ! -f "$MEMORY_TEST_WORK/fit-failed" ]] || exit 1
    if [[ -f "$MEMORY_TEST_WORK/malformed" ]]; then echo 'unexpected output';
    else echo '-c 4096 -ngl -1'; fi
else
    echo 'Accelerator0 7000 1000 192'
    echo 'Host 512 256 256'
fi
MOCK
chmod +x "$SERVER" "$work/build/bin/llama-fit-params"
declare -a MEMORY_NAMES=() MEMORY_MIB=()
declare -A DEVICE_FREE=()
refresh_memory
[[ ${MEMORY_NAMES[*]} == 'Host Accelerator0' && ${MEMORY_MIB[*]} == '1024 8192' ]]
[[ ${DEVICE_FREE[Accelerator0]} == 10240 && ! -v 'DEVICE_FREE[Accelerator1]' ]]

[[ $(memory_gib -512) == -0.5 ]]
[[ $(memory_line estimate) == *'GPU 2.0'* ]]
for width in 16 24 32 40 72; do
    line=$(memory_line estimate "$width")
    (( ${#line} <= width ))
    [[ "$line" != *$'\n'* ]]
done
MEMORY_NAMES+=(OtherGPU ThirdGPU)
MEMORY_MIB+=(1024 1024)
DEVICE_FREE[OtherGPU]=2048 DEVICE_FREE[ThirdGPU]=2048
first=$(memory_line estimate 40)
[[ "$first" == *'+'* ]]
MEMORY_PAGE=2
second=$(memory_line estimate 40)
[[ "$second" != "$first" && "$second" == *GPU2* ]]
memory_controls estimate
MEMORY_PAGE=0
# Every pool remains reachable without a detail screen, even on narrow pages.
seen=''
for MEMORY_PAGE in 0 1 2 3; do seen+=$(memory_line estimate 40); done
[[ "$seen" == *'GPU1'* && "$seen" == *'GPU2'* && "$seen" == *'GPU3'* && "$seen" == *'RAM'* ]]
MEMORY_PAGE=0
MEMORY_NAMES=(Host Accelerator0); MEMORY_MIB=(1024 8192)
unset 'DEVICE_FREE[OtherGPU]' 'DEVICE_FREE[ThirdGPU]'
size=$(wc -c < "$work/args")
refresh_memory
[[ $(wc -c < "$work/args") == "$size" ]]
CTX_SIZE=8192
refresh_memory
(( $(wc -c < "$work/args") > size ))
DEVICE_FREE[Accelerator0]=8500
[[ $(memory_line estimate) == *'GPU 0.3'* ]]
DEVICE_FREE[Accelerator0]=8000

[[ $(memory_line estimate) == *'GPU -0.1'* ]]
[[ $(memory_line estimate) != *'Remaining: -'* ]]
unset 'DEVICE_FREE[Accelerator0]'
[[ $(memory_line estimate) == *'GPU N/A'* ]]

# The CPU override is shared by planning and launch without mutating profiles.
DEVICE=none GPU_LAYERS=all
build_model_args
[[ " ${MODEL_ARGS[*]} " == *' --gpu-layers 0 '* && "$GPU_LAYERS" == all ]]
touch "$work/malformed"
memory_estimate
[[ ${#MEMORY_NAMES[@]} == 0 && $(memory_line estimate) == *'Est. free: unavailable'* ]]
rm "$work/malformed"
touch "$work/fit-failed"
memory_estimate
[[ ${#MEMORY_NAMES[@]} == 2 ]]
DEVICE=auto GPU_LAYERS=auto
memory_estimate
[[ ${#MEMORY_NAMES[@]} == 0 ]]
DEVICE=none
rm "$work/build/bin/llama-fit-params"
memory_estimate
[[ ${#MEMORY_NAMES[@]} == 0 ]]
memory_available
[[ $(memory_line live) == *'GPU off'* ]]
printf 'PASS: native planner parsing, cache invalidation, margins, missing budgets, CPU override and live RAM\n'
