#!/usr/bin/env bash
# Isolated build/update and package-manager checks; no real packages or models.
set -euo pipefail
TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$TEST_ROOT" "${1:-linux}" <<'PY'
import hashlib
import io
import json
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import struct
import subprocess
import sys
import tarfile
import tempfile
import termios
import time

root = Path(sys.argv[1])
adapter = sys.argv[2]
assert adapter in ('linux', 'macos')
gpu = 'metal' if adapter == 'macos' else 'vulkan'
with tempfile.TemporaryDirectory(prefix='mir-build-test-') as temporary:
    work = Path(temporary)
    home = work / 'home with spaces'
    home.mkdir()
    commands = work / 'bin'
    commands.mkdir()

    def executable(name, text):
        path = commands / name
        path.write_text(text)
        path.chmod(0o755)

    executable('git', '''#!/usr/bin/env bash
if [[ $* == *rev-parse* ]]; then
    [[ $* != *--verify* || ${TEST_NOT_TAG:-0} == 0 ]] || exit 1
    printf '%040d\\n' 1; exit
fi
[[ ${TEST_CLONE_FAIL:-0} == 0 ]] || exit 1
printf '%s\\0' "$@" >> "$TEST_WORK/git.args"
if [[ ${TEST_SLOW:-0} == 1 ]]; then
    echo "$$" > "$TEST_WORK/worker.pid"
    trap 'echo stopped > "$TEST_WORK/worker.stopped"; exit 143' TERM
    /bin/sleep 30
fi
target=${*: -1}
mkdir -p "$target/tools/ui/dist"
if [[ ${TEST_PIN_UI:-0} == 1 ]]; then
    mkdir -p "$target/scripts"
    touch "$target/scripts/ui-assets.cmake"
elif [[ ${TEST_NO_UI:-0} == 0 ]]; then echo '<html>fixture</html>' > "$target/tools/ui/dist/index.html"; fi
''')
    executable('cmake', '''#!/usr/bin/env bash
printf '%s\\0' "$@" >> "$TEST_WORK/cmake.args"
[[ ${TEST_CMAKE_FAIL:-0} == 0 ]] || exit 1
if [[ $* == *'--target help'* ]]; then exit 99; fi
if [[ ${1:-} == -S ]]; then
    mkdir -p "$4/bin"
    cat > "$4/bin/llama-server" <<'SERVER'
#!/usr/bin/env bash
[[ ${TEST_PROBE_FAIL:-0} == 0 ]] || exit 1
if [[ ${TEST_SLOW_PROBE:-0} == 1 ]]; then
    echo "$$" > "$TEST_WORK/probe.pid"
    trap 'echo stopped > "$TEST_WORK/probe.stopped"; exit 143' TERM
    /bin/sleep 30
fi
if [[ ${1:-} == --list-devices ]]; then
    echo 'Available devices:'
    echo '  BLAS: CPU library (0 MiB, 0 MiB free)'
    if [[ ${TEST_NO_DEVICE:-0} == 0 ]]; then echo '  Arbitrary0: Test accelerator'; fi
else echo 'version/help fixture'; fi
SERVER
    chmod +x "$4/bin/llama-server"
fi
''')
    executable('curl', '''#!/usr/bin/env bash
[[ ${TEST_NETWORK_FAIL:-0} == 0 ]] || exit 22
printf '%s\\0' "$@" >> "$TEST_WORK/curl.args"
if [[ $* == *'/releases/tags/'* ]]; then printf '%s' "$TEST_UI_META"; exit; fi
while (( $# )); do
    if [[ $1 == --output ]]; then cp -- "$TEST_UI_ARCHIVE" "$2"; exit; fi
    shift
done
printf '%s' '[{"tag_name":"v1","published_at":"2026-01-01","draft":false},{"tag_name":"b2","published_at":"2026-01-03","prerelease":true},{"tag_name":"draft","published_at":"2026-01-04","draft":true}]'
''')
    executable('ps', '''#!/usr/bin/env bash
if [[ ${TEST_PS_RACE:-0} == 1 && ! -e "$TEST_WORK/ps-started" ]]; then
    touch "$TEST_WORK/ps-started"
    /bin/sleep 2
    exit 1
fi
exec "$TEST_REAL_PS" "$@"
''')
    executable('ss', '#!/usr/bin/env bash\nexit 0\n')
    executable('setsid', '#!/usr/bin/env python3\nimport os, sys\nos.setsid()\nos.execvp(sys.argv[1], sys.argv[1:])\n')
    env = {k: v for k, v in os.environ.items() if not k.startswith(('MIR_', 'LLAMA_', 'XDG_'))}
    env.update(HOME=str(home), XDG_CONFIG_HOME=str(home / 'config'),
               XDG_DATA_HOME=str(home / 'data'), PATH=str(commands) + ':' + os.environ['PATH'],
               MIR_ROOT=str(root), TEST_GPU=gpu, TEST_WORK=str(work), TEST_REAL_PS=shutil.which('ps'))
    sources = 'source "$MIR_ROOT/tests/helpers/core.sh"\nload_test_core ' + adapter + '\n'
    init = '''initialize_config
mkdir -p "$CONFIG_DIR"
message() { printf '%s\\n' "$*" >> "$TEST_WORK/messages"; }
ui() { /bin/sleep 0.03; return 5; }
'''

    def check(code, overrides=None, success=True, timeout=12):
        result = subprocess.run(['bash', '-euo', 'pipefail', '-c', sources + init + code],
                                env=env | (overrides or {}), capture_output=True, text=True, timeout=timeout)
        assert (result.returncode == 0) == success, (code, result.stdout, result.stderr)
        return result

    check('''[[ $(latest_build_tag) == b2 ]]
for tag in 'bad;touch /tmp/never' '../bad' '-bad' ''; do
    if valid_build_tag "$tag"; then exit 1; fi
done
''')
    check('latest_build_tag', {'TEST_NETWORK_FAIL': '1'}, success=False)
    print('PASS: release ordering, prereleases, network errors and literal tag validation')

    check('''LLAMA_CPP_PATH="$HOME/external"
mkdir -p "$LLAMA_CPP_PATH"; echo original > "$LLAMA_CPP_PATH/keep"
MODEL="$HOME/model.gguf"; touch "$MODEL"
DEVICE=none; CTX_SIZE=4096
install_build v1 cpu 2
read_build "$LLAMA_CPP_PATH"
[[ $BUILD_TAG == v1 && $BUILD_BACKEND == cpu && -z $BUILD_PREVIOUS ]]
first=$LLAMA_CPP_PATH
[[ $SERVER == "$first/build/bin/llama-server" && -f "$HOME/external/keep" ]]
[[ $DEVICE == none && $CTX_SIZE == 4096 && $MODEL == "$HOME/model.gguf" ]]
install_build b2 "$TEST_GPU" 2
read_build "$LLAMA_CPP_PATH"
[[ $BUILD_TAG == b2 && $BUILD_BACKEND == "$TEST_GPU" && $BUILD_PREVIOUS == "${first##*/}" ]]
second=$LLAMA_CPP_PATH
CAPABILITIES_SERVER=old
activate_build "$first"
[[ $LLAMA_CPP_PATH == "$first" && -z $CAPABILITIES_SERVER ]]
activate_build "$second"
[[ $LLAMA_CPP_PATH == "$second" ]]
''')
    assert ('-DGGML_' + gpu.upper() + '=ON\0').encode() in (work / 'cmake.args').read_bytes()
    assert b'--target\0llama-server\0' in (work / 'cmake.args').read_bytes()
    assert b'--target\0help\0' not in (work / 'cmake.args').read_bytes()
    if adapter == 'linux':
        check('''stage=$(mktemp -d "$(build_root)/builds/build.XXXXXXXX")
    build_release "$stage" b2 cuda 2 ''
    read_build "$stage"
    [[ $BUILD_BACKEND == cuda ]]
    rm -rf -- "$stage"
    ''')
        assert b'-DGGML_CUDA=ON\0' in (work / 'cmake.args').read_bytes()
    print('PASS: install, update, backend flags, restore and preserved model settings')

    ui_archive = work / 'ui.tar.gz'
    def make_ui_archive(unsafe=False):
        with tarfile.open(ui_archive, 'w:gz') as archive:
            entries = {'llama-v1/index.html':b'<html>UI release v1</html>'}
            if unsafe:
                entries[str(work / 'escaped-ui')] = b'unsafe'
            for name, data in entries.items():
                entry = tarfile.TarInfo(name)
                entry.size = len(data)
                archive.addfile(entry, io.BytesIO(data))
        return {'tag_name':'v1', 'assets':[{
            'name':'llama-v1-ui.tar.gz',
            'browser_download_url':'https://github.com/ggml-org/llama.cpp/releases/download/v1/llama-v1-ui.tar.gz',
            'digest':'sha256:' + hashlib.sha256(ui_archive.read_bytes()).hexdigest()}]}

    ui_metadata = make_ui_archive()
    ui_env = {'TEST_PIN_UI':'1', 'TEST_UI_META':json.dumps(ui_metadata), 'TEST_UI_ARCHIVE':str(ui_archive)}
    check('''stage=$(mktemp -d "$(build_root)/builds/build.XXXXXXXX")
build_release "$stage" v1 cpu 2 ''
[[ $(cat "$stage/source/tools/ui/dist/index.html") == '<html>UI release v1</html>' ]]
[[ ! -e "$stage/ui.tar.gz" ]]
rm -rf -- "$stage"
''', ui_env)
    assert b'-DLLAMA_USE_PREBUILT_UI=OFF\0' in (work / 'cmake.args').read_bytes()
    download_args = (work / 'curl.args').read_bytes()
    assert b'/releases/tags/v1\0' in download_args and b'/download/v1/llama-v1-ui.tar.gz\0' in download_args
    assert b'/download/latest/' not in download_args
    for failure in ('digest', 'missing_asset', 'tag', 'unsafe_archive'):
        metadata = make_ui_archive(unsafe=failure == 'unsafe_archive')
        if failure == 'digest': metadata['assets'][0]['digest'] = 'sha256:' + '0' * 64
        if failure == 'missing_asset': metadata['assets'] = []
        if failure == 'tag': metadata['tag_name'] = 'other'
        check('''previous=$LLAMA_CPP_PATH; before=$(cat "$PATHS_FILE")
if install_build v1 cpu 2; then exit 1; fi
[[ $LLAMA_CPP_PATH == "$previous" && $(cat "$PATHS_FILE") == "$before" ]]
''', ui_env | {'TEST_UI_META':json.dumps(metadata)})
        assert not (work / 'escaped-ui').exists()
    print('PASS: exact-release Web UI, SHA-256, disabled latest fallback and missing/mismatched/unsafe asset rejection')
    linked = work / 'linked builds'
    linked.symlink_to(home / 'data/mir.cpp/llama.cpp/builds', target_is_directory=True)
    check('''stage=$(mktemp -d "$TEST_WORK/linked builds/build.XXXXXXXX")
build_release "$stage" linked cpu 2 ''
[[ -x "$stage/build/bin/llama-server" ]]
rm -rf -- "$stage"
''')
    cmake_args = (work / 'cmake.args').read_bytes().split(b'\0')[:-1]
    for index, arg in enumerate(cmake_args[:-1]):
        if arg in (b'-S', b'-B'):
            path = os.fsdecode(cmake_args[index + 1])
            assert path == str(Path(path).resolve()), path
    print('PASS: symlinked staging paths resolve consistently for upstream CMake UI packaging')


    for failure in ('TEST_CLONE_FAIL', 'TEST_NOT_TAG', 'TEST_CMAKE_FAIL', 'TEST_PROBE_FAIL', 'TEST_NO_UI', 'TEST_NO_DEVICE'):
        check('''previous=$LLAMA_CPP_PATH; before=$(cat "$PATHS_FILE")
count=$(find "$(build_root)/builds" -mindepth 1 -maxdepth 1 -type d | wc -l)
if install_build broken vulkan 2; then exit 1; fi
[[ $LLAMA_CPP_PATH == "$previous" && $(cat "$PATHS_FILE") == "$before" ]]
[[ $(find "$(build_root)/builds" -mindepth 1 -maxdepth 1 -type d | wc -l) == "$count" ]]
''', {failure: '1'})
    check('''previous=$LLAMA_CPP_PATH; before=$(cat "$PATHS_FILE")
save_paths() { return 1; }
if install_build unsaved cpu 2; then exit 1; fi
[[ $LLAMA_CPP_PATH == "$previous" && $(cat "$PATHS_FILE") == "$before" ]]
''')
    check('''exec 7> "$(build_root)/.build.lock"; flock -n 7
previous=$LLAMA_CPP_PATH
if install_build locked cpu 2; then exit 1; fi
[[ $LLAMA_CPP_PATH == "$previous" ]]
''')
    print('PASS: checkout/compiler/probe/UI/device/storage failures and concurrent build protection')

    for slow, name in [('TEST_SLOW','worker'), ('TEST_SLOW_PROBE','probe')]:
        check('''previous=$LLAMA_CPP_PATH; before=$(cat "$PATHS_FILE")
ui() {
    if [[ ${UI_TITLE:-} == 'Building llama.cpp' ]]; then
        for attempt in {1..100}; do
            [[ -f "$TEST_WORK/$TEST_PROCESS_NAME.pid" ]] && break
            /bin/sleep 0.01
        done
        /bin/sleep 0.05
        return 1
    fi
    return 0
}
if install_build canceled cpu 2; then exit 1; fi
[[ $LLAMA_CPP_PATH == "$previous" && $(cat "$PATHS_FILE") == "$before" ]]
for attempt in {1..100}; do
    [[ -f "$TEST_WORK/$TEST_PROCESS_NAME.stopped" ]] && break
    /bin/sleep 0.01
done
[[ -f "$TEST_WORK/$TEST_PROCESS_NAME.stopped" ]]
''', {slow:'1', 'TEST_PROCESS_NAME':name})
    print('PASS: confirmed cancellation stops both compiler and server probes and preserves paths')

    (work / 'worker.pid').unlink()
    (work / 'worker.stopped').unlink()
    process = subprocess.Popen(['bash', '-euo', 'pipefail', '-c', sources + init + 'install_build interrupted cpu 2'],
                               env=env | {'TEST_SLOW':'1'}, start_new_session=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    deadline = time.monotonic() + 5
    while not (work / 'worker.pid').exists() and time.monotonic() < deadline:
        time.sleep(0.02)
    assert (work / 'worker.pid').exists()
    os.killpg(process.pid, signal.SIGTERM)
    process.communicate(timeout=5)
    deadline = time.monotonic() + 3
    while not (work / 'worker.stopped').exists() and time.monotonic() < deadline:
        time.sleep(0.02)
    assert (work / 'worker.stopped').exists()
    print('PASS: launcher termination stops its detached compiler process group')

    (work / 'worker.pid').unlink()
    (work / 'worker.stopped').unlink()
    process = subprocess.Popen(['bash', '-euo', 'pipefail', '-c', sources + init + 'install_build interrupted cpu 2'],
                               env=env | {'TEST_SLOW':'1', 'TEST_PS_RACE':'1'}, start_new_session=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    worker_group = None
    try:
        deadline = time.monotonic() + 5
        while not all((work / name).exists() for name in ('worker.pid', 'ps-started')) and time.monotonic() < deadline:
            time.sleep(0.01)
        assert (work / 'ps-started').exists() and (work / 'worker.pid').exists()
        worker_group = os.getpgid(int((work / 'worker.pid').read_text()))
        os.killpg(process.pid, signal.SIGTERM)
        process.communicate(timeout=5)
        deadline = time.monotonic() + 3
        while not (work / 'worker.stopped').exists() and time.monotonic() < deadline:
            time.sleep(0.02)
        assert (work / 'worker.stopped').exists()
    finally:
        if worker_group:
            try: os.killpg(worker_group, signal.SIGTERM)
            except ProcessLookupError: pass
        if process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
            process.communicate(timeout=5)
    print('PASS: deterministic SIGTERM during initial worker identity lookup')

    check('''metadata="$LLAMA_CPP_PATH/mir-build.conf"
cp "$metadata" "$TEST_WORK/metadata"
printf 'format=1\ntag=$(touch %s)\n' "$TEST_WORK/executed" > "$metadata"
if read_build "$LLAMA_CPP_PATH"; then exit 1; fi
[[ ! -e "$TEST_WORK/executed" ]]
cp "$TEST_WORK/metadata" "$metadata"
if read_build "$LLAMA_CPP_PATH/../../builds/${LLAMA_CPP_PATH##*/}"; then exit 1; fi
latest_build_tag() { printf b2; }
ui() { return 0; }
menu() {
    if [[ -f "$TEST_WORK/menu.visited" ]]; then printf back;
    else touch "$TEST_WORK/menu.visited"; printf update; fi
}
platform_ensure_dependencies() { return 0; }
build_menu
''')
    assert 'already the latest' in (work / 'messages').read_text()
    print('PASS: data-only metadata, contained managed paths and current-release menu')

    if adapter != 'linux':
        print('PASS: macOS managed CPU/Metal builds, update/restore and worker cancellation fixtures')
        sys.exit(0)

    # Simulated package operations use a pipe for the script and a PTY for consent.
    executable('apt-get', '''#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$TEST_WORK/packages"
printf 'PACKAGE_STDOUT\\n'
printf 'PACKAGE_STDERR\\n' >&2
exit "${TEST_APT_FAIL:-0}"
''')
    executable('sudo', '''#!/usr/bin/env bash
printf 'sudo %s\\n' "$*" >> "$TEST_WORK/packages"
if [[ ${TEST_PASSWORD:-0} == 1 && $2 == update ]]; then
    printf '[sudo] password: ' > /dev/tty
    IFS= read -r -s password < /dev/tty
    printf '\\n' > /dev/tty
    [[ $password == test-password ]] || exit 1
fi
exec "$@"
''')
    executable('dpkg-query', '#!/usr/bin/env bash\nprintf "install ok installed"\n')
    executable('apt-cache', '#!/usr/bin/env bash\nexit 1\n')
    dependency_code = sources + '''
debian_package_manager() { return 0; }
command() {
    if [[ $1 == -v && $2 == cmake ]]; then return 1; fi
    builtin command "$@"
}
if [[ ${TEST_TUI:-0} == 1 ]]; then
    THEME_FILE="$MIR_ROOT/dialogrc"
    ui --infobox 'Dependency menu marker' 7 60
    result=0
    platform_ensure_dependencies build dependency_terminal || result=$?
    ui --infobox 'Returned to menu marker' 7 60
    exit "$result"
fi
platform_ensure_dependencies build
'''
    def dependency_run(answer, overrides=None):
        settings = env | {'TERM':'xterm-256color', 'LANG':'C.UTF-8'} | (overrides or {})
        master, slave = pty.openpty()
        def terminal():
            import fcntl
            import termios
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        process = subprocess.Popen(['bash'], stdin=subprocess.PIPE, stdout=slave, stderr=slave,
                                   env=settings, preexec_fn=terminal)
        os.close(slave)
        process.stdin.write(dependency_code.encode())
        process.stdin.close()
        output = b''
        def await_text(text):
            nonlocal output
            deadline = time.monotonic() + 5
            while text not in output and time.monotonic() < deadline:
                if select.select([master], [], [], 0.1)[0]:
                    try:
                        output += os.read(master, 65536)
                    except OSError:
                        break
            assert text in output, output
        try:
            await_text(b'[y/N]')
            os.write(master, answer.encode() + b'\n')
            if settings.get('TEST_PASSWORD') == '1' and answer == 'y' and os.geteuid() != 0:
                await_text(b'[sudo] password:')
                deadline = time.monotonic() + 2
                while termios.tcgetattr(master)[3] & termios.ECHO and time.monotonic() < deadline:
                    time.sleep(0.01)
                assert not termios.tcgetattr(master)[3] & termios.ECHO
                os.write(master, b'test-password\n')
            if settings.get('TEST_TUI') == '1':
                await_text(b'Press Enter to return to Mir.cpp.')
                assert b'Returned to menu marker' not in output and process.poll() is None
                os.write(master, b'\n')
            deadline = time.monotonic() + 5
            while process.poll() is None and time.monotonic() < deadline:
                if select.select([master], [], [], 0.05)[0]:
                    try:
                        output += os.read(master, 65536)
                    except OSError:
                        break
            process.wait(timeout=1)
            while select.select([master], [], [], 0.1)[0]:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                output += data
            return process.returncode, output
        finally:
            os.close(master)
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)

    assert dependency_run('n')[0] != 0
    assert not (work / 'packages').exists()
    assert dependency_run('y')[0] == 0
    package_log = (work / 'packages').read_text()
    assert 'apt-get update' in package_log and 'install --no-remove -y cmake' in package_log
    assert 'upgrade' not in package_log
    assert dependency_run('y', {'TEST_APT_FAIL': '1'})[0] != 0
    print('PASS: terminal consent with piped input, limited sudo, refusal and package failure')

    clear = b'\x1b[0m\x1b[2J\x1b[H'
    for answer, failure in [('y','0'), ('n','0'), ('y','1')]:
        before = (work / 'packages').read_bytes()
        status, output = dependency_run(answer, {'TEST_TUI':'1', 'TEST_APT_FAIL':failure, 'TEST_PASSWORD':'1'})
        assert (status == 0) == (answer == 'y' and failure == '0'), output
        first_clear = output.index(clear)
        last_clear = output.index(clear, first_clear + len(clear))
        assert output.index(b'Dependency menu marker') < first_clear < output.index(b'Missing dependency packages')
        assert output.index(b'Press Enter to return') < last_clear < output.index(b'Returned to menu marker')
        assert b'test-password' not in output
        if answer == 'y':
            assert first_clear < output.index(b'PACKAGE_STDOUT') < last_clear
            assert first_clear < output.index(b'PACKAGE_STDERR') < last_clear
        else:
            assert b'PACKAGE_STDOUT' not in output and (work / 'packages').read_bytes() == before
    result = check('''debian_package_manager() { return 0; }
platform_ensure_dependencies build dependency_terminal
''')
    assert not result.stdout and not result.stderr
    print('PASS: 80x24 dialog handoff, sudo input, stdout/stderr, pause and redraw on success/failure/refusal; no pause when ready')
PY
