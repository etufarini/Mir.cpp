#!/usr/bin/env bash
# macOS dependency and terminal fixtures; no real Homebrew packages are changed.
set -euo pipefail
TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$TEST_ROOT" <<'PY'
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time

root = Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='mir-macos-build-') as temporary:
    work = Path(temporary)
    commands = work / 'bin'
    commands.mkdir()
    brew = commands / 'brew'
    brew.write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$TEST_WORK/packages"
printf 'BREW_OUTPUT\\n'
[ "${TEST_BREW_FAIL:-0}" = 0 ] || exit 1
: > "$TEST_WORK/installed"
''')
    brew.chmod(0o755)
    env = {k:v for k,v in os.environ.items() if not k.startswith(('MIR_', 'SPUTNIK_', 'LLAMA_', 'XDG_'))}
    env.update(HOME=str(work), XDG_CONFIG_HOME=str(work / 'config'),
               PATH=str(commands) + ':' + os.environ['PATH'], TEST_WORK=str(work),
               TERM='xterm-256color', LANG='C.UTF-8')
    source = '''MIR_ROOT=$1
source "$MIR_ROOT/tests/helpers/core.sh"
load_test_core macos
xcode-select() { [[ ${TEST_SDK_FAIL:-0} == 0 ]]; }
xcrun() { [[ ${TEST_SDK_FAIL:-0} == 0 ]]; }
command() {
    if [[ $1 == -v ]]; then
        case "$2" in
            brew) [[ ${TEST_NO_BREW:-0} == 0 ]]; return $? ;;
            cmake|python3|gtimeout|gmv|gfind|dialog|flock)
                [[ ${TEST_MISSING:-0} == 0 || -f "$TEST_WORK/installed" ]]; return $? ;;
            git|make|cc|c++) return 0 ;;
        esac
    fi
    builtin command "$@"
}
'''
    def check(code, overrides=None, success=True):
        result = subprocess.run(['bash', '-euo', 'pipefail', '-c', source + code, 'test', str(root)],
                                env=env | (overrides or {}), start_new_session=True,
                                capture_output=True, text=True, timeout=8)
        assert (result.returncode == 0) == success, (result.stdout, result.stderr)
        return result

    check('''[[ $(platform_build_backends) == $'cpu\\nCPU\\nmetal\\nMetal (GPU)' ]]
platform_build_flags cpu
[[ ${BUILD_FLAGS[*]} == -DGGML_METAL=OFF ]]
platform_build_flags metal
[[ ${BUILD_FLAGS[*]} == -DGGML_METAL=ON ]]
if platform_build_flags cuda; then exit 1; fi
platform_ensure_dependencies build
platform_ensure_dependencies metal
''')
    assert not (work / 'packages').exists()
    result = check('platform_ensure_dependencies build', {'TEST_SDK_FAIL':'1'}, False)
    assert 'xcode-select --install' in result.stderr and not (work / 'packages').exists()
    result = check('platform_ensure_dependencies build', {'TEST_MISSING':'1', 'TEST_NO_BREW':'1'}, False)
    assert 'Homebrew is required' in result.stderr
    result = check('platform_ensure_dependencies build', {'TEST_MISSING':'1'}, False)
    assert 'brew install cmake python coreutils' in result.stderr
    assert not (work / 'packages').exists()
    check('''capture() {
    [[ $* == 'macos_install_packages cmake python coreutils' ]]
    touch "$TEST_WORK/installed"
}
platform_ensure_dependencies build capture
''', {'TEST_MISSING':'1'})
    (work / 'installed').unlink()
    check('''refuse() { return 1; }
if platform_ensure_dependencies build refuse; then exit 1; fi
[[ ! -e "$TEST_WORK/installed" ]]
''', {'TEST_MISSING':'1'})
    check('''check_dependencies() { [[ $1 == install ]]; }
TEST_SDK_FAIL=1 platform_ensure_dependencies launcher
capture() {
    [[ $* == 'macos_install_packages coreutils findutils dialog flock' ]]
    touch "$TEST_WORK/installed"
}
TEST_MISSING=1 platform_ensure_dependencies launcher capture
''')
    (work / 'installed').unlink()
    check('''check_dependencies() { return 1; }
if platform_ensure_dependencies launcher; then exit 1; fi
''')
    print('PASS: launcher package mapping, SDK-independent setup and native dependency failures')
    print('PASS: CPU/Metal flags, SDK prerequisite, missing Homebrew/tools, grouped packages and dependency rollback')

    code = source + '''THEME_FILE="$MIR_ROOT/dialogrc"
ui --infobox 'Before build dependencies' 7 60
result=0
platform_ensure_dependencies build dependency_terminal || result=$?
ui --infobox 'After build dependencies' 7 60
exit "$result"
'''
    def terminal_check(answer, failure):
        (work / 'installed').unlink(missing_ok=True)
        (work / 'packages').unlink(missing_ok=True)
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        def session():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)
        process = subprocess.Popen(['bash', '-euo', 'pipefail', '-c', code, 'test', str(root)],
                                   stdin=slave, stdout=slave, stderr=slave,
                                   env=env | {'TEST_MISSING':'1', 'TEST_BREW_FAIL':str(failure)},
                                   preexec_fn=session)
        os.close(slave)
        output = bytearray()
        def pump():
            if select.select([master], [], [], 0.05)[0]:
                try:
                    output.extend(os.read(master, 65536))
                except OSError:
                    pass
        def await_text(text):
            deadline = time.monotonic() + 5
            while text not in output and time.monotonic() < deadline:
                pump()
            assert text in output, output
        try:
            await_text(b'[y/N]')
            os.write(master, answer.encode() + b'\n')
            await_text(b'Press Enter to return to Mir.cpp.')
            assert b'After build dependencies' not in output and process.poll() is None
            os.write(master, b'\n')
            deadline = time.monotonic() + 5
            while process.poll() is None and time.monotonic() < deadline:
                pump()
            assert process.poll() is not None, output
            while select.select([master], [], [], 0.05)[0]:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                if not data:
                    break
                output.extend(data)
            assert (process.returncode == 0) == (answer == 'y' and failure == 0), output
            clear = b'\x1b[0m\x1b[2J\x1b[H'
            first = output.index(clear)
            last = output.index(clear, first + len(clear))
            assert output.index(b'Before build dependencies') < first < output.index(b'Missing dependency packages')
            assert output.index(b'Press Enter to return') < last < output.index(b'After build dependencies')
            if answer == 'y':
                assert first < output.index(b'BREW_OUTPUT') < last
                assert (work / 'packages').read_text() == 'install --formula cmake python coreutils\n'
            else:
                assert not (work / 'packages').exists()
            assert (work / 'installed').exists() == (answer == 'y' and failure == 0)
        finally:
            os.close(master)
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=5)
    for answer, failure in [('y',0), ('n',0), ('y',1)]:
        terminal_check(answer, failure)
    print('PASS: real 80x24 Homebrew consent, cancellation/failure, output handoff and menu redraw with simulated packages')
PY
