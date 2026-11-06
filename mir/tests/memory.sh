#!/usr/bin/env bash
# Native planner fixtures and memory-budget edge cases; no model allocation.
set -euo pipefail
TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MIR_ROOT=$TEST_ROOT
source "$MIR_ROOT/tests/helpers/core.sh"
load_test_core fake
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/build/bin"
SERVER="$work/build/bin/llama-server"
MODEL="$work/model with spaces.gguf"
touch "$MODEL"
CTX_SIZE=4096 THREADS=auto DEVICE=auto GPU_LAYERS=auto PROMPT_PROCESSING=auto
CACHE_TYPE_K=q4_0 CACHE_TYPE_V=q4_0
export MEMORY_TEST_WORK="$work"
cat > "$SERVER" <<'MOCK'
#!/usr/bin/env bash
case "$1" in
    --help) printf '%s\n' "${MEMORY_TEST_SERVER_HELP:-number of server slots (default: 1)}" ;;
    --list-devices)
        echo '  Accelerator0: Test device (16384 MiB, 10240 MiB free)'
        echo '  Accelerator1: Unknown budget (0 MiB, 0 MiB free)' ;;
    *) exit 1 ;;
esac
MOCK
cat > "$work/build/bin/llama-fit-params" <<'MOCK'
#!/usr/bin/env bash
if [[ "$1" == --help ]]; then
    printf '%s\n' "${MEMORY_TEST_HELP:---fit-print --parallel}" "${MEMORY_TEST_CACHE_HELP:---cache-type-k TYPE
    allowed values: f16, q8_0, q4_0
--cache-type-v TYPE
    allowed values: f16, q8_0, q4_0}"
    exit 0
fi
printf '%s\0' "$@" >> "$MEMORY_TEST_WORK/args"
if [[ "${*: -1}" == off ]]; then
    [[ ! -f "$MEMORY_TEST_WORK/fit-failed" ]] || exit 1
    if [[ -f "$MEMORY_TEST_WORK/malformed" ]]; then echo 'unexpected output';
    else printf '%s\n' "${MEMORY_TEST_FIT--c 4096 -ngl -1}"; fi
else
    echo 'Accelerator0 7000 1000 192'
    echo 'Host 512 256 256'
    if [[ -f "$MEMORY_TEST_WORK/duplicates" ]]; then echo 'Host 1 2 3'; fi
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
for cache_setting in CACHE_TYPE_K CACHE_TYPE_V; do
    size=$(wc -c < "$work/args")
    printf -v "$cache_setting" '%s' q8_0
    refresh_memory
    (( $(wc -c < "$work/args") > size ))
