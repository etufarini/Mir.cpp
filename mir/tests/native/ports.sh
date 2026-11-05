#!/usr/bin/env bash
# Inspect only sockets owned by this test; never signal any listener.
set -euo pipefail
TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "$TEST_ROOT" "$1" <<'PY'
import os
from pathlib import Path
import socket
import subprocess
import sys
root=Path(sys.argv[1]).resolve()
adapter=sys.argv[2]
if (adapter == 'linux' and not sys.platform.startswith('linux')) or (adapter == 'macos' and sys.platform != 'darwin'):
    print(f'SKIP: native {adapter} sockets require that operating system')
    sys.exit(0)
code='MIR_ROOT=$1; source "$MIR_ROOT/tests/helpers/core.sh"; load_test_core "$2"; '
for family,address in [(socket.AF_INET,'127.0.0.1'),(socket.AF_INET6,'::1')]:
    with socket.socket(family) as listener:
        listener.bind((address,0))
        listener.listen()
        port=listener.getsockname()[1]
        check=f'PORT={port}; check_port; [[ -n "$LISTENERS" && " ${{PIDS[*]}} " == *" {os.getpid()} "* ]]'
        result=subprocess.run(['bash','-euo','pipefail','-c',code+check,'test',str(root),adapter],capture_output=True,timeout=10)
        assert result.returncode == 0, result.stderr
    check=f'PORT={port}; check_port; [[ -z "$LISTENERS" ]]'
    result=subprocess.run(['bash','-euo','pipefail','-c',code+check,'test',str(root),adapter],capture_output=True,timeout=10)
    assert result.returncode == 0, result.stderr
print(f'PASS: native {adapter} IPv4/IPv6 discovery, process attribution and socket release')
PY
