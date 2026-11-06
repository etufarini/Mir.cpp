#!/usr/bin/env bash
# Portable defaults and simulated backend/model edge cases; no real inference.
set -euo pipefail
TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$TEST_ROOT" <<'PY'
import json
import os
from pathlib import Path
import pty
import shutil
import struct
import subprocess
import sys
import tempfile
import time

root = Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix='mir-portability-') as temporary:
    work = Path(temporary)
    commands = work / 'bin'
    commands.mkdir()
    # Exercise the Linux branch even on macOS; native Darwin checks are separate.
    (commands / 'uname').write_text('#!/bin/sh\nprintf "Linux\\n"\n')
    (commands / 'uname').chmod(0o755)
    for tool in ('mv', 'find'):
        gnu = shutil.which('g' + tool)
        if gnu:
            (commands / tool).symlink_to(gnu)
    models = work / 'models'
    models.mkdir()
    model = models / 'model.gguf'
    model.touch()
    server_dir = work / 'llama.cpp'
    (server_dir / 'build/bin').mkdir(parents=True)

    def executable(path, contents):
        path.write_text(contents)
        path.chmod(0o755)

    help_text = '''--model FNAME        model file
--port PORT          TCP port
--host HOST          bind address
-dev, --device DEV   devices
--ctx-size N         context
--threads N          threads
--gpu-layers N       layers, auto or all
--batch-size N       batch
--ubatch-size N      ubatch
-sm, --split-mode {none,layer,row,tensor}  GPU distribution
-ts, --tensor-split N0,N1,...  relative proportions
-fitt, --fit-target MiB0,MiB1,...  fitting margin
-ctk, --cache-type-k TYPE  KV cache data type for K
    allowed values: f32, f16, bf16, q8_0, q4_0, q4_1, iq4_nl, q5_0, q5_1
-ctv, --cache-type-v TYPE  KV cache data type for V
    allowed values: f32, f16, bf16, q8_0, q4_0, q4_1, iq4_nl, q5_0, q5_1
--alias STRING       alias
--lora-scaled FNAME SCALE   adapter
--no-webui           Disable the Web UI
number of server slots (default: 1)'''
    executable(server_dir / 'build/bin/llama-server', '''#!/usr/bin/env bash
if [[ ${1:-} == --help ]]; then printf '%s\\n' "$TEST_HELP"; exit "${TEST_HELP_EXIT:-0}"; fi
if [[ ${1:-} == --list-devices ]]; then printf '%s\\n' "$TEST_DEVICES"; exit "${TEST_DEVICE_EXIT:-0}"; fi
printf '%s\\0' "$@" > "$TEST_ARGS"
if [[ ${TEST_LIVE:-0} == 1 ]]; then
    trap 'exit 0' TERM
    while true; do /bin/sleep 0.02; done
fi
''')
    executable(commands / 'ss', '''#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$TEST_PORTS"
if [[ -n ${TEST_BUSY_PORT:-} && $* == *":$TEST_BUSY_PORT" ]]; then
    printf 'LISTEN 0 128 0.0.0.0:%s 0.0.0.0:*\\n' "$TEST_BUSY_PORT"
fi
''')
    executable(commands / 'curl', '#!/usr/bin/env bash\nprintf "%s\\0" "$@" > "$TEST_CURL"\n')
    executable(commands / 'xdg-open', '#!/usr/bin/env bash\nprintf "%s" "$1" > "$TEST_BROWSER"\n')
    executable(commands / 'sleep', '#!/usr/bin/env bash\n/bin/sleep 0.01\n')
    executable(commands / 'dialog', '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
path = Path(os.environ['TEST_QUEUE'])
queue = json.loads(path.read_text())
status, value = queue.pop(0)
path.write_text(json.dumps(queue))
sys.stdout.write(value)
sys.exit(status)
''')
    env = {k:v for k,v in os.environ.items() if not k.startswith(('LLAMA_', 'MIR_'))}
    env.update(PATH=str(commands) + ':' + env['PATH'], XDG_CONFIG_HOME=str(work / 'config'),
               MIR_LLAMA_CPP_DIR=str(server_dir), MIR_MODELS_DIR=str(models),
               TEST_HELP=help_text, TEST_DEVICES='Available devices:\n  Vulkan0: First GPU (16384 MiB, 8192 MiB free)\n  Vulkan1: Second GPU (8192 MiB, 4096 MiB free)',
               TEST_ARGS=str(work / 'args'), TEST_PORTS=str(work / 'ports'),
               TEST_CURL=str(work / 'curl'), TEST_BROWSER=str(work / 'browser'),
               TEST_QUEUE=str(work / 'queue'))
    sources = 'MIR_ROOT=$1; source "$MIR_ROOT/tests/helpers/core.sh"; load_test_core fake\n'

    def check(code, overrides=None):
        result = subprocess.run(['bash', '-euo', 'pipefail', '-c', sources + code,
                                 'test', str(root), str(model)], env=env | (overrides or {}),
                                capture_output=True, text=True, timeout=12)
        assert result.returncode == 0, (code, result.stdout, result.stderr)

    def launch(overrides=None, arguments=None):
        (work / 'args').unlink(missing_ok=True)
        (work / 'ports').write_text('')
        result = subprocess.run(['bash', str(root / 'mir.sh'), str(model)] + (arguments or []),
                                env=env | (overrides or {}), capture_output=True, text=True, timeout=10)
        data = (work / 'args').read_bytes().split(b'\0')[:-1] if (work / 'args').exists() else []
        return result, [s.decode() for s in data]

    for context in ['auto', '0', '256', '1024', '2147483647']:
        result, args = launch({'MIR_CTX_SIZE':context})
        assert result.returncode == 0, result.stderr
        if context == 'auto':
            assert '--ctx-size' not in args
        else:
            assert args[args.index('--ctx-size')+1] == context
    result, args = launch({'LLAMA_ARG_CTX_SIZE':'2048'})
    assert result.returncode == 0 and '--ctx-size' not in args
    for context in ['', '-1', '01', '2147483648', '999999999999999999999999', '1+1']:
        result, args = launch({'MIR_CTX_SIZE':context})
        assert result.returncode != 0 and not args, context
    check('''initialize_config "$2"
for CTX_SIZE in auto 0 1024; do
    DEVICE=Vulkan0,Vulkan1
    write_profile "$PROFILES_DIR/Multi.conf"
    saved=$(profile_data)
    CTX_SIZE=4096 DEVICE=none
    load_profile "$PROFILES_DIR/Multi.conf"
    [[ $(profile_data) == "$saved" && $(profile_status) == Multi ]]
done
DEVICE=Vulkan0,Vulkan1,
if valid_device "$DEVICE"; then exit 1; fi
''')
    (work / 'queue').write_text(json.dumps([[0,'context'], [0,'custom'], [0,'1024'], [0,'back']]))
    check('initialize_config "$2"; model_menu; [[ $CTX_SIZE == 1024 ]]')
    (work / 'queue').write_text(json.dumps([[0,'context'], [0,'custom'], [255,''], [0,'back']]))
    check('initialize_config "$2"; model_menu; [[ $CTX_SIZE == auto ]]')
    print('PASS: automatic/custom context, native environment, bounded validation, multi-device profiles and canceled edits')


    # GPU controls must stay optional, literal and independent of CPU fallback.
    result, args = launch()
    for flag in ['--split-mode', '--tensor-split', '--fit-target']:
        assert flag not in args
    gpu_controls = {'SPLIT_MODE':('layer','--split-mode'),
                    'TENSOR_SPLIT':('2.5,1','--tensor-split'),
                    'FIT_TARGET':('2048,1024','--fit-target')}
    for key, (value, flag) in gpu_controls.items():
        result, args = launch({'MIR_'+key:value})
        assert result.returncode == 0 and args[args.index(flag)+1] == value, result.stderr
        result, args = launch({'LLAMA_ARG_'+key:value})
        assert result.returncode == 0 and flag not in args
        result, args = launch({'MIR_'+key:'auto', 'LLAMA_ARG_'+key:value})
        assert result.returncode == 0 and flag not in args
        result, args = launch({'MIR_'+key:value, 'LLAMA_ARG_'+key:'invalid'})
        assert result.returncode == 0 and args[args.index(flag)+1] == value
        result, args = launch({'MIR_'+key:value, 'MIR_DEVICE':'none', 'TEST_HELP':help_text.replace(flag,'--unavailable')})
        assert result.returncode == 0 and flag not in args and args[args.index('--gpu-layers')+1] == '0'
        result, args = launch({'MIR_'+key:value, 'TEST_HELP':help_text.replace(flag,'--unavailable')})
        assert result.returncode != 0 and flag in result.stderr and not args
    invalid_gpu = {'SPLIT_MODE':['','bogus','LAYER','$(touch executed)'],
                   'TENSOR_SPLIT':['','0','0,0.0','-1,2','1,','1,,2','1/2','01,2','nan,1','1e2,1',
                                   '2147483648,1','1.1234567890,1','$(touch executed)'],
                   'FIT_TARGET':['','-1','1.5','01','1,','1,,2','2147483648','$(touch executed)']}
    for key, values in invalid_gpu.items():
        for value in values:
            result, args = launch({'MIR_'+key:value})
            assert result.returncode != 0 and not args, (key,value,result.stderr)
    for value in ['0,1','0.5,1.25','2147483647,1']:
        result, args = launch({'MIR_TENSOR_SPLIT':value})
        assert result.returncode == 0, result.stderr
    result, args = launch({'MIR_FIT_TARGET':'0'})
    assert result.returncode == 0
    for arguments in [['-sm','row','-ts','1,2','-fitt','1024'],
                      ['--split-mode=row','--tensor-split=1,2','--fit-target=1024']]:
        check('''initialize_config "$2"
validate_config
prepare_server ''' + ' '.join(arguments) + '''
[[ $EFFECTIVE_SPLIT_MODE == row ]]
''', {'MIR_SPLIT_MODE':'tensor', 'MIR_TENSOR_SPLIT':'2,1', 'MIR_FIT_TARGET':'2048'})
    for arguments in [['-ts'], ['--fit-target'], ['--split-mode','bogus']]:
        result, args = launch(arguments=arguments)
        assert result.returncode != 0 and not args, arguments
    result, args = launch(arguments=['--alias','--tensor-split'])
    assert result.returncode == 0
    for value in ['0,0','1/2','1e2,1']:
        result, args = launch(arguments=['--tensor-split',value])
        assert result.returncode == 0 and args[-2:] == ['--tensor-split',value]
    result, args = launch({'TEST_HELP':help_text.replace('{none,layer,row,tensor}','{none,layer,future_mode}')}, ['--split-mode','future_mode'])
    assert result.returncode == 0 and args[-2:] == ['--split-mode','future_mode']
    result, args = launch({'MIR_SPLIT_MODE':'tensor', 'TEST_HELP':help_text.replace('{none,layer,row,tensor}','{none,layer,row}')})
    assert result.returncode != 0 and 'not advertised' in result.stderr
    print('PASS: optional GPU flags, literal ratio/margin validation, native/MIR/CLI priority, CPU fallback and unsupported builds')

    (work / 'queue').write_text(json.dumps([[0,'multiple'],[0,'Vulkan0\nVulkan1']]))
    check('initialize_config "$2"; select_device; [[ $DEVICE == Vulkan0,Vulkan1 ]]')
    for status, value in [(255,''),(0,'')]:
        queue = [[0,'multiple'],[status,value]] + ([[0,'']] if status == 0 else [])
        (work / 'queue').write_text(json.dumps(queue))
        check('initialize_config "$2"; DEVICE=Vulkan1,Vulkan0; select_device; [[ $DEVICE == Vulkan1,Vulkan0 ]]')
    check('''initialize_config "$2"
DEVICE=Vulkan1,Vulkan0
server_devices
ui() { printf '%s\\n' "$@" > "$TEST_ARGS"; printf 'Vulkan1\\nVulkan0'; }
select_multiple_devices
[[ $DEVICE == Vulkan1,Vulkan0 ]]
mapfile -t options < "$TEST_ARGS"
[[ " ${options[*]} " == *' Vulkan1 Vulkan1: Second GPU '*' on Vulkan0 Vulkan0: First GPU '*' on '* ]]
''')
    (work / 'queue').write_text(json.dumps([[0,'mode'],[0,'row'],[0,'proportions'],[0,'2,1'],[0,'margin'],[0,'2048,1024'],[0,'back']]))
    check('''initialize_config "$2"
DEVICE=Vulkan0,Vulkan1
gpu_memory_menu
[[ $SPLIT_MODE == row && $TENSOR_SPLIT == 2,1 && $FIT_TARGET == 2048,1024 ]]
write_profile "$PROFILES_DIR/GPU.conf"
saved=$(profile_data)
for field in split_mode tensor_split fit_target; do
    sed "s/^$field=.*/$field=invalid/" "$CURRENT_PROFILE" > "$PROFILES_DIR/Bad.conf"
    if load_profile "$PROFILES_DIR/Bad.conf"; then exit 1; fi
    [[ $(profile_data) == "$saved" && $(profile_status) == GPU ]]
done
SPLIT_MODE=auto TENSOR_SPLIT=auto FIT_TARGET=auto
[[ $(profile_status) == 'GPU (Modified)' ]]
load_profile "$PROFILES_DIR/GPU.conf"
[[ $(profile_data) == "$saved" && $(profile_status) == GPU ]]
''')
    (work / 'queue').write_text(json.dumps([[0,'mode'],[255,''],[0,'proportions'],[255,''],[0,'margin'],[255,''],[0,'back']]))
    check('initialize_config "$2"; DEVICE=Vulkan0,Vulkan1; gpu_memory_menu; [[ $SPLIT_MODE == auto && $TENSOR_SPLIT == auto && $FIT_TARGET == auto ]]')
    (work / 'queue').write_text(json.dumps([[0,'mode'],[0,'auto'],[0,'proportions'],[0,'auto'],[0,'margin'],[0,'auto'],[0,'back']]))
    check('''initialize_config "$2"
DEVICE=Vulkan0,Vulkan1 SPLIT_MODE=row TENSOR_SPLIT=2,1 FIT_TARGET=2048
gpu_memory_menu
[[ $SPLIT_MODE == auto && $TENSOR_SPLIT == auto && $FIT_TARGET == auto ]]
''', {'TEST_HELP':'--model FNAME\n--port PORT'})
    check('''initialize_config "$2"
DEVICE=Vulkan0
ui() { return 99; }
gpu_memory_menu
[[ $GPU_SETTINGS_ACTIVE == false ]]
''')
    print('PASS: multi-GPU checklist order/cancellation, advanced menus, single-device visibility and atomic profile tracking')


    # Visibility follows platform capability and usable native memory reports.
    for devices, expected in [
        ('Available devices:\n  (none)', 'false'),
        ('Available devices:\n  GPU0: One GPU (8192 MiB, 4096 MiB free)', 'false'),
        ('Available devices:\n  GPU0: One GPU (8192 MiB, 4096 MiB free)\n  BLAS: CPU accelerator (0 MiB, 0 MiB free)', 'false'),
        ('Available devices:\n  GPU0: One GPU (8192 MiB, 4096 MiB free)\n  GPU1: Unknown memory', 'false'),
        ('Available devices:\n  GPU0: One GPU (8192 MiB, 4096 MiB free)\n  GPU0: Duplicate (8192 MiB, 4096 MiB free)', 'false'),
        ('Available devices:\n  GPU0: One GPU (8192 MiB, 4096 MiB free)\n  GPU1: Second GPU (8192 MiB, 4096 MiB free)', 'true')]:
        check('''initialize_config "$2"
TUI=true SPLIT_MODE=layer TENSOR_SPLIT=2,1 FIT_TARGET=2048
before=$(profile_data)
ui() { printf '%s\\n' "$@" > "$TEST_ARGS"; return 255; }
performance_menu
[[ $GPU_SETTINGS_ACTIVE == "$TEST_EXPECT" ]]
options=$(cat "$TEST_ARGS")
if "$TEST_EXPECT"; then [[ $options == *'GPU memory'* ]]; else [[ $options != *'GPU memory'* ]]; fi
select_device
options=$(cat "$TEST_ARGS")
if "$TEST_EXPECT"; then [[ $options == *'Select multiple devices'* ]]; else [[ $options != *'Select multiple devices'* ]]; fi
prepare_server
if "$TEST_EXPECT"; then
    [[ " ${ARGS[*]} " == *' --split-mode layer '* ]]
else
    [[ " ${ARGS[*]} " != *' --split-mode '* && " ${ARGS[*]} " != *' --tensor-split '* && " ${ARGS[*]} " != *' --fit-target '* ]]
fi
[[ $(profile_data) == "$before" ]]
''', {'TEST_DEVICES':devices, 'TEST_EXPECT':expected})
    check('''initialize_config "$2"
TUI=true DEVICE=Vulkan0 SPLIT_MODE=layer TENSOR_SPLIT=2,1 FIT_TARGET=2048
prepare_server
[[ $GPU_SETTINGS_ACTIVE == false && " ${ARGS[*]} " != *' --split-mode '* ]]
DEVICE=Vulkan0,Vulkan0
refresh_gpu_settings
[[ $GPU_SETTINGS_ACTIVE == false ]]
DEVICE=none
refresh_gpu_settings
[[ $GPU_SETTINGS_ACTIVE == false ]]
''')
    check('''initialize_config "$2"
TUI=true
ui() { printf '%s\\n' "$@" > "$TEST_ARGS"; return 255; }
performance_menu
[[ $GPU_SETTINGS_ACTIVE == false ]]
options=$(cat "$TEST_ARGS")
[[ $options != *'GPU memory'* ]]
''', {'TEST_DEVICE_EXIT':'1'})
    print('PASS: zero/one/two devices, CPU accelerators, unknown/duplicate reports, discovery failure and inactive TUI profile values')

    # The installed build's help is the authority; never reuse draft-cache lists.
    check(r'''initialize_config "$2"
server_capabilities
expected=$'f32\nf16\nbf16\nq8_0\nq4_0\nq4_1\niq4_nl\nq5_0\nq5_1'
[[ $(cache_types K) == "$expected" && $(cache_types V) == "$expected" ]]
help=$'--cache-type-k TYPE\n  allowed values: f16, q4_0,\n                  custom_type\n  (default: f16)\n--cache-type-v TYPE\n  allowed values: f16\n--cache-type-k-draft TYPE\n  allowed values: draft_only'
[[ $(cache_types K "$help") == $'f16\nq4_0\ncustom_type' ]]
[[ $(cache_types V "$help") == f16 ]]
[[ -z $(cache_types K $'--cache-type-k-draft TYPE\nallowed values: draft_only') ]]
''')
    for kind in ['f32', 'f16', 'bf16', 'q8_0', 'q4_0', 'q4_1', 'iq4_nl', 'q5_0', 'q5_1']:
        result, args = launch({'MIR_CACHE_TYPE_K':kind, 'MIR_CACHE_TYPE_V':kind})
        assert result.returncode == 0, (kind, result.stderr)
        assert args[args.index('--cache-type-k')+1] == kind
        assert args[args.index('--cache-type-v')+1] == kind
    result, args = launch()
    assert args[args.index('--cache-type-k')+1] == 'q4_0'
    assert args[args.index('--cache-type-v')+1] == 'q4_0'
    result, args = launch({'LLAMA_ARG_CACHE_TYPE_K':'q8_0', 'LLAMA_ARG_CACHE_TYPE_V':'f16'})
    assert result.returncode == 0 and 'KV cache: K q8_0 | V f16' in result.stdout
    result, args = launch({'LLAMA_ARG_CACHE_TYPE_K':'q8_0', 'MIR_CACHE_TYPE_K':'q4_0'})
    assert result.returncode == 0 and 'KV cache: K q4_0 | V q4_0' in result.stdout
    for key in ['K', 'V']:
        for value in ['', 'Q4_0', 'q4_0 q8_0', '$(touch executed)', '--port']:
            result, args = launch({'MIR_CACHE_TYPE_'+key:value})
            assert result.returncode != 0 and not args, (key, value)
        result, args = launch({'MIR_CACHE_TYPE_'+key:'unavailable'})
        assert result.returncode != 0 and not args and 'not advertised' in result.stderr
    for arguments in [['-ctk','q8_0','-ctv','f16'], ['--cache-type-k=q8_0','--cache-type-v=f16']]:
        result, args = launch({'MIR_CACHE_TYPE_K':'unavailable'}, arguments)
        assert result.returncode == 0 and 'KV cache: K q8_0 | V f16' in result.stdout, result.stderr
    result, args = launch(arguments=['--alias','--cache-type-v'])
    assert result.returncode == 0 and 'KV cache: K q4_0 | V q4_0' in result.stdout
    for arguments in [['-ctk'], ['--cache-type-v'], ['--cache-type-k','unavailable']]:
        result, args = launch(arguments=arguments)
        assert result.returncode != 0 and not args
    result, args = launch({'TEST_HELP':'--model FNAME\n--port PORT'})
    assert result.returncode != 0 and 'does not advertise --cache-type-k' in result.stderr
    print('PASS: all advertised cache types, wrapped/draft help isolation, defaults, native/MIR/CLI priority and unsupported controls')

    (work / 'queue').write_text(json.dumps([[0,'k'],[0,'q8_0'],[0,'v'],[0,'other'],[0,'q5_1'],[0,'back']]))
    check('initialize_config "$2"; cache_menu; [[ $CACHE_TYPE_K == q8_0 && $CACHE_TYPE_V == q5_1 ]]')
    (work / 'queue').write_text(json.dumps([[0,'k'],[255,''],[0,'v'],[0,'other'],[0,'back'],[0,'back']]))
    check('initialize_config "$2"; cache_menu; [[ $CACHE_TYPE_K == q4_0 && $CACHE_TYPE_V == q4_0 ]]')
    check(r'''initialize_config "$2"
CACHE_TYPE_K=q8_0 CACHE_TYPE_V=q5_1
write_profile "$PROFILES_DIR/Cache.conf"
saved=$(profile_data)
CACHE_TYPE_K=f16
[[ $(profile_status) == 'Cache (Modified)' ]]
load_profile "$PROFILES_DIR/Cache.conf"
[[ $(profile_data) == "$saved" && $(profile_status) == Cache ]]
CACHE_TYPE_V=q4_0
[[ $(profile_status) == 'Cache (Modified)' ]]
CACHE_TYPE_V=q5_1
set_generation_preset focused
[[ $CACHE_TYPE_K == q8_0 && $CACHE_TYPE_V == q5_1 ]]
load_profile "$PROFILES_DIR/Cache.conf"
for field in cache_type_k cache_type_v; do
    sed "s/^$field=.*/$field=invalid value/" "$CURRENT_PROFILE" > "$PROFILES_DIR/Bad.conf"
    if load_profile "$PROFILES_DIR/Bad.conf"; then exit 1; fi
    [[ $(profile_data) == "$saved" && $(profile_status) == Cache ]]
done
message() { :; }
platform_timeout() { return 1; }
CAPABILITIES_SERVER=''
select_cache_type K "$CACHE_TYPE_K"
[[ $(profile_data) == "$saved" && $(profile_status) == Cache ]]
''')
    print('PASS: primary/other cache menus, separate K/V edits, cancellation, probe failure, profile round trips and rollback')

    for host, address in [('::1','[::1]'), ('::','[::1]'), ('0.0.0.0','127.0.0.1'),
                          ('127.0.0.2','127.0.0.2'), ('::1,127.0.0.1','[::1]')]:
        result, _ = launch({'MIR_HOST':host})
        assert result.returncode == 0 and f'http://{address}:9931' in result.stdout, result
    result, _ = launch({'LLAMA_ARG_HOST':'::1'})
    assert result.returncode == 0 and 'http://[::1]:9931' in result.stdout
    result, args = launch(arguments=['--port','10001', '--host','::1', '--alias','two words'])
    assert result.returncode == 0 and 'http://[::1]:10001' in result.stdout
    assert (work / 'ports').read_text().strip().endswith(':10001')
    assert args[-6:] == ['--port','10001', '--host','::1', '--alias','two words']
    result, _ = launch({'TEST_BUSY_PORT':'10001'}, ['--port','10001'])
    assert result.returncode != 0 and 'IN USE' in result.stderr and not (work / 'args').exists()
    result, _ = launch({'TEST_BUSY_PORT':'9931'}, ['--port=10002','--host=0.0.0.0'])
    assert result.returncode == 0 and 'http://127.0.0.1:10002' in result.stdout
    result, _ = launch(arguments=['--alias','--port','--lora-scaled','--host','1'])
    assert result.returncode == 0 and 'http://127.0.0.1:9931' in result.stdout, result
    result, _ = launch(arguments=['--no-webui','--host','::1'])
    assert result.returncode == 0 and 'http://[::1]:9931' in result.stdout, result
    for arguments in [['--port'], ['--host'], ['--port','65536']]:
        result, args = launch(arguments=arguments)
        assert result.returncode != 0 and not args, arguments
    check('''initialize_config "$2"
validate_config
prepare_server --host /tmp/mir-test.sock
[[ $URL == 'Unix socket: /tmp/mir-test.sock' && $HEALTH_URL == http://localhost ]]
[[ ${CURL_ARGS[*]} == *'--unix-socket /tmp/mir-test.sock' ]]
''')
    print('PASS: effective host/port, IPv6, wildcard and native binds, occupied overrides, argument values and Unix socket health')

    minimal_help = '--model FNAME\n--port PORT\n--cache-type-k TYPE\n--cache-type-v TYPE'
    result, _ = launch({'TEST_HELP':minimal_help, 'MIR_THREADS':'4'})
    assert result.returncode != 0 and 'does not advertise --threads' in result.stderr
    result, _ = launch({'TEST_HELP':minimal_help})
    assert result.returncode == 0, result.stderr
    result, _ = launch({'TEST_HELP_EXIT':'1'})
    assert result.returncode == 0 and 'Could not inspect' in result.stderr
    result, _ = launch({'MIR_DEVICE':'Vulkan0,Vulkan1'})
    assert result.returncode == 0, result.stderr
    result, _ = launch({'MIR_DEVICE':'Vulkan9'})
    assert result.returncode != 0 and "Device 'Vulkan9' is unavailable" in result.stderr
    result, _ = launch({'MIR_DEVICE':'Vulkan9'}, ['--device','none'])
    assert result.returncode == 0, result.stderr
    check('''initialize_config "$2"
DEVICE=Vulkan9
write_profile "$PROFILES_DIR/OtherComputer.conf"
DEVICE=auto
load_profile "$PROFILES_DIR/OtherComputer.conf"
if prepare_server; then exit 1; fi
[[ $DEVICE == Vulkan9 && $(profile_status) == OtherComputer && $LAUNCH_ERROR == *unavailable* ]]
platform_timeout() { return 1; }
message() { :; }
ui() { printf none; }
select_device
[[ $DEVICE == none ]]
GPU_LAYERS=all
prepare_server
[[ ${ARGS[*]} == *'--device none --gpu-layers 0'* ]]
''')
    # Prove the bound can actually terminate a stalled probe, independently of a GPU.
    executable(commands / 'stalled', '#!/usr/bin/env bash\nexec /bin/sleep 30\n')
    start = time.monotonic()
    check('if platform_timeout 0.1 stalled; then exit 1; fi')
    assert time.monotonic() - start < 3
    print('PASS: server capability checks, missing devices without mutation, CPU recovery and bounded probing')

    # Write metadata-only fixtures: tensor allocation is never needed.
    def gguf(path, fields, endian='<', version=3):
        def string(value):
            value = value.encode()
            return struct.pack(endian+'Q', len(value)) + value
        data = b'GGUF' + struct.pack(endian+'IQQ', version, 0, len(fields))
        for key, kind, value in fields:
            data += string(key) + struct.pack(endian+'I', kind)
            if kind == 8:
                data += string(value)
            elif kind == 9:
                data += struct.pack(endian+'IQ', 8, len(value)) + b''.join(string(s) for s in value)
            else:
                data += struct.pack(endian+{2:'H',4:'I'}[kind], value)
        path.write_bytes(data)

    gguf(models / 'unrelated-name.gguf', [('general.type',8,'mmproj')])
    gguf(models / 'adapter.gguf', [('general.type',8,'adapter')])
    gguf(models / 'first.gguf', [('split.no',2,0), ('general.type',8,'model')])
    gguf(models / 'second.gguf', [('split.no',2,1)])
    gguf(models / 'big-endian.gguf', [('split.no',2,1)], endian='>')
    gguf(models / 'future.gguf', [], version=99)
    gguf(models / 'tokens.gguf', [('tokenizer.ggml.tokens',9,['a','b']), ('general.type',8,'model')])
    (models / 'truncated.gguf').write_bytes(b'GGUF\x03')
    (models / 'oversized.gguf').write_bytes(b'GGUF' + struct.pack('<IQQQ',3,0,1,2**63))
    outside = work / 'outside.gguf'
    gguf(outside, [('general.type',8,'model')])
    (models / 'linked.gguf').symlink_to(outside)
    (models / 'broken.gguf').symlink_to(work / 'missing.gguf')
    (models / 'directory-link').symlink_to(work, target_is_directory=True)
    (work / 'root-link').symlink_to(models, target_is_directory=True)
    check('''initialize_config "$2"
scan_models
[[ $MODEL == "$2" ]]
printf '%s\\0' "${MODELS[@]}" > "$TEST_ARGS"
''')
    discovered = {Path(os.fsdecode(p)).name for p in (work / 'args').read_bytes().split(b'\0') if p}
    assert discovered == {'model.gguf','first.gguf','future.gguf','tokens.gguf','truncated.gguf','oversized.gguf','linked.gguf'}, discovered
    check('''initialize_config "$2"
scan_models
[[ ${#MODELS[@]} == 7 ]]
''', {'MIR_MODELS_DIR':str(work / 'root-link')})
    # No Python is a supported runtime configuration; metadata is advisory only.
    check('''initialize_config "$2"
command() { if [[ ${*: -1} == python3 ]]; then return 1; else builtin command "$@"; fi; }
scan_models
[[ ${#MODELS[@]} == 11 ]]
''')
    print('PASS: linked files/root folders, component and shard metadata, unknown formats and optional-reader fallback')

    # The complete running loop must probe and open the effective IPv6 endpoint.
    (work / 'browser').unlink(missing_ok=True)
    process = subprocess.Popen(['bash', str(root / 'mir.sh'), str(model), '--port', '10003'],
                               env=env | {'TEST_LIVE':'1', 'MIR_HOST':'::1'},
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 5
        while not (work / 'browser').exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        assert (work / 'browser').read_text() == 'http://[::1]:10003'
        curl_args = (work / 'curl').read_bytes().split(b'\0')[:-1]
        assert b'http://[::1]:10003/health' in curl_args and b'--noproxy' in curl_args and b'--globoff' in curl_args
    finally:
        process.terminate()
        process.communicate(timeout=5)
    assert process.returncode == 143
    print('PASS: running health check, browser address and shutdown with an overridden IPv6 endpoint')

    # A rejected setting must return to the TUI so it can be corrected there.
    (work / 'queue').write_text(json.dumps([[0,'launch'], [0,''], [0,'performance'],
                                           [0,'threads'], [0,'auto'], [0,'back'],
                                           [0,'launch'], [0,'']]))
    master, slave = pty.openpty()
    process = subprocess.Popen(['bash', str(root / 'mir.sh')],
                               env=env | {'TEST_LIVE':'1', 'MIR_THREADS':'4',
                                          'TEST_HELP':minimal_help},
                               stdin=slave, stdout=slave, stderr=slave)
    os.close(slave)
    try:
        process.wait(timeout=8)
        assert process.returncode == 0
        assert json.loads((work / 'queue').read_text()) == []
        assert b'--threads' not in (work / 'args').read_bytes().split(b'\0')
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
    print('PASS: unsupported settings return to the TUI for correction before successful launch')
PY
