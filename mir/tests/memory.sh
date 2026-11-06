#!/usr/bin/env bash
# Live memory measurements and compact pagination; no model allocation.
set -euo pipefail
MIR_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$MIR_ROOT/tests/helpers/core.sh"
load_test_core fake
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
SERVER="$work/llama-server"
DEVICE=auto MEMORY_PAGE=0
cat > "$SERVER" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == --list-devices ]] || exit 1
printf '%s\n' "${MEMORY_TEST_DEVICES:-Available devices:
  Accelerator0: First GPU (16384 MiB, 10240 MiB free)
  Accelerator1: Unknown budget (0 MiB, 0 MiB free)
  BLAS: CPU accelerator (0 MiB, 0 MiB free)}"
exit "${MEMORY_TEST_EXIT:-0}"
MOCK
chmod +x "$SERVER"
memory_available
[[ $RAM_AVAILABLE == 16384 && ${GPU_DEVICE_NAMES[*]} == Accelerator0 ]]
[[ ${DEVICE_FREE[Accelerator0]} == 10240 && ${#DEVICE_FREE[@]} == 1 ]]
[[ $(memory_line) == 'Free GiB: RAM 16.0 | GPU 10.0' ]]
[[ $(memory_gib 512) == 0.5 ]]
# Stable discovery order also identifies the pools across pages.
export MEMORY_TEST_DEVICES='Available devices:
  First: First GPU (16384 MiB, 10240 MiB free)
  Second: Second GPU (8192 MiB, 2048 MiB free)
  Third: Third GPU (8192 MiB, 4096 MiB free)'
memory_available
[[ ${GPU_DEVICE_NAMES[*]} == 'First Second Third' ]]
for width in 16 24 32 40 72; do
    line=$(memory_line "$width")
    (( ${#line} <= width ))
    [[ "$line" != *$'\n'* ]]
done
[[ $(memory_line 40) == *'+'* ]]
seen=''
for MEMORY_PAGE in 0 1 2 3; do seen+=$(memory_line 40); done
[[ "$seen" == *GPU1* && "$seen" == *GPU2* && "$seen" == *GPU3* && "$seen" == *RAM* ]]
MEMORY_PAGE=0
memory_width() { printf 40; }
memory_controls
[[ ${MEMORY_BUTTONS[*]} == '--extra-button --extra-label Next memory' ]]
# Duplicate, malformed, unavailable and zero-budget reports are not extra GPUs.
export MEMORY_TEST_DEVICES='Available devices:
  First: GPU (16384 MiB, 10240 MiB free)
  First: Duplicate (16384 MiB, 10240 MiB free)
  Second: Invalid (8192 MiB, 9000 MiB free)
  Third: Invalid (99999999999999999999 MiB, 0 MiB free)
  Fourth: Missing memory metadata
  bad[name]: Invalid device tag (8192 MiB, 4096 MiB free)
  BLAS: CPU accelerator (0 MiB, 0 MiB free)'
memory_available
[[ ${GPU_DEVICE_NAMES[*]} == First && ${#DEVICE_FREE[@]} == 1 ]]
export MEMORY_TEST_EXIT=1
memory_available
[[ ${#GPU_DEVICE_NAMES[@]} == 0 && ${#DEVICE_FREE[@]} == 0 ]]
[[ $(memory_line) == *'GPU N/A'* ]]
DEVICE=none
memory_available
[[ $(memory_line) == 'Free GiB: RAM 16.0 | GPU off' ]]
# Missing memory never blocks telemetry or server controls.
platform_memory_snapshot() { RAM_AVAILABLE=''; }
memory_available
[[ $(memory_line) == 'Free GiB: RAM N/A | GPU off' ]]
printf 'PASS: live RAM/device readings, stable pool order, pagination, malformed/probe failures and CPU-only telemetry\n'