done
python3 - "$work/args" <<'PYARGS'
import sys
from pathlib import Path
args = Path(sys.argv[1]).read_bytes().split(b'\0')[:-1]
assert args.count(b'--cache-type-k') == args.count(b'--cache-type-v') == args.count(b'--fit-print')
last = len(args) - 1 - args[::-1].index(b'--cache-type-k')
assert args[last:last+4] == [b'--cache-type-k', b'q8_0', b'--cache-type-v', b'q8_0']
PYARGS
size=$(wc -c < "$work/args")
export LLAMA_ARG_FLASH_ATTN=on
refresh_memory
(( $(wc -c < "$work/args") > size ))
unset LLAMA_ARG_FLASH_ATTN
export MEMORY_TEST_CACHE_HELP='--cache-type-k TYPE
allowed values: q4_0'
MEMORY_KEY=''
refresh_memory
[[ ${#MEMORY_NAMES[@]} == 0 && $(memory_line live) == *'Free GiB: RAM'* ]]
unset MEMORY_TEST_CACHE_HELP
CACHE_TYPE_K=q4_0 CACHE_TYPE_V=q4_0 MEMORY_KEY=''
refresh_memory
[[ ${#MEMORY_NAMES[@]} == 2 ]]
printf 'PASS: matching K/V planner arguments, independent cache changes, native Flash Attention and unsupported planner fallback\n'
DEVICE_FREE[Accelerator0]=8500
[[ $(memory_line estimate) == *'GPU 0.3'* ]]
DEVICE_FREE[Accelerator0]=8000

[[ $(memory_line estimate) == *'GPU -0.1'* ]]
[[ $(memory_line estimate) != *'Remaining: -'* ]]
unset 'DEVICE_FREE[Accelerator0]'
[[ $(memory_line estimate) == *'GPU N/A'* ]]

# Duplicate pools must not be summed into a plausible allocation estimate.
touch "$work/duplicates"
memory_estimate
[[ ${#MEMORY_NAMES[@]} == 0 ]]
rm "$work/duplicates"
memory_estimate
[[ ${#MEMORY_NAMES[@]} == 2 ]]

# Preserve every fitted pair and strip only the tensor override's outer quotes.
export MEMORY_TEST_FIT='-c 4096 -ngl -1 -ts 1,2 -ot "blk.*=CPU"'
: > "$work/args"
memory_estimate
[[ ${#MEMORY_NAMES[@]} == 2 ]]
python3 - "$work/args" <<'PYARGS'
import sys
from pathlib import Path
args = Path(sys.argv[1]).read_bytes().split(b'\0')[:-1]
assert args[-10:] == [b'-c', b'4096', b'-ngl', b'-1', b'-ts', b'1,2',
                      b'-ot', b'blk.*=CPU', b'--fit-print', b'on'], args
PYARGS
# Invalid fitting output must never reach the allocation-measurement call.
for MEMORY_TEST_FIT in '' '-c' '-c 4096 -ngl' '-c bad' '-ngl all' '-ts 1,,2' '-ot ""' '-ot "bad"quote' '-unknown 1' $'-c 4096\n-ngl -1'; do
    : > "$work/args"
    memory_estimate
    [[ ${#MEMORY_NAMES[@]} == 0 ]]
    mapfile -d '' -t planner_args < "$work/args"
    [[ ${planner_args[-1]} == off ]]
done
unset MEMORY_TEST_FIT
printf 'PASS: fitted argument pairs, tensor override quotes and rejected malformed planner output\n'

# A planner without unified KV support must not estimate an automatic server.
export MEMORY_TEST_SERVER_HELP='number of server slots (default: -1, -1 = auto)'
CAPABILITIES_SERVER='' MEMORY_KEY=''
size=$(wc -c < "$work/args")
refresh_memory
[[ ${#MEMORY_NAMES[@]} == 0 ]]
(( $(wc -c < "$work/args") == size ))
memory_available
[[ $(memory_line live) == *'Free GiB: RAM 16.0'* ]]
# Native auto must follow the same path even when supplied through the environment.
export LLAMA_ARG_N_PARALLEL=-1
refresh_memory
[[ ${#MEMORY_NAMES[@]} == 0 ]]
# A helper capable of matching the layout receives explicit effective settings.
export MEMORY_TEST_HELP='--fit-print --parallel --kv-unified --no-kv-unified'
MEMORY_KEY=''
refresh_memory
[[ ${#MEMORY_NAMES[@]} == 2 ]]
python3 - "$work/args" <<'PYARGS'
import sys
from pathlib import Path
args = Path(sys.argv[1]).read_bytes().split(b'\0')
assert [b'--parallel', b'4'] == args[args.index(b'--parallel'):args.index(b'--parallel')+2]
assert b'--kv-unified' in args
PYARGS
# A compatible helper also receives an explicit disabled KV layout.
export LLAMA_ARG_N_PARALLEL=2 LLAMA_ARG_KV_UNIFIED=off
: > "$work/args"
refresh_memory
[[ ${#MEMORY_NAMES[@]} == 2 ]]
python3 - "$work/args" <<'PYARGS'
import sys
from pathlib import Path
args = Path(sys.argv[1]).read_bytes().split(b'\0')
assert [b'--parallel', b'2'] == args[args.index(b'--parallel'):args.index(b'--parallel')+2]
assert b'--no-kv-unified' in args and b'--kv-unified' not in args
PYARGS
# A positive slot override does not enable unified KV by default.
export MEMORY_TEST_HELP='--fit-print --parallel' LLAMA_ARG_N_PARALLEL=2
refresh_memory
[[ ${#MEMORY_NAMES[@]} == 2 ]]
export LLAMA_ARG_KV_UNIFIED=on
refresh_memory
[[ ${#MEMORY_NAMES[@]} == 0 ]]
# Native negative aliases win even when explicitly empty; never change the env.
export LLAMA_ARG_NO_KV_UNIFIED=''
refresh_memory
[[ ${#MEMORY_NAMES[@]} == 2 && $LLAMA_ARG_KV_UNIFIED == on && -v LLAMA_ARG_NO_KV_UNIFIED ]]
# shellcheck disable=SC2016 # Deliberately literal input must never execute.
for LLAMA_ARG_N_PARALLEL in '' 0 '$(touch "$MEMORY_TEST_WORK/unsafe")' 999999999999999999; do
    refresh_memory
    [[ ${#MEMORY_NAMES[@]} == 0 ]]
done
[[ ! -e "$work/unsafe" ]]
unset LLAMA_ARG_N_PARALLEL LLAMA_ARG_KV_UNIFIED LLAMA_ARG_NO_KV_UNIFIED
# Auto still forces unified KV even when its environment toggle says off.
export LLAMA_ARG_KV_UNIFIED=off
refresh_memory
[[ ${#MEMORY_NAMES[@]} == 0 ]]
unset LLAMA_ARG_KV_UNIFIED MEMORY_TEST_SERVER_HELP MEMORY_TEST_HELP
CAPABILITIES_SERVER='' MEMORY_KEY=''
printf 'PASS: planner/server layout compatibility, auto slots, native KV controls, cache invalidation and independent live telemetry\n'

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
