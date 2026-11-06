#!/usr/bin/env bash
# Installer integration checks use local archives and an isolated HOME.
set -euo pipefail
TEST_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$TEST_ROOT" "${1:-Linux}" <<'PY'
import io
import shlex
import os
import pty
from pathlib import Path
import subprocess
import shutil
import signal
import time
import sys
import tarfile
import tempfile

root = Path(sys.argv[1])
target_os = sys.argv[2]
assert target_os in ('Linux', 'Darwin')
installer = (root / 'sh/install.sh').read_bytes()
host_brew = shutil.which('brew')
host_brew_data = Path(host_brew).read_bytes() if host_brew else None
with tempfile.TemporaryDirectory(prefix='mir-install-') as temporary:
    work = Path(temporary)
    home = work / 'home with spaces'
    home.mkdir()
    bin_dir = work / 'mock-bin'
    bin_dir.mkdir()
    archive = work / 'source.tar.gz'
    files = ['mir.sh', 'dialogrc', 'sh/uninstall.sh'] + [
        str(p.relative_to(root)) for p in sorted((root / 'lib').rglob('*')) if p.suffix in ('.sh', '.py')]
    documents = ['README.md'] + [
        'mir/' + str(p.relative_to(root)) for p in sorted((root / 'docs').rglob('*')) if p.is_file()]
    files += documents
    def source_path(name):
        return (root.parent if name in documents else root) / name
    def package(omit=None, broken=False, marker=''):
        with tarfile.open(archive, 'w:gz') as tar:
            for name in files:
                if name == omit:
                    continue
                data = source_path(name).read_bytes()
                if name == 'mir.sh':
                    data += b'\nif\n' if broken else ('\n# ' + marker + '\n').encode()
                archive_name = name if name in documents else 'mir/' + name
                info = tarfile.TarInfo('Mir.cpp-main/' + archive_name)
                info.size = len(data)
                info.mode = 0o644  # Installer must make the launcher executable.
                tar.addfile(info, io.BytesIO(data))
    def executable(path, content):
        assert not path.is_symlink(), f'Refusing to overwrite a symlink: {path}'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        path.chmod(0o755)
    executable(bin_dir / 'curl', '''#!/usr/bin/env bash
printf '%s\\0' "$@" > "$TEST_DOWNLOAD_ARGS"
if [[ -n ${TEST_PAUSE_FLAG:-} ]]; then
    printf ready > "$TEST_PAUSE_FLAG"
    /bin/sleep 30
fi
while (( $# )); do
    if [[ $1 == --output ]]; then
        [[ ${TEST_DOWNLOAD:-ok} != fail ]] || exit 22
        if [[ ${TEST_DOWNLOAD:-ok} == truncated ]]; then printf bad > "$2"; exit 0; fi
        cp -- "$TEST_ARCHIVE" "$2"
        exit
    fi
    shift
done
exit 1
''')
    executable(bin_dir / 'uname', '#!/bin/sh\nprintf "' + target_os + '\\n"\n')
    real_move = shutil.which('gmv') or '/bin/mv'
    executable(bin_dir / 'mv', '''#!/usr/bin/env bash
if [[ ${TEST_ACTIVATION:-ok} == fail && ${*: -1} == */current ]]; then exit 1; fi
exec REAL_MOVE "$@"
'''.replace('REAL_MOVE', shlex.quote(real_move)))
    executable(bin_dir / 'gmv', (bin_dir / 'mv').read_text())
    executable(bin_dir / 'netstat', '#!/bin/sh\nexit 0\n')
    executable(bin_dir / 'lsof', '#!/bin/sh\nexit 1\n')
    if not shutil.which('gfind'):
        (bin_dir / 'gfind').symlink_to(shutil.which('find'))
    executable(bin_dir / 'rm', '''#!/usr/bin/env bash
if [[ ${TEST_CLEANUP:-ok} == fail ]]; then
    for target in "$@"; do
        if [[ $target == */releases/install.* && -d $target ]]; then exit 1; fi
    done
fi
exec /bin/rm "$@"
''')
    executable(bin_dir / 'ss', '#!/usr/bin/env bash\nexit 0\n')
    executable(bin_dir / 'sleep', '#!/usr/bin/env bash\n/bin/sleep 0.01\n')
    env = {k: v for k, v in os.environ.items() if not k.startswith(('LLAMA_', 'MIR_', 'XDG_'))}
    env.update(HOME=str(home), PATH=str(bin_dir) + ':' + os.environ['PATH'],
               TEST_ARCHIVE=str(archive), TEST_DOWNLOAD_ARGS=str(work / 'download-args'),
               XDG_CONFIG_HOME=str(home / 'config'))
    install_dir = home / '.local/share/mir.cpp'
    command = home / '.local/bin/mir'
    def install(overrides=None, success=True):
        # stdin matches curl | bash, with a working directory outside the project.
        result = subprocess.run(['bash'], input=installer, env=env | (overrides or {}),
                                cwd='/', capture_output=True, timeout=10)
        assert (result.returncode == 0) == success, result.stderr.decode()
        if (install_dir / '.install.flock').exists():
            import fcntl
            with (install_dir / '.install.flock').open() as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return result
    config = home / 'config/mir.cpp'
    config.mkdir(parents=True)
    (config / 'paths.conf').write_text('existing paths\n')
    (config / 'profiles').mkdir()
    (config / 'profiles/Personal.conf').write_text('existing profile\n')
    # Installation must preserve unrelated applications and their settings.
    previous = home / '.local/share/other-app'
    (previous / 'releases/old').mkdir(parents=True)
    (previous / 'releases/old/other-app.sh').write_text('previous program\n')
    (previous / 'current').symlink_to('releases/old')
    previous_command = home / '.local/bin/other-app'
    executable(previous_command, '#!/bin/sh\n# Other application\nprintf "previous command\\n"\n')
    previous_config = home / 'config/other-app'
    (previous_config / 'profiles').mkdir(parents=True)
    (previous_config / 'paths.conf').write_text('previous paths\n')
    (previous_config / 'profiles/Old.conf').write_text('previous profile\n')
    previous_files = {p: p.read_bytes() for p in [previous_command, previous / 'releases/old/other-app.sh']}
    previous_files.update({p: p.read_bytes() for p in previous_config.rglob('*') if p.is_file()})
    package(marker='first')
    install({'TEST_ACTIVATION':'fail'}, success=False)
    assert not command.exists() and not (install_dir / 'current').exists()
    install()
    target = (install_dir / 'current').resolve()
    assert b'https://codeload.github.com/etufarini/Mir.cpp/tar.gz/refs/heads/main' in (work / 'download-args').read_bytes().split(b'\0')
    assert command.is_file() and os.access(command, os.X_OK)
    selected_adapters = {'lib/platform/linux.sh'} if target_os == 'Linux' else {'lib/platform/macos.sh', 'lib/platform/macos-bootstrap.sh'}
    for name in files:
        if name.startswith('lib/platform/') and name not in selected_adapters:
            assert not (target / name).exists()
        elif name != 'mir.sh':
            assert (target / name).read_bytes() == source_path(name).read_bytes()
    assert (config / 'paths.conf').read_text() == 'existing paths\n'
    assert (config / 'profiles/Personal.conf').read_text() == 'existing profile\n'
    # Prove the installed wrapper locates its modules and forwards each argument.
    model = work / 'model with spaces.gguf'
    model.touch()
    server_dir = work / 'llama.cpp'
    executable(server_dir / 'build/bin/llama-server', '''#!/usr/bin/env bash
if [[ ${1:-} == --help ]]; then echo '--model --port'; exit 0; fi
printf '%s\\0' "$@" > "$TEST_ARGS"
''')
    result = subprocess.run([str(command), str(model), '--alias', 'two words'],
                            env=env | {'MIR_LLAMA_CPP_DIR': str(server_dir), 'TEST_ARGS': str(work / 'args')},
                            cwd='/', capture_output=True, timeout=5)
    assert result.returncode == 0, result.stderr
    assert (work / 'args').read_bytes().endswith(b'--alias\x00two words\x00')
    print('PASS: piped installer, complete runtime, paths with spaces, wrapper and personal configuration')

    package(marker='second')
    install()
    updated = (install_dir / 'current').resolve()
    assert updated != target and not target.exists()
    assert b'# second' in (updated / 'mir.sh').read_bytes()
    snapshot = command.read_bytes()
    releases = set((install_dir / 'releases').iterdir())
    install({'TEST_ACTIVATION':'fail'}, success=False)
    assert (install_dir / 'current').resolve() == updated
    assert command.read_bytes() == snapshot
    assert set((install_dir / 'releases').iterdir()) == releases
    for failure in ['fail', 'truncated']:
        install({'TEST_DOWNLOAD':failure}, success=False)
        assert (install_dir / 'current').resolve() == updated
        assert command.read_bytes() == snapshot
        assert set((install_dir / 'releases').iterdir()) == releases
    for omitted in [*selected_adapters, 'lib/runtime.sh', 'lib/tui/main.sh', 'lib/memory.sh', 'lib/gguf.py', 'dialogrc', 'sh/uninstall.sh', *documents]:
        package(omit=omitted)
        install(success=False)
        assert (install_dir / 'current').resolve() == updated
        assert set((install_dir / 'releases').iterdir()) == releases
    package(broken=True)
    install(success=False)
    assert (install_dir / 'current').resolve() == updated
    assert set((install_dir / 'releases').iterdir()) == releases
    print('PASS: update and rollback on download, archive, missing-file and syntax failures')

    package()
    command.write_text('#!/bin/sh\necho unrelated\n')
    install(success=False)
    assert command.read_text() == '#!/bin/sh\necho unrelated\n'
    command.write_bytes(snapshot)
    # A stale lock file or the legacy lock directory must not block a new run.
    (install_dir / '.install.lock').mkdir()
    install()
    assert (install_dir / '.install.lock').is_dir()
    (install_dir / '.install.lock').rmdir()
    lock_file = install_dir / '.install.flock'
    with lock_file.open('w') as lock:
        import fcntl
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        result = subprocess.run(['bash'], input=installer, env=env, capture_output=True, timeout=5)
        assert result.returncode != 0 and b'Another Mir.cpp installation' in result.stderr
    install()
    print('PASS: unrelated-command protection, concurrent lock and automatic lock release')

    # A forced interruption releases the kernel lock even during a download.
    pause_flag = work / 'download-waiting'
    process = subprocess.Popen(['bash'], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, env=env | {'TEST_PAUSE_FLAG':str(pause_flag)},
                               start_new_session=True)
    try:
        process.stdin.write(installer)
        process.stdin.close()
        deadline = time.monotonic() + 4
        while not pause_flag.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        assert pause_flag.exists()
        process.kill()
        process.wait(timeout=3)
        with lock_file.open() as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    finally:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=3)
    install()
    assert len(list((install_dir / 'releases').glob('install.*'))) == 1
    print('PASS: interrupted download releases the lock and leftover staging is cleaned on reinstall')

    # Cleanup failure is a warning: the new release remains usable.
    result = install({'TEST_CLEANUP':'fail'})
    assert b'WARNING: Reinstallation succeeded' in result.stderr
    assert b'Installation complete with cleanup warnings' in result.stdout
    assert len(list((install_dir / 'releases').glob('install.*'))) == 2
    install()
    assert len(list((install_dir / 'releases').glob('install.*'))) == 1
    print('PASS: incomplete cleanup reports a warning without breaking the active installation')

    # A managed wrapper can be damaged or absent, including its execute bits.
    command.write_text('#!/broken-shell\n# Mir.cpp managed launcher\nbroken exec\n')
    command.chmod(0o600)
    install()
    assert os.access(command, os.X_OK) and command.read_bytes() == snapshot
    command.unlink()
    install()
    assert command.read_bytes() == snapshot
    assert len(list((install_dir / 'releases').glob('install.*'))) == 1
    assert (config / 'paths.conf').read_text() == 'existing paths\n'
    assert (config / 'profiles/Personal.conf').read_text() == 'existing profile\n'
    print('PASS: clean repeated installation and repair of managed wrappers')

    # Control PATH completely so missing-command checks do not depend on the host.
    restricted = work / 'restricted-bin'
    restricted.mkdir()
    tools = 'uname brew bash curl tar gzip mktemp chmod mkdir mv ln rm flock dialog ps find sort grep cut dirname sleep cp'.split()
    tools += ['gfind', 'gmv', 'lsof', 'netstat'] if target_os == 'Darwin' else ['ss']
    for tool in tools:
        source = bin_dir / tool
        if source.exists():
            (restricted / tool).symlink_to(source)
        elif shutil.which(tool):
            (restricted / tool).symlink_to(shutil.which(tool))
        elif tool == 'dialog':
            executable(restricted / tool, '#!/bin/sh\nexit 0\n')
    fake_prefix = work / 'isolated brew'
    (fake_prefix / 'bin').mkdir(parents=True)
    (restricted / 'brew').unlink(missing_ok=True)
    executable(restricted / 'brew', "#!/bin/sh\nprintf '%s\\n' " + shlex.quote(str(fake_prefix)) + "\n")
    (restricted / 'gzip').unlink()
    (restricted / 'dialog').unlink()
    installed = (install_dir / 'current').resolve()
    result = install({'PATH':str(restricted)}, success=False)
    if target_os == 'Darwin':
        assert b'brew install dialog' in result.stderr
        assert b'brew install' in result.stderr
    else:
        assert b'Missing tools for launcher' in result.stderr or b'A terminal is required' in result.stderr
    assert b'Installation complete' not in result.stdout
    assert (install_dir / 'current').resolve() == installed
    assert b'Downloading Mir.cpp' not in result.stdout
    (restricted / 'gzip').symlink_to(shutil.which('gzip'))
    executable(restricted / 'dialog', '#!/bin/sh\nexit 0\n')
    result = install({'PATH':str(restricted)})
    assert ('WARNING: ' + ('open' if target_os == 'Darwin' else 'xdg-open') + ' is missing').encode() in result.stderr
    assert b'Open the server address manually' in result.stderr
    print('PASS: aggregated required dependencies before changes and optional browser warning')

    # Respect XDG_DATA_HOME for a separate fresh installation.
    other_home = work / 'other home'
    other_home.mkdir()
    custom_data = work / 'custom data'
    install({'HOME':str(other_home), 'XDG_DATA_HOME':str(custom_data)})
    assert (custom_data / 'mir.cpp/current/lib/config.sh').is_file()
    assert (other_home / '.local/bin/mir').is_file()
    other_adapter = 'lib/platform/macos.sh' if target_os == 'Linux' else 'lib/platform/linux.sh'
    package(omit=other_adapter)
    install({'HOME':str(other_home), 'XDG_DATA_HOME':str(custom_data)})
    assert not (custom_data / 'mir.cpp/current' / other_adapter).exists()
    print('PASS: only the selected adapter is required and installed')
    print('PASS: XDG data directory')

    def uninstall(arguments=(), overrides=None, success=True):
        result = subprocess.run([str(command), '--uninstall', *arguments],
                                env=env | (overrides or {}), cwd='/', input=b'',
                                capture_output=True, timeout=5)
        assert (result.returncode == 0) == success, (result.stdout, result.stderr)
        return result

    # Invalid arguments and unavailable confirmation must leave everything intact.
    installed = (install_dir / 'current').resolve()
    result = uninstall(success=False)
    assert b'Confirmation requires a terminal' in result.stderr
    uninstall(['--unknown'], success=False)
    uninstall(['--yes', 'extra'], success=False)
    assert command.is_file() and installed.is_dir()
    # Exercise the real terminal prompt, including its default refusal and approval.
    def confirm(answer):
        master, slave = pty.openpty()
        try:
            process = subprocess.Popen([str(command), '--uninstall'], env=env,
                                       stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            os.write(master, answer)
            output, error = process.communicate(timeout=5)
            assert process.returncode == 0, (output, error)
            return output
        finally:
            os.close(master)
            os.close(slave)
    assert b'Uninstallation canceled' in confirm(b'\n')
    assert command.is_file() and installed.is_dir()
    print('PASS: uninstall argument validation, non-interactive refusal and canceled confirmation')

    # Share the installer's lock; no files are removed while it is held.
    with lock_file.open() as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        result = uninstall(['--yes'], success=False)
        assert b'Another Mir.cpp installation or removal' in result.stderr
    assert command.is_file() and installed.is_dir()
    # Calling the script directly cannot bypass command ownership or release checks.
    script = installed / 'sh/uninstall.sh'
    def direct_remove():
        result = subprocess.run(['bash', str(script), str(install_dir), str(command), '--yes'],
                                env=env, capture_output=True, timeout=5)
        assert result.returncode != 0, result.stderr
        return result
    snapshot = command.read_bytes()
    command.write_text('#!/bin/sh\necho unrelated\n')
    assert b'does not belong' in direct_remove().stderr
    command.write_bytes(snapshot)
    moved_command = command.with_name('original-mir')
    command.rename(moved_command)
    command.symlink_to(moved_command)
    assert b'has been replaced' in direct_remove().stderr
    command.unlink()
    moved_command.rename(command)
    # A replaced active link must not allow deletion of a foreign target.
    original_target = os.readlink(install_dir / 'current')
    (install_dir / 'current').unlink()
    (install_dir / 'current').symlink_to(previous / 'releases/old')
    assert b'active installed copy' in direct_remove().stderr
    (install_dir / 'current').unlink()
    (install_dir / 'current').symlink_to(original_target)
    print('PASS: uninstall lock, unrelated command, symlink and active-release protection')

    # Leave a stale managed release, unrelated files, and a link to external data.
    stale = install_dir / 'releases/install.12345678'
    stale.mkdir()
    (stale / 'old.sh').write_text('old program\n')
    unknown = install_dir / 'releases/personal'
    unknown.mkdir()
    (unknown / 'keep').write_text('personal data\n')
    linked = install_dir / 'releases/install.ABCDEFGH'
    linked.symlink_to(previous, target_is_directory=True)
    (install_dir / 'keep').write_text('unrelated file\n')
    result = uninstall(['--yes'], {'TEST_CLEANUP':'fail'}, success=False)
    assert b'Check permissions and retry' in result.stderr
    assert command.is_file() and installed.is_dir() and stale.is_dir()
    # The stored paths work even after HOME and both XDG directories change.
    result = uninstall(['--yes'], {'HOME':str(other_home), 'XDG_DATA_HOME':str(custom_data),
                                 'XDG_CONFIG_HOME':str(work / 'different config')})
    assert b'Uninstallation complete' in result.stdout
    assert not command.exists() and not installed.exists() and not stale.exists()
    assert not (install_dir / 'current').is_symlink()
    assert (unknown / 'keep').read_text() == 'personal data\n'
    assert (install_dir / 'keep').read_text() == 'unrelated file\n'
    assert linked.is_symlink()
    assert lock_file.is_file()
    assert model.is_file() and (server_dir / 'build/bin/llama-server').is_file()
    assert (config / 'paths.conf').read_text() == 'existing paths\n'
    assert (config / 'profiles/Personal.conf').read_text() == 'existing profile\n'
    assert (other_home / '.local/bin/mir').is_file()
    assert (custom_data / 'mir.cpp/current/lib/config.sh').is_file()
    print('PASS: removal, failure reporting, original paths and preservation of personal and external files')
    # A clean reinstall works with the retained lock, followed by confirmed removal.
    # Remove the test's foreign symlink before reinstall: only removal promises to keep it.
    linked.unlink()
    install()
    assert b'Uninstallation complete' in confirm(b'y\n')
    assert not command.exists() and not (install_dir / 'current').exists()
    print('PASS: reinstall after removal and interactive confirmation')
    assert all(path.read_bytes() == data for path, data in previous_files.items())
    assert os.readlink(previous / 'current') == 'releases/old'
    assert subprocess.check_output([str(previous_command)]) == b'previous command\n'
    assert not host_brew or Path(host_brew).read_bytes() == host_brew_data
    print('PASS: unrelated application command, program, settings and host Homebrew are preserved')
PY
