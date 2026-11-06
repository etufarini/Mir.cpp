#!/usr/bin/env bash
# Isolated integration checks; optional argument compares a pre-refactor launcher.
set -euo pipefail
TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$TEST_ROOT" "${1:-}" <<'PY'
import json
import os
from pathlib import Path
import pty
import subprocess
import shutil
import sys
import tempfile
import time

root = Path(sys.argv[1])
baseline = sys.argv[2]
launchers = [root / 'mir.sh']
assert all(path.is_file() for path in launchers)
if baseline:
    launchers.append(Path(baseline).resolve())

with tempfile.TemporaryDirectory(prefix='mir-regression-') as temporary:
    work = Path(temporary).resolve()
    bin_dir = work / 'bin'
    bin_dir.mkdir()
    # Exercise the Linux branch even on macOS; native Darwin checks are separate.
    (bin_dir / 'uname').write_text('#!/bin/sh\nprintf "Linux\\n"\n')
    (bin_dir / 'uname').chmod(0o755)
    for tool in ('mv', 'find'):
        gnu = shutil.which('g' + tool)
        if gnu:
            (bin_dir / tool).symlink_to(gnu)
    models = work / 'models with spaces'
    models.mkdir()
    model = models / 'example.gguf'
    model.touch()
    server_dir = work / 'llama with spaces'
    (server_dir / 'build/bin').mkdir(parents=True)
    def executable(path, text):
        path.write_text(text)
        path.chmod(0o755)
    executable(server_dir / 'build/bin/llama-server', '''#!/usr/bin/env bash
if [[ ${1:-} == --list-devices ]]; then
    printf 'Available devices:\\n  Vulkan0: Test GPU\\n  Vulkan1: Other GPU\\n'; exit 0
fi
if [[ ${1:-} == --help ]]; then
    echo 'number of server slots (default: 1)'
    echo '--model --port --host --ctx-size --device --threads --gpu-layers --batch-size --ubatch-size --temperature --top-p --top-k --min-p --repeat-penalty --presence-penalty --frequency-penalty --seed --n-predict'
    exit 0
fi
printf '%s\\0' "$@" > "$TEST_ARGS"
if [[ ${TEST_LIVE:-0} == 1 ]]; then
    echo "$$" > "$TEST_PID"
    trap 'echo stopped > "$TEST_STOP"; exit 0' TERM
    while true; do /bin/sleep 0.05; done
fi
exit "${TEST_EXIT:-0}"
''')
    executable(bin_dir / 'ss', '#!/usr/bin/env bash\nprintf "%s" "${TEST_LISTENERS:-}"\n')
    executable(bin_dir / 'curl', '#!/usr/bin/env bash\nexit "${TEST_HEALTH:-1}"\n')
    executable(bin_dir / 'xdg-open', '#!/usr/bin/env bash\nprintf "%s" "$1" > "$TEST_BROWSER"\n')
    executable(bin_dir / 'sleep', '#!/usr/bin/env bash\n/bin/sleep 0.01\n')
    executable(bin_dir / 'dialog', '''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
p = Path(os.environ['TEST_QUEUE'])
queue = json.loads(p.read_text())
with open(os.environ['TEST_DIALOG'], 'a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\\n')
if not queue:
    sys.exit(255)
status, value = queue.pop(0)
p.write_text(json.dumps(queue))
sys.stdout.write(value)
sys.exit(status)
''')
    env = {k: v for k, v in os.environ.items() if not k.startswith(('LLAMA_', 'MIR_'))}
    env.update(PATH=str(bin_dir) + ':' + env['PATH'], XDG_CONFIG_HOME=str(work / 'config'),
               LLAMA_CPP_DIR=str(server_dir), LLAMA_MODELS_DIR=str(models),
               TEST_ARGS=str(work / 'args'), TEST_PID=str(work / 'pid'),
               TEST_STOP=str(work / 'stopped'), TEST_BROWSER=str(work / 'browser'),
               TEST_QUEUE=str(work / 'queue'), TEST_DIALOG=str(work / 'dialog.log'), TERM='xterm')
    def run(launcher, overrides=None, arguments=None):
        args_file = work / 'args'
        args_file.unlink(missing_ok=True)
        result = subprocess.run(['bash', str(launcher), str(model)] + (arguments or []),
                                env=env | (overrides or {}), cwd='/', capture_output=True, timeout=8)
        error = result.stderr
        error = error.replace(b'MIR_LLAMA_CPP_DIR', b'LLAMA_CPP_DIR').replace(b'MIR_', b'LLAMA_')
        return result.returncode, result.stdout, error, args_file.read_bytes() if args_file.exists() else None
    cases = [({}, []), ({'LLAMA_DEVICE':'none', 'LLAMA_GPU_LAYERS':'all'}, []),
             ({'LLAMA_THREADS':'4', 'LLAMA_GPU_LAYERS':'12', 'LLAMA_DEVICE':'Vulkan0',
               'LLAMA_PROMPT_PROCESSING':'large-batch',
               'LLAMA_HOST':'0.0.0.0', 'LLAMA_PORT':'09931'}, ['--ctx-size','8192','--alias','a b']),
             ({'LLAMA_PROMPT_PROCESSING':'low-memory'}, []),
             ({'LLAMA_THREADS':'0'}, []), ({'LLAMA_GPU_LAYERS':'-1'}, []),
             ({'LLAMA_PORT':'65536'}, []), ({'LLAMA_CTX_SIZE':'bad'}, []),
             ({'LLAMA_PROMPT_PROCESSING':'bad'}, []),
             ({'TEST_LISTENERS':'LISTEN 0 128 0.0.0.0:9931 0.0.0.0:*\n'}, []),
             ({'TEST_EXIT':'7'}, [])]
    for index, (overrides, arguments) in enumerate(cases):
        results = [run(launcher, overrides, arguments) for launcher in launchers]
        renamed = {('MIR_LLAMA_CPP_DIR' if key == 'LLAMA_CPP_DIR' else key.replace('LLAMA_', 'MIR_', 1)): value
                   for key, value in overrides.items()}
        assert run(root / 'mir.sh', renamed, arguments) == results[0], index
        assert all(r == results[0] for r in results), (index, results)
        code, _, error, args = results[0]
        if index < 4:
            assert code == 0 and args, (index, results)
        elif index < 10:
            assert code == 1 and args is None and error, (index, results)
        else:
            assert code == 7, results
        if index == 0:
            assert b'--threads' not in args and b'--gpu-layers' not in args
        if index == 1:
            assert b'--gpu-layers\x000\x00' in args
        if index == 2:
            assert args.endswith(b'--ctx-size\x008192\x00--alias\x00a b\x00')
    print('PASS: direct startup, validation, port blocking, argument boundaries and exit status')

    precedence = run(root / 'mir.sh', {'LLAMA_THREADS':'bad', 'MIR_THREADS':'3',
                         'LLAMA_PORT':'bad', 'MIR_PORT':'10001',
                         'LLAMA_DEVICE':'Vulkan0', 'MIR_DEVICE':'none',
                         'LLAMA_HOST':'127.0.0.2', 'MIR_HOST':'127.0.0.1',
                         'MIR_LLAMA_CPP_DIR':str(server_dir), 'LLAMA_CPP_DIR':'/missing'})
    assert precedence[0] == 0, precedence
    assert b'--threads\x003\x00' in precedence[3] and b'--port\x0010001\x00' in precedence[3]
    assert b'--device\x00none\x00' in precedence[3] and b'--host\x00127.0.0.1\x00' in precedence[3]
    assert run(root / 'mir.sh', {'MIR_THREADS':'', 'LLAMA_THREADS':'4'})[0] == 1
    print('PASS: new environment names, legacy aliases, explicit precedence')

    sampling = ['temperature', 'top_p', 'top_k', 'min_p', 'repeat_penalty', 'presence_penalty', 'frequency_penalty']
    presets = {'focused':['0.6','0.95','20','0','1','0','0'],
               'exploratory':['1','0.95','20','0','1','0','0'],
               'min-p':['1','1','0','0.05','1','0','0']}
    for preset, values in presets.items():
        result = run(root / 'mir.sh', {'MIR_GENERATION_PRESET':preset})
        assert result[0] == 0, result
        args = result[3].decode().split('\0')[:-1]
        for key, value in zip(sampling, values):
            assert args[args.index('--'+key.replace('_','-'))+1] == value, args
        assert '--seed' not in args and '--n-predict' not in args
    default_args = run(root / 'mir.sh')[3].decode().split('\0')
    assert all('--'+key.replace('_','-') not in default_args for key in sampling)
    overrides = {'MIR_GENERATION_PRESET':'focused', 'MIR_TEMPERATURE':'0.75',
                 'LLAMA_TEMPERATURE':'bad', 'MIR_SEED':'4294967295', 'MIR_MAX_TOKENS':'1024'}
    args = run(root / 'mir.sh', overrides, ['--temperature','0.9'])[3].decode().split('\0')[:-1]
    assert args[args.index('--temperature')+1] == '0.75' and args[-2:] == ['--temperature','0.9']
    assert args[args.index('--seed')+1] == '4294967295' and args[args.index('--n-predict')+1] == '1024'
    for key, value in [('TEMPERATURE',''), ('TEMPERATURE','-0.1'), ('TEMPERATURE','nan'),
                       ('TOP_P','1.01'), ('MIN_P','-0.1'), ('TOP_K','1.5'), ('TOP_K','2147483648'),
                       ('REPEAT_PENALTY','0'), ('PRESENCE_PENALTY','$(touch bad)'),
                       ('SEED','4294967296'), ('MAX_TOKENS','-2'), ('GENERATION_PRESET','unknown')]:
        result = run(root / 'mir.sh', {'MIR_'+key:value})
        assert result[0] == 1 and result[3] is None and result[2], (key,value,result)
    for key, value in [('TEMPERATURE','0'), ('TOP_P','1.000'), ('MIN_P','0'), ('TOP_K','0'),
                       ('REPEAT_PENALTY','0.01'), ('PRESENCE_PENALTY','-0.5'), ('FREQUENCY_PENALTY','0.2'),
                       ('SEED','-1'), ('MAX_TOKENS','-1'), ('MAX_TOKENS','0')]:
        assert run(root / 'mir.sh', {'MIR_'+key:value})[0] == 0, (key,value)
    assert run(root / 'mir.sh', {'LLAMA_GENERATION_PRESET':'min-p', 'LLAMA_TEMPERATURE':'0.7'})[0] == 0
    print('PASS: generation presets, default omission, numeric validation, aliases and pass-through precedence')

    # Source functions without running initialization, launching or installing traps.
    sources = 'MIR_ROOT=$1; source "$MIR_ROOT/tests/helpers/core.sh"; load_test_core fake\n'
    # Compare resolved controls and paths as well as launch arguments.
    control_values = {'LLAMA_CPP_DIR': str(server_dir), 'MODELS_DIR': str(models),
                      'CTX_SIZE': '8192', 'PORT': '10002',
                      'DEVICE': 'none', 'THREADS': '3', 'GPU_LAYERS': '12',
                      'PROMPT_PROCESSING': 'low-memory', 'HOST': '::1',
                      'GENERATION_PRESET': 'focused', 'TEMPERATURE': '0.7',
                      'TOP_P': '0.9', 'TOP_K': '30', 'MIN_P': '0.05',
                      'REPEAT_PENALTY': '1.1', 'PRESENCE_PENALTY': '-0.2',
                      'FREQUENCY_PENALTY': '0.2', 'SEED': '42', 'MAX_TOKENS': '2048'}
    def control_snapshot(overrides):
        code = sources + '''initialize_config "$2"
validate_config
profile_data
printf '%s\\n' "$LLAMA_CPP_PATH" "$MODELS_DIR" "$SERVER_HOST" "$(generation_preset)"
'''
        result = subprocess.run(['bash', '-euo', 'pipefail', '-c', code, 'test', str(root), str(model)],
                                env=env | overrides, capture_output=True, timeout=8)
        assert result.returncode == 0, (overrides, result.stderr)
        return result.stdout
    for suffix, value in control_values.items():
        legacy = 'LLAMA_' + ('CPP_DIR' if suffix == 'LLAMA_CPP_DIR' else suffix)
        expected = control_snapshot({legacy: value})
        assert control_snapshot({'MIR_' + suffix: value, legacy: 'bad'}) == expected
    assert run(root / 'mir.sh', {'MIR_THREADS': '', 'LLAMA_THREADS': '4'})[0] == 1
    assert run(root / 'mir.sh', {'MIR_TEMPERATURE': '', 'LLAMA_TEMPERATURE': '0.7'})[0] == 1
    literal_checks = r'''
MIR_HOST=$'$(touch executed)\n'
read_launcher_control literal HOST default
[[ "$literal" == "$MIR_HOST" && ! -e executed ]]
unset MIR_HOST
MIR_THREADS=3
initialize_config "$2"
[[ $THREADS == 3 && ! -v LLAMA_THREADS ]]
MIR_THREADS=4
initialize_config "$2"
[[ $THREADS == 4 && ! -v LLAMA_THREADS ]]
unset MIR_THREADS
LLAMA_THREADS=''
initialize_config "$2"
[[ $THREADS == auto ]]
'''
    subprocess.run(['bash', '-euo', 'pipefail', '-c', sources + literal_checks, 'test', str(root), str(model)],
                   env=env, cwd=work, check=True)
    print('PASS: all current/legacy control priorities, explicit empties, literal values and repeat initialization')
    checks = r'''
initialize_config "$2"
validate_config
save_paths
LLAMA_CPP_PATH=; MODELS_DIR=
load_paths
[[ "$LLAMA_CPP_PATH" == "$LLAMA_CPP_DIR" && "$MODELS_DIR" == "$LLAMA_MODELS_DIR" ]]
scan_models
[[ "$MODEL" == "$2" && ${#MODELS[@]} == 1 ]]
mkdir -p "$PROFILES_DIR"
write_profile "$PROFILES_DIR/Valid.conf"
load_profile "$PROFILES_DIR/Valid.conf"
[[ $(profile_status) == Valid ]]
THREADS=3
[[ $(profile_status) == 'Valid (Modified)' ]]
THREADS=auto
[[ $(profile_status) == Valid ]]
# Canceled overwrite and failed atomic replacement preserve file and tracking.
message() { :; }
ui() { return 1; }
original=$(cat "$CURRENT_PROFILE")
save_profile update
[[ $(cat "$CURRENT_PROFILE") == "$original" && $(profile_status) == Valid ]]
mv() { return 1; }
if write_profile "$CURRENT_PROFILE"; then exit 1; fi
unset -f mv
[[ $(cat "$CURRENT_PROFILE") == "$original" && $(profile_status) == Valid ]]
[[ -z $(find "$PROFILES_DIR" -name '.profile.*' -print) ]]
before=$(profile_data)
printf 'threads=bad\n' >> "$PROFILES_DIR/Valid.conf"
if load_profile "$PROFILES_DIR/Valid.conf"; then exit 1; fi
[[ $(profile_data) == "$before" && $(profile_status) == Valid ]]
printf 'llama_dir=$(touch %s)\nmodels_dir=%s\n' "$CONFIG_DIR/executed" "$MODELS_DIR" > "$PATHS_FILE"
load_paths
[[ ! -e "$CONFIG_DIR/executed" ]]
'''
    subprocess.run(['bash','-euo','pipefail','-c', sources + checks, 'test', str(root), str(model)], env=env, check=True)
    print('PASS: module loading, saved paths, GGUF discovery, profile tracking and invalid-load rollback')

    generation_checks = r'''
initialize_config "$2"
build_model_args
planner_args=$(printf '%s\n' "${MODEL_ARGS[@]}")
set_generation_preset focused
GENERATION[seed]=7 GENERATION[max_tokens]=2048
set_generation_preset min-p
[[ $(generation_preset) == min-p && ${GENERATION[seed]} == 7 && ${GENERATION[max_tokens]} == 2048 ]]
build_model_args
[[ $(printf '%s\n' "${MODEL_ARGS[@]}") == "$planner_args" ]]
write_profile "$PROFILES_DIR/Generation.conf"
(( $(wc -l < "$PROFILES_DIR/Generation.conf") == 16 ))
saved=$(profile_data)
GENERATION[temperature]=0.8
[[ $(generation_preset) == custom && $(profile_status) == 'Generation (Modified)' ]]
load_profile "$PROFILES_DIR/Generation.conf"
[[ $(profile_data) == "$saved" && $(profile_status) == Generation && $(generation_preset) == min-p ]]
GENERATION[seed]=8
[[ $(profile_status) == 'Generation (Modified)' ]]
GENERATION[seed]=7
[[ $(profile_status) == Generation ]]
before=$(profile_data)
for field in model context port device threads gpu_layers prompt_processing "${GENERATION_KEYS[@]}"; do
    while IFS= read -r line; do
        [[ "$line" == "$field="* ]] || printf '%s\n' "$line"
    done < "$PROFILES_DIR/Generation.conf" > "$PROFILES_DIR/Incomplete.conf"
    if load_profile "$PROFILES_DIR/Incomplete.conf"; then exit 1; fi
    [[ $(profile_data) == "$before" && $(profile_status) == Generation ]]
done
for value in 'temperature=nan' 'top_p=2' 'seed=4294967296' 'max_tokens=-2'; do
    field=${value%%=*}
    while IFS= read -r line; do
        if [[ "$line" == "$field="* ]]; then printf '%s\n' "$value"; else printf '%s\n' "$line"; fi
    done < "$PROFILES_DIR/Generation.conf" > "$PROFILES_DIR/Invalid.conf"
    if load_profile "$PROFILES_DIR/Invalid.conf"; then exit 1; fi
    [[ $(profile_data) == "$before" && $(profile_status) == Generation ]]
done
head -n 7 "$PROFILES_DIR/Generation.conf" > "$PROFILES_DIR/Incomplete.conf"
if load_profile "$PROFILES_DIR/Incomplete.conf"; then exit 1; fi
[[ $(profile_data) == "$before" && $(profile_status) == Generation ]]
cat "$PROFILES_DIR/Generation.conf" > "$PROFILES_DIR/Invalid.conf"
printf 'unexpected=auto\n' >> "$PROFILES_DIR/Invalid.conf"
if load_profile "$PROFILES_DIR/Invalid.conf"; then exit 1; fi
[[ $(profile_data) == "$before" && $(profile_status) == Generation ]]
# Invalid or canceled edits preserve all saved values and tracking.
message() { :; }
ui() { printf 'bad'; }
before=$(profile_data)
edit_generation_value temperature
[[ $(profile_data) == "$before" && $(profile_status) == Generation ]]
ui() { return 255; }
edit_generation_value seed
generation_menu
[[ $(profile_data) == "$before" && $(profile_status) == Generation ]]
rm "$PROFILES_DIR/Generation.conf" "$PROFILES_DIR/Incomplete.conf" "$PROFILES_DIR/Invalid.conf"
'''
    subprocess.run(['bash','-euo','pipefail','-c',sources+generation_checks,'test',str(root),str(model)],env=env,check=True)
    print('PASS: sixteen-field profiles, required fields, Modified tracking, rollback, cancellation and planner isolation')

    summary_checks = r'''
initialize_config "$2"
CTX_SIZE=4096
MODEL="/models/$(printf 'long-name-%.0s' {1..20})model.gguf"
DEVICE=$(printf 'Accelerator%.0s' {1..12})
CURRENT_PROFILE="$PROFILES_DIR/$(printf 'Profile%.0s' {1..10}).conf"
SAVED_PROFILE='different settings'
PORT_STATUS=$'Port 9931: IN USE\n123 user server'
printf -v MEMORY_TEXT '%-72s' 'Est. free GiB: RAM 16.3 | GPU 1.5'
before=$(profile_data)
mapfile -t lines < <(configuration_summary)
[[ ${#lines[@]} == 6 && ${lines[0]} == *'(Modified)' ]]
[[ ${lines[1]} == *'...'*model.gguf && ${lines[2]} == 'Context       4K' ]]
[[ ${lines[3]} == Device* && ${lines[4]} == 'Port          9931: IN USE' ]]
for line in "${lines[@]}"; do (( ${#line} <= 72 )); done
[[ $(profile_data) == "$before" ]]
for CTX_SIZE in auto 0 4096 12345 2147483647; do
    mapfile -t lines < <(configuration_summary)
    [[ ${lines[2]} == "Context       $(context_label)" ]]
    (( ${#lines[2]} <= 72 ))
done
MODEL=''
[[ $(configuration_summary) == *'Model         Not selected'* ]]
'''
    subprocess.run(['bash','-euo','pipefail','-c',sources+summary_checks,'test',str(root),str(model)],env=env,check=True)
    print('PASS: compact summary, long names, Modified visibility and unchanged settings')

    # Migration is isolated from the normal regression settings and never evaluates data.
    migration_base = work / 'migration config'
    legacy = migration_base / 'llama-launcher'
    legacy.mkdir(parents=True)
    (legacy / 'profiles').mkdir()
    paths_data = f'llama_dir={server_dir}\nmodels_dir={models}\n'
    (legacy / 'paths.conf').write_text(paths_data)
    profile_data = (f'model={model}\ncontext=4096\nport=9931\n'
                    'device=auto\nthreads=auto\ngpu_layers=auto\nprompt_processing=auto\n'
                    + ''.join(f'{key}=auto\n' for key in [*sampling, 'seed', 'max_tokens'])).encode()
    (legacy / 'profiles/Old.conf').write_bytes(profile_data)
    migration_env = {k:v for k,v in env.items() if k not in ('LLAMA_CPP_DIR','LLAMA_MODELS_DIR')}
    migration_env.update(XDG_CONFIG_HOME=str(migration_base), TEST_SERVER_DIR=str(server_dir), TEST_MODELS_DIR=str(models))
    migration_check = r'initialize_config "$2"; [[ "$LLAMA_CPP_PATH" == "$TEST_SERVER_DIR" && "$MODELS_DIR" == "$TEST_MODELS_DIR" ]]; load_profile "$PROFILES_DIR/Old.conf"; [[ $(profile_status) == Old ]]'
    def check_migration(code, success=True):
        result = subprocess.run(['bash','-euo','pipefail','-c',sources+code,'test',str(root),str(model)],
                                env=migration_env, capture_output=True)
        assert (result.returncode == 0) == success, result.stderr
        return result
    check_migration(migration_check)
    imported = migration_base / 'mir.cpp'
    assert (imported / 'paths.conf').read_text() == paths_data
    assert (imported / 'profiles/Old.conf').read_bytes() == profile_data
    assert (legacy / 'paths.conf').read_text() == paths_data
    (legacy / 'profiles/Later.conf').write_text('not copied after first import')
    check_migration(migration_check)
    assert not (imported / 'profiles/Later.conf').exists()
    shutil.rmtree(imported)
    failure = check_migration('cp() { return 1; }; initialize_config "$2"', success=False)
    assert b'Cannot import previous' in failure.stderr and not imported.exists()
    assert not list(migration_base.glob('.mir-migration.*'))
    check_migration('mv() { return 1; }; initialize_config "$2"', success=False)
    assert not imported.exists() and (legacy / 'paths.conf').read_text() == paths_data
    assert not list(migration_base.glob('.mir-migration.*'))
    check_migration(migration_check)
    # Existing Mir.cpp settings win even when the legacy source changes.
    recent_profile = profile_data.replace(b'context=4096', b'context=8192')
    (legacy / 'profiles/Old.conf').write_bytes(recent_profile)
    check_migration(migration_check + '; [[ $CTX_SIZE == 4096 ]]')
    shutil.rmtree(imported)
    check_migration(migration_check + '; [[ $CTX_SIZE == 8192 ]]')
    assert (imported / 'profiles/Old.conf').read_bytes() == recent_profile
    assert (legacy / 'profiles/Old.conf').read_bytes() == recent_profile
    shutil.rmtree(imported)
    check_migration('cp() { return 1; }; initialize_config "$2"', success=False)
    assert not imported.exists() and not list(migration_base.glob('.mir-migration.*'))
    # A destination created during activation must also remain untouched.
    check_migration(r'''mv() {
    mkdir -p "$CONFIG_DIR"
    printf existing > "$CONFIG_DIR/Existing"
    command mv "$@"
}
initialize_config "$2"
[[ $(cat "$CONFIG_DIR/Existing") == existing && ! -e "$PATHS_FILE" ]]
''')
    assert sorted(p.name for p in imported.iterdir()) == ['Existing']
    assert not list(migration_base.glob('.mir-migration.*'))
    print('PASS: atomic legacy import, unchanged originals, existing-directory precedence and failed-import recovery')

    hidden = models / '.hidden'
    hidden.mkdir()
    (work / 'queue').write_text(json.dumps([[0,'hidden'],[0,'path'],[0,str(hidden)],[0,'use']]))
    folder_checks = r'initialize_config "$2"; [[ $(select_folder "$MODELS_DIR") == "$MODELS_DIR/.hidden" ]]'
    subprocess.run(['bash','-euo','pipefail','-c',sources+folder_checks,'test',str(root),str(model)],env=env,check=True)
    (work / 'queue').write_text(json.dumps([[255,'']]))
    folder_checks = r'initialize_config "$2"; previous=$MODELS_DIR; if select_folder "$MODELS_DIR"; then exit 1; fi; [[ "$MODELS_DIR" == "$previous" ]]'
    subprocess.run(['bash','-euo','pipefail','-c',sources+folder_checks,'test',str(root),str(model)],env=env,check=True)
    print('PASS: hidden-folder navigation, typed paths and cancellation')

    # Drive the complete TUI in a real terminal, using a deterministic dialog queue.
    for launcher in launchers:
        (work / 'config/mir.cpp/profiles/A profile.conf').unlink(missing_ok=True)
        queue = [[0,'configurations'],[0,'save'],[0,'A profile'],[0,''],[0,'back'],
                 [0,'model'],[0,'context'],[0,'8192'],
                 *([[0,'generation'],[0,'preset'],[0,'focused'],
                 [0,'sampling'],[0,'temperature'],[0,'0.7'],[0,'back'],
                 [0,'seed'],[0,'42'],[0,'max_tokens'],[0,'2048'],[0,'back']] if launcher == root / 'mir.sh' else []),
                 [0,'back'],
                 [0,'performance'],[0,'prompt'],[0,'low-memory'],[0,'back'],
                 [0,'configurations'],[0,'update'],[0,''],[0,''],[0,'back'],
                 [0,'configurations'],[0,'load'],[0,'0'],
                 [0,'configurations'],[0,'delete'],[0,'0'],[0,''],[0,'back'],
                 [0,'server'],[0,'check'],[0,'details'],[0,''],[0,'back'],[0,'launch'],[1,''],[0,''],[0,'']]
        (work / 'queue').write_text(json.dumps(queue))
        (work / 'dialog.log').write_text('')
        (work / 'stopped').unlink(missing_ok=True)
        master, slave = pty.openpty()
        process = subprocess.Popen(['bash',str(launcher)], stdin=slave, stdout=slave, stderr=slave,
                                   env=env | {'TEST_LIVE':'1','TEST_HEALTH':'0'}, cwd='/')
        os.close(slave)
        try:
            process.wait(timeout=8)
            assert process.returncode == 0
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
        assert (work / 'stopped').exists(), 'Server was not cleaned up'
        assert not (work / 'config/mir.cpp/profiles/A profile.conf').exists()
        assert json.loads((work / 'queue').read_text()) == []
        log = (work / 'dialog.log').read_text()
        assert 'View log' in log and 'Ready' in log
        if launcher == root / 'mir.sh':
            assert 'MIR.CPP / STATION CONTROL' in log and 'Status     Ready' in log
            assert 'Est. free: unavailable' in log
            assert 'Free GiB:' in log, log
            dialogs = [json.loads(line) for line in log.splitlines()]
            for args in dialogs:
                assert args.count('MIR.CPP / STATION CONTROL') == 1
                title = args[args.index('--title')+1].strip()
                assert title and 'Mir.cpp' not in title and 'STATION CONTROL' not in title
            menus = [args for args in dialogs if '--menu' in args]
            model_menus = [args for args in menus if args[args.index('--title')+1] == ' Model settings ']
            assert model_menus
            for args in model_menus:
                index = args.index('--menu')
                assert args[index+4] == '4'
                assert args[index+5::2] == ['model','context','generation','back']
            assert all(args[args.index('--ok-label')+1] == 'Select' for args in menus)
            for args in menus:
                cancel = [value for key, value in zip(args, args[1:]) if key == '--cancel-label'][-1]
                assert cancel == ('Quit' if 'Launch server' in args else 'Back')
            main = [args for args in menus if 'Launch server' in args]
            assert main[0][main[0].index('--default-item')+1] == 'launch'
            assert any(args[args.index('--default-item')+1] == 'model' for args in main)
            assert any(args[args.index('--default-item')+1] == 'context' for args in menus)
            for args in main:
                assert args[args.index('--title')+1] == ' Main menu '
                index = args.index('--menu')
                assert args[index+5::2] == ['launch','model','performance','server','configurations','paths','quit']
                assert len(args[index+1].splitlines()) == 6
            assert any('--msgbox' in args and ' Port process details ' in args and '--scrollbar' in args for args in dialogs)
            assert any('--msgbox' in args and ' Information ' in args for args in dialogs)
            assert all(args[args.index('--title')+1] == ' Server log ' and '--exit-label' in args
                       for args in dialogs if '--textbox' in args)
        args = (work / 'args').read_bytes()
        assert b'--ctx-size\x008192\x00' in args and b'--batch-size\x00512\x00' in args
        if launcher == root / 'mir.sh':
            assert b'--temperature\x000.7\x00' in args and b'--seed\x0042\x00' in args and b'--n-predict\x002048\x00' in args
        # The log viewer must have received a temporary file removed by cleanup.
        boxes = [json.loads(line) for line in log.splitlines() if '--textbox' in line]
        assert boxes and not Path(boxes[0][boxes[0].index('--textbox')+1]).exists()
    print('PASS: TUI navigation, settings, readiness, logs, Stop server and temporary-log cleanup')

    for launcher in launchers:
        (work / 'pid').unlink(missing_ok=True)
        (work / 'stopped').unlink(missing_ok=True)
        process = subprocess.Popen(['bash', str(launcher), str(model)], env=env | {'TEST_LIVE':'1'},
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 4
            while not (work / 'pid').exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            assert (work / 'pid').exists()
            process.terminate()
            process.communicate(timeout=4)
            assert process.returncode == 143 and (work / 'stopped').exists()
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
    print('PASS: SIGTERM exit status and owned-server cleanup')

    # Exercise listener safety without sending any operating-system signal.
    safety = r'''
initialize_config "$2"
check_port() { LISTENERS=occupied; PIDS=(999999); PORT_STATUS='Port 9931: IN USE'; }
message() { :; }
ps() { printf 'identity\n'; }
sleep() { :; }
kill() { printf '%s\n' "$*" >> "$TEST_STOP"; }
ui() { return 1; }
stop_listener
[[ ! -e "$TEST_STOP" ]]
ui() { [[ "$*" != *SIGKILL* ]]; }
stop_listener
[[ $(cat "$TEST_STOP") == '-TERM 999999' ]]
rm "$TEST_STOP"
# PID identity changes between confirmation and the signal attempt.
ui() { ps() { printf 'changed\n'; }; }
stop_listener
[[ ! -e "$TEST_STOP" ]]
'''
    (work / 'stopped').unlink(missing_ok=True)
    subprocess.run(['bash','-euo','pipefail','-c',sources+safety,'test',str(root),str(model)],env=env,check=True)
    print('PASS: canceled shutdown, separate SIGKILL confirmation and reused-PID protection')
PY
