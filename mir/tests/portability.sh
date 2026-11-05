#!/usr/bin/env bash
# Portable defaults and simulated backend/model edge cases; no real inference.
set -euo pipefail
TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$TEST_ROOT" <<'PY'
import json
import os
from pathlib import Path
import pty
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
--reasoning [on|off|auto]    reasoning
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
    env = {k:v for k,v in os.environ.items() if not k.startswith(('LLAMA_', 'SPUTNIK_', 'MIR_'))}
    env.update(PATH=str(commands) + ':' + env['PATH'], XDG_CONFIG_HOME=str(work / 'config'),
               MIR_LLAMA_CPP_DIR=str(server_dir), MIR_MODELS_DIR=str(models),
               TEST_HELP=help_text, TEST_DEVICES='Available devices:\n  Vulkan0: First GPU\n  Vulkan1: Second GPU',
               TEST_ARGS=str(work / 'args'), TEST_PORTS=str(work / 'ports'),
               TEST_CURL=str(work / 'curl'), TEST_BROWSER=str(work / 'browser'),
               TEST_QUEUE=str(work / 'queue'))
    sources = '\n'.join(f'source "$1/{p.relative_to(root)}"' for p in sorted((root / 'lib').rglob('*.sh'))) + '\n'

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

    result, _ = launch({'TEST_HELP':'--model FNAME\n--port PORT', 'MIR_THREADS':'4'})
    assert result.returncode != 0 and 'does not advertise --threads' in result.stderr
    result, _ = launch({'TEST_HELP':'--model FNAME\n--port PORT'})
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
bounded_command() { return 1; }
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
    check('if bounded_command 0.1 stalled; then exit 1; fi')
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
                                          'TEST_HELP':'--model FNAME\n--port PORT'},
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
