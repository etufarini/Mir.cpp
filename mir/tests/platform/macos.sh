#!/usr/bin/env bash
# Darwin fixtures run on either host; native socket checks run only on macOS.
set -euo pipefail
TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$TEST_ROOT" <<'PY'
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
native_path = os.environ['PATH']
sources = 'MIR_ROOT=$1; source "$MIR_ROOT/tests/helpers/core.sh"; load_test_core macos\n'
with tempfile.TemporaryDirectory(prefix='mir-macos-') as temporary:
    work = Path(temporary)
    commands = work / 'bin'
    commands.mkdir()
    def executable(path, text):
        path.write_text(text)
        path.chmod(0o755)
    executable(commands / 'uname', '#!/bin/sh\nprintf "Darwin\\n"\n')
    executable(commands / 'sysctl', """#!/bin/sh
[ "${TEST_SYSCTL_EXIT:-0}" = 0 ] || exit 1
[ "$*" = '-n hw.optional.arm64' ] || exit 1
printf '%s\\n' "${TEST_ARM64-1}"
""")
    snapshot = ('Mach Virtual Memory Statistics: (page size of 16384 bytes)\n'
                'Pages free: 65536.\nPages inactive: 655360.\nPages speculative: 65536.\n')
    executable(commands / 'vm_stat', """#!/bin/sh
printf '%s' "$TEST_VM_STAT"
exit "${TEST_VM_STAT_EXIT:-0}"
""")
    for tool in ('find', 'mv'):
        (commands / ('g' + tool)).symlink_to(shutil.which('g' + tool) or shutil.which(tool))
    executable(commands / 'netstat', '#!/bin/sh\nprintf "%s\\n" "$TEST_SOCKETS"\nexit "${TEST_NETSTAT_EXIT:-0}"\n')
    executable(commands / 'lsof', '#!/bin/sh\nprintf "%s\\n" "$TEST_PIDS"\nexit "${TEST_LSOF_EXIT:-0}"\n')
    executable(commands / 'open', '#!/bin/sh\nprintf "%s" "$1" > "$TEST_BROWSER"\n')
    executable(commands / 'curl', '#!/bin/sh\nexit 0\n')
    models = work / 'models with spaces'
    models.mkdir()
    model = models / 'model.gguf'
    model.touch()
    (models / 'linked.gguf').symlink_to(model)
    (models / '._resource.gguf').touch()
    package = work / 'package with spaces'
    (package / 'bin').mkdir(parents=True)
    executable(package / 'bin/llama-server', '''#!/usr/bin/env bash
case "$1" in
    --help)
        printf '%s\\n' '--model --port --device --gpu-layers --cache-type-k --cache-type-v'
        if [[ ${TEST_SERVER_AUTO:-0} == 1 ]]; then echo 'number of server slots (default: -1, -1 = auto)';
        else echo 'number of server slots (default: 1)'; fi ;;
    --list-devices) printf probe >> "$TEST_DEVICE_PROBES"; /bin/sleep "${TEST_DEVICE_DELAY:-0}"; printf 'Available devices:\\n  MTL0: Test GPU (8192 MiB, 4096 MiB free)\\n' ;;
    *) printf '%s\\0' "$@" > "$TEST_ARGS"; /bin/sleep 0.2 ;;
esac
''')
    executable(package / 'bin/llama-fit-params', '''#!/usr/bin/env bash
if [[ $1 == --help ]]; then
    printf '%s\\n' '--fit-print --parallel' '--cache-type-k TYPE' 'allowed values: q4_0' '--cache-type-v TYPE' 'allowed values: q4_0'
    exit 0
fi
if [[ ${*: -1} == off ]]; then echo '-c 512 -ngl -1';
else printf '%s\\n' 'MTL0 7000 1000 192' 'Host 512 256 256'; fi
''')
    env = {k:v for k,v in os.environ.items() if not k.startswith(('MIR_', 'LLAMA_', 'XDG_'))}
    env.update(PATH=str(commands) + ':' + native_path, HOME=str(work), XDG_CONFIG_HOME=str(work / 'config'),
               MIR_LLAMA_CPP_DIR=str(package), MIR_MODELS_DIR=str(models), TEST_SOCKETS='', TEST_PIDS='',
               TEST_VM_STAT=snapshot, TEST_BROWSER=str(work / 'browser'), TEST_ARGS=str(work / 'args'), TEST_DEVICE_PROBES=str(work / 'probes'))
    def check(code, overrides=None, success=True):
        result = subprocess.run(['bash', '-euo', 'pipefail', '-c', sources + code, 'test', str(root), str(model)],
                                env=env | (overrides or {}), capture_output=True, text=True, timeout=25)
        assert (result.returncode == 0) == success, (code, result.stdout, result.stderr)
        return result
    check('''initialize_config "$2"
validate_config
[[ "$SERVER" == "$MIR_LLAMA_CPP_DIR/bin/llama-server" ]]
scan_models
(( ${#MODELS[@]} == 2 ))
DEVICE=none GPU_LAYERS=all
prepare_server
[[ " ${ARGS[*]} " == *' --gpu-layers 0 '* ]]
''')
    # Source builds retain precedence when both supported layouts exist.
    (package / 'build/bin').mkdir(parents=True)
    (package / 'build/bin/llama-server').symlink_to(package / 'bin/llama-server')
    check('initialize_config "$2"; [[ "$SERVER" == "$MIR_LLAMA_CPP_DIR/build/bin/llama-server" ]]')
    (package / 'build/bin/llama-server').unlink()
    check('''initialize_config "$2"
server_devices
[[ ${DEVICE_NAMES[*]} == MTL0 ]]
size=$(wc -c < "$TEST_DEVICE_PROBES")
memory_available
[[ $RAM_AVAILABLE == 12288 && ${#DEVICE_FREE[@]} == 0 ]]
memory_estimate
[[ $(memory_line estimate) == 'Est. free GiB: RAM ~3.0' ]]
SERVER_PID=123
memory_available
(( $(wc -c < "$TEST_DEVICE_PROBES") == size ))
[[ $(memory_line live) == 'Free GiB: RAM ~12.0' ]]
memory_controls live
[[ ${#MEMORY_BUTTONS[@]} == 0 ]]
for width in 16 24 40 72; do
    for MEMORY_PAGE in 0 1 2 3; do
        line=$(memory_line estimate "$width")
        (( ${#line} <= width ))
        [[ $line == *'RAM ~3.0' ]]
    done
done
RAM_AVAILABLE=8192
[[ $(memory_line estimate) == 'Est. free GiB: RAM ~-1.0' ]]
MEMORY_NAMES=() MEMORY_MIB=()
[[ $(memory_line estimate) == 'Est. free GiB: RAM N/A' ]]
DEVICE=none
memory_available
(( $(wc -c < "$TEST_DEVICE_PROBES") == size ))
[[ $(memory_line live) == 'Free GiB: RAM ~12.0' ]]
''', {'TEST_DEVICE_DELAY':'2.2'})
    print('PASS: Darwin paths, cold discovery, shared-memory forecast, live available RAM, compact widths and no telemetry GPU probes')
    check('''initialize_config "$2"
build_model_args
before=$(printf '%s\\n' "${MODEL_ARGS[@]}")
refresh_memory
[[ ${#MEMORY_NAMES[@]} == 0 && $(memory_line estimate) == 'Est. free GiB: RAM N/A' ]]
[[ $(memory_line live) == 'Free GiB: RAM ~12.0' ]]
[[ $(printf '%s\\n' "${MODEL_ARGS[@]}") == "$before" ]]
''', {'TEST_SERVER_AUTO':'1'})
    print('PASS: automatic unified KV with an incompatible planner shows N/A and preserves live RAM and launch arguments')
    check('''initialize_config "$2"
memory_available
memory_estimate
[[ $(platform_memory_style) == system ]]
[[ $(memory_line estimate) == 'Est. free GiB: RAM N/A' ]]
[[ $(memory_line live) == 'Free GiB: RAM ~12.0' ]]
MEMORY_NAMES=(Host) MEMORY_MIB=(1024)
[[ $(memory_line estimate) == 'Est. free GiB: RAM ~11.0' ]]
''', {'TEST_ARM64':'0'})
    check('[[ $(platform_memory_style) == system ]]', {'TEST_SYSCTL_EXIT':'1'})
    for bad in ('', snapshot.replace('Pages inactive: 655360.\n', ''),
                snapshot + 'Pages free: 1.\n', snapshot.replace('16384', '0'),
                snapshot.replace('16384', '12345'), snapshot.replace('16384', '99999999'),
                snapshot.replace('655360.', '$(touch executed).'),
                snapshot.replace('655360.', '999999999999999999999.'),
                snapshot.replace('Pages speculative: 65536.', 'Pages speculative: invalid.')):
        check('platform_memory_snapshot; [[ -z "$RAM_AVAILABLE" ]]', {'TEST_VM_STAT':bad})
    assert not (work / 'executed').exists()
    check('platform_memory_snapshot; [[ -z "$RAM_AVAILABLE" ]]', {'TEST_VM_STAT_EXIT':'1'})
    check('''initialize_config "$2"
memory_available
[[ $RAM_AVAILABLE == 0 && $(memory_line live) == 'Free GiB: RAM ~0.0' ]]
''', {'TEST_VM_STAT':snapshot.replace('655360.', '0.').replace('65536.', '0.')})
    check('platform_memory_snapshot; [[ $RAM_AVAILABLE == 3072 ]]',
          {'TEST_VM_STAT':snapshot.replace('16384', '4096')})
    print('PASS: non-unified forecasts, 4/16 KiB pages, missing/malformed/duplicate counters, zero values and unavailable probes')

    busy = 'tcp4 0 0 127.0.0.1.9931 *.* LISTEN\ntcp6 0 0 ::1.9931 *.* LISTEN\n'
    check('PORT=9931; check_port; [[ -z "$LISTENERS" && ${#PIDS[@]} == 0 ]]',
          {'TEST_SOCKETS':'tcp4 0 0 127.0.0.1.9931 *.* ESTABLISHED\ntcp6 0 0 *.19931 *.* LISTEN'})
    check('''initialize_config "$2"
check_port
[[ "$PORT_STATUS" == *'IN USE'* && ${#PIDS[@]} == 0 ]]
if prepare_server; then exit 1; fi
[[ "$LAUNCH_ERROR" == *'IN USE'* ]]
''', {'TEST_SOCKETS':busy, 'TEST_LSOF_EXIT':'1'})
    check('PORT=9931; check_port; (( ${#PIDS[@]} == 1 )); [[ ${PIDS[0]} == 123 ]]',
          {'TEST_SOCKETS':busy, 'TEST_PIDS':'p123\nf10\np123'})
    check('PORT=9931; check_port', {'TEST_NETSTAT_EXIT':'1'}, success=False)
    print('PASS: Darwin IPv4/IPv6 listeners, exact ports, hidden owners, PID deduplication and fail-closed inspection')

    stop_code = '''PORT=9931
ps() { if [[ -f "$HOME/recycled" ]]; then echo new; else echo original; fi; }
sleep() { :; }
message() { printf '%s\\n' "$*" >> "$HOME/messages"; }
kill() { printf '%s\\n' "$*" >> "$HOME/signals"; return "${TEST_KILL_EXIT:-0}"; }
ui() {
    printf '%s\\n' "$*" >> "$HOME/prompts"
    if [[ ${TEST_RECYCLE:-0} == 1 ]]; then touch "$HOME/recycled"; fi
    if [[ $* == *SIGKILL* ]]; then return "${TEST_FORCE:-1}"; fi
    return "${TEST_CONFIRM:-0}"
}
stop_listener
'''
    def stop(overrides):
        for name in ('recycled', 'signals', 'messages', 'prompts'):
            (work / name).unlink(missing_ok=True)
        check(stop_code, {'TEST_SOCKETS':busy, 'TEST_PIDS':'p123'} | overrides)
        return (work / 'signals').read_text() if (work / 'signals').exists() else ''
    assert not stop({'TEST_CONFIRM':'1'})
    assert stop({}) == '-TERM 123\n'
    assert stop({'TEST_FORCE':'0'}) == '-TERM 123\n-KILL 123\n'
    assert not stop({'TEST_RECYCLE':'1'})
    stop({'TEST_KILL_EXIT':'1'})
    assert 'Cannot stop PID 123' in (work / 'messages').read_text()
    print('PASS: canceled shutdown, SIGTERM first, separate SIGKILL approval, recycled PIDs and permission failures')

    check('''initialize_config "$2"
prepare_server
run_server
''')
    assert (work / 'browser').read_text() == 'http://127.0.0.1:9931'
    assert b'--model\0' in (work / 'args').read_bytes()
    # Migration keeps the original and never merges with existing settings.
    legacy = work / 'migration/llama-launcher'
    legacy.mkdir(parents=True)
    (legacy / 'paths.conf').write_text('llama_dir=old\nmodels_dir=old\n')
    check('''CONFIG_DIR="$HOME/migration/mir.cpp"
migrate_config
[[ -f "$CONFIG_DIR/paths.conf" && -f "$HOME/migration/llama-launcher/paths.conf" ]]
printf unchanged > "$CONFIG_DIR/paths.conf"
migrate_config
[[ $(cat "$CONFIG_DIR/paths.conf") == unchanged ]]
''')
    print('PASS: macOS browser opening and atomic GNU-move migration without overwriting settings')

PY
