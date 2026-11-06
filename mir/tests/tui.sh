#!/usr/bin/env bash
# Real dialog geometry and environment isolation; no server or models needed.
set -euo pipefail
TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TEST_ROOT/lib/tui/common.sh"
export LINES=17 COLUMNS=53 DIALOGOPTS='--begin 1 1'
export DIALOGRC=original-theme DIALOG_TIMEOUT=5
THEME_FILE="$TEST_ROOT/dialogrc"
dialog() {
    [[ ! -v LINES && ! -v COLUMNS && ! -v DIALOGOPTS ]] || return 99
    [[ "$DIALOGRC" == "$THEME_FILE" && "$DIALOG_TIMEOUT" == 5 ]] || return 99
    printf 'selected value'
    return "$TEST_STATUS"
}
for TEST_STATUS in 0 1 5 255; do
    status=0
    value=$(ui --menu test 12 76 1 item value) || status=$?
    [[ "$value" == 'selected value' && "$status" == "$TEST_STATUS" ]]
    [[ "$LINES" == 17 && "$COLUMNS" == 53 && "$DIALOGOPTS" == '--begin 1 1' && "$DIALOGRC" == original-theme ]]
done
unset -f dialog
printf 'PASS: dialog-only environment isolation, selection output and unchanged cancel/timeout statuses\n'
python3 -I - "$TEST_ROOT" <<'PY'
import fcntl
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time

root = Path(sys.argv[1]).resolve()
if not shutil.which('dialog'):
    print('SKIP: install dialog for real terminal geometry checks')
    sys.exit(0)
base = dict(os.environ, TERM='xterm-256color', LINES='17', COLUMNS='53', DIALOGOPTS='--begin 1 1')
with tempfile.TemporaryDirectory(prefix='mir-tui-') as temporary:
    work = Path(temporary)
    def geometry(shape, resized=None, menu=False, widget=None):
        master, slave = pty.openpty()
        def size(value):
            fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack('HHHH', *value, 0, 0))
        size(shape)
        trace = work / 'trace'
        trace.unlink(missing_ok=True)
        code = '''source "$1/lib/tui/common.sh"
THEME_FILE="$1/dialogrc"
UI_TITLE='Geometry check'
'''
        height, width = (22, 80) if menu else (12, 76)
        if widget:
            height, width = {'devices':(20,80), 'gpu':(18,80), 'performance':(19,80)}[widget]
            code += '''source "$1/lib/config.sh"
source "$1/lib/server.sh"
source "$1/lib/tui/settings.sh"
TRACE_FILE=$2
dialog() { command dialog --trace "$TRACE_FILE" "$@"; }
server_capabilities() { :; }
platform_multi_gpu_ui() { return 0; }
server_devices() { GPU_DEVICE_NAMES=(Accelerator0 Accelerator1); }
DEVICE=Accelerator1,Accelerator0
GPU_DEVICE_NAMES=(Accelerator0 Accelerator1)
DEVICE_NAMES=(Accelerator0 Accelerator1)
DEVICE_DESCRIPTIONS=('First GPU' 'Second GPU')
FIT_TARGET=auto SPLIT_MODE=auto TENSOR_SPLIT=auto
GPU_LAYERS=auto THREADS=auto PROMPT_PROCESSING=auto
'''
            code += {'devices':'select_multiple_devices', 'gpu':'gpu_memory_menu',
                     'performance':'performance_menu'}[widget] + '\n'
            code += '[[ $DEVICE == Accelerator1,Accelerator0 ]]\n'
        elif menu:
            code += 'value=$(ui --trace "$2" --menu "Display check" 22 80 2 first "First item" second "Second item"); [[ "$value" == first ]]\n'
        else:
            code += 'ui --trace "$2" --yesno "Display check" 12 76\n'
        code += '[[ "$DIALOGOPTS" == "--begin 1 1" ]]\n'
        def session():
            os.setsid()
            fcntl.ioctl(0, termios.TIOCSCTTY, 0)
        process = subprocess.Popen(['bash', '-euo', 'pipefail', '-c', code, 'test', str(root), str(trace)],
                                   stdin=slave, stdout=slave, stderr=slave, env=base, preexec_fn=session)
        os.close(slave)
        captured = bytearray()
        def pump():
            if select.select([master], [], [], 0.05)[0]:
                try:
                    captured.extend(os.read(master, 65536))
                except OSError:
                    pass
        def positions():
            text = trace.read_text() if trace.exists() else ''
            return [tuple(map(int, match)) for match in re.findall(r'window (\d+)x(\d+) at (\d+),(\d+)', text)]
        def centered(value):
            rows, columns = value
            return height, width, (rows-height)//2, (columns-width)//2
        def await_position(value, after=0):
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                pump()
                windows = positions()
                if after:
                    # dialog can maximize a widget that originally filled the
                    # terminal. Verify its actual rectangle remains centered.
                    if len(windows) > after:
                        h, w, y, x = windows[-1]
                        if (0 < h <= value[0] and 0 < w <= value[1] and
                                (y, x) == ((value[0]-h)//2, (value[1]-w)//2)):
                            return
                elif centered(value) in windows:
                    return
                if process.poll() is not None:
                    break
            raise AssertionError((value, positions(), captured[-2000:]))
        try:
            await_position(shape)
            if resized:
                previous_count = len(positions())
                size(resized)
                os.killpg(process.pid, signal.SIGWINCH)
                await_position(resized, after=previous_count)
            os.write(master, b'\x1b' if widget in ('gpu','performance') else b'\n')
            deadline = time.monotonic() + 5
            while process.poll() is None and time.monotonic() < deadline:
                pump()
            assert process.poll() == 0, (process.poll(), captured[-2000:])
            print(f'PASS: centered {height}x{width} dialog at {shape}' + (f', recentered at {resized}' if resized else ''))
        finally:
            # Close the PTY before waiting so macOS cannot block on queued output.
            os.close(master)
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=3)
    geometry((24, 80), menu=True)
    geometry((40, 120), menu=True)
    geometry((40, 120), resized=(24, 80))
    geometry((24, 80), resized=(40, 120), menu=True)
    for widget in ('devices','gpu','performance'):
        geometry((24, 80), widget=widget)
PY
