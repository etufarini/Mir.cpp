#!/usr/bin/env bash
# Enforce the platform boundary and Linux startup without any macOS files.
set -euo pipefail
TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$TEST_ROOT" <<'PY'
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

root = Path(sys.argv[1]).resolve()
# Shared features must depend on services, not platform implementations.
for file in [root/'sh/install-core.sh', *sorted((root/'lib').glob('*.sh')), *sorted((root/'lib/tui').glob('*.sh'))]:
    if file.name in ('runtime.sh', 'platform.sh'):
        continue
    text = file.read_text()
    assert not re.search(r'\bis_macos\b|\bDarwin\b|\bHomebrew\b|/proc/|\b(?:gfind|gmv|gtimeout|netstat|lsof|xdg-open)\b', text), file
for file in (root/'tests').rglob('*.sh'):
    if file.name == 'architecture.sh':
        continue
    assert not re.search(r'sources\s*=.*rglob', file.read_text()), file
with tempfile.TemporaryDirectory(prefix='mir-architecture-') as temporary:
    work = Path(temporary)
    (work/'lib/platform').mkdir(parents=True)
    for name in ('runtime.sh', 'platform.sh'):
        (work/'lib'/name).symlink_to(root/'lib'/name)
    (work/'lib/platform/linux.sh').symlink_to(root/'lib/platform/linux.sh')
    # No macOS file exists in this checkout. Importing one must fail the test.
    command = '''source "$1/lib/runtime.sh"
source "$1/lib/platform.sh"
uname() { printf 'Linux\\n'; }
brew() { printf 'Unexpected Homebrew invocation\\n' >&2; exit 99; }
MIR_ROOT=$1
configure_runtime
[[ "$PLATFORM_ID" == linux && "$RUNTIME_BASH" == "$BASH" ]]
load_platform "$PLATFORM_ID"
platform_required_tools
[[ ${REQUIRED_TOOLS[*]} == 'curl ss' ]]
load_platform linux
if load_platform macos; then exit 1; fi
[[ "$PLATFORM_LOADED" == linux ]]
if load_platform '../unexpected'; then exit 1; fi
'''
    result = subprocess.run(['bash','-euo','pipefail','-c',command,'test',str(work)],
                            capture_output=True,text=True,timeout=5,env=os.environ)
    assert result.returncode == 0, (result.stdout,result.stderr)
print('PASS: OS-free shared modules, explicit test imports, Linux-only checkout and adapter isolation')
PY
"$BASH" "$TEST_ROOT/sh/build-install.sh" --check
