#!/usr/bin/env bash
# Managed builds are immutable after activation; paths.conf selects the version.

build_root() { printf '%s/mir.cpp/llama.cpp' "${XDG_DATA_HOME:-$HOME/.local/share}"; }

valid_build_tag() { [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]{0,79}$ ]]; }

read_build() {
    local path=$1 line key root
    local -A fields=()
    root=$(build_root)
    [[ "$path" == "$root/builds/${path##*/}" && ${path##*/} =~ ^build\.[[:alnum:]]{8}$ &&
        -d "$path" && ! -L "$path" && -f "$path/mir-build.conf" && ! -L "$path/mir-build.conf" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == *=* ]] || return 1
        key=${line%%=*}
        case "$key" in format|tag|commit|backend|previous) ;; *) return 1 ;; esac
        [[ ! -v "fields[$key]" ]] || return 1
        fields[$key]=${line#*=}
    done < "$path/mir-build.conf"
    (( ${#fields[@]} == 5 )) && [[ ${fields[format]} == 1 ]] || return 1
    valid_build_tag "${fields[tag]}" && [[ ${fields[commit]} =~ ^[a-f0-9]{40,64}$ ]] || return 1
    platform_build_flags "${fields[backend]}" || return 1
    [[ -z ${fields[previous]} || ${fields[previous]} =~ ^build\.[[:alnum:]]{8}$ ]] || return 1
    BUILD_TAG=${fields[tag]}; BUILD_COMMIT=${fields[commit]}
    BUILD_BACKEND=${fields[backend]}; BUILD_PREVIOUS=${fields[previous]}
}

latest_build_tag() {
    # Published development releases count too; /latest excludes prereleases.
    curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
        --connect-timeout 15 --max-time 45 --retry 1 \
        'https://api.github.com/repos/ggml-org/llama.cpp/releases?per_page=30' |
        python3 -c 'import json, sys
releases = [r for r in json.load(sys.stdin) if not r.get("draft") and r.get("published_at")]
if not releases: sys.exit("No published llama.cpp releases found.")
print(max(releases, key=lambda r: r["published_at"])["tag_name"])'
}

prepare_build_ui() {
    local stage=$1 tag=$2 metadata
    local -a asset fetch=(curl --fail --silent --show-error --location --proto '=https' --tlsv1.2
        --connect-timeout 15 --max-time 180 --retry 1)
    # A bundled UI already belongs to the checked-out release. Modern upstream
    # otherwise falls back to latest when shallow Git history reports build 1.
    [[ ! -s "$stage/source/tools/ui/dist/index.html" ]] || return 0
    metadata=$("${fetch[@]}" "https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$tag" |
        python3 -c 'import json, re, sys
release = json.load(sys.stdin)
tag = sys.argv[1]
name = "llama-" + tag + "-ui.tar.gz"
if release.get("tag_name") != tag: sys.exit("UI release does not match the selected tag.")
assets = [a for a in release.get("assets", []) if a.get("name") == name]
if len(assets) != 1: sys.exit("No matching Web UI release asset. Choose another published tag.")
asset = assets[0]
url = "https://github.com/ggml-org/llama.cpp/releases/download/" + tag + "/" + name
digest = asset.get("digest") or ""
if asset.get("browser_download_url") != url or not re.fullmatch(r"sha256:[0-9a-f]{64}", digest):
    sys.exit("Web UI release URL or SHA-256 digest is missing or invalid.")
print(url)
print(digest[7:])' "$tag") || return 1
    mapfile -t asset <<< "$metadata"
    (( ${#asset[@]} == 2 )) || return 1
    printf 'Downloading Web UI for release %s...\n' "$tag"
    "${fetch[@]}" "${asset[0]}" --output "$stage/ui.tar.gz" || return 1
    python3 - "$stage/ui.tar.gz" "$stage/source/tools/ui/dist" "${asset[1]}" "$tag" <<'PY' || return 1
import hashlib
from pathlib import Path, PurePosixPath
import shutil
import sys
import tarfile

archive, destination, expected = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
prefix = 'llama-' + sys.argv[4]
digest = hashlib.sha256()
with archive.open('rb') as source:
    for chunk in iter(lambda: source.read(1024 * 1024), b''):
        digest.update(chunk)
if digest.hexdigest() != expected:
    sys.exit('Web UI archive SHA-256 does not match the selected release.')
with tarfile.open(archive, 'r:gz') as package:
    entries = package.getmembers()
    prefixed = any(PurePosixPath(e.name).parts == (prefix, 'index.html') for e in entries)
    for entry in entries:
        path = PurePosixPath(entry.name)
        if path.is_absolute() or '..' in path.parts or not (entry.isdir() or entry.isfile()):
            sys.exit('Unsafe path or file type in Web UI release archive.')
        if prefixed and path.parts and path.parts[0] != prefix:
            sys.exit('Unexpected root folder in Web UI release archive.')
    for entry in entries:
        parts = PurePosixPath(entry.name).parts
        target = destination.joinpath(*(parts[1:] if prefixed else parts))
        if entry.isdir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            with package.extractfile(entry) as source, target.open('wb') as output:
                shutil.copyfileobj(source, output)
if not (destination / 'index.html').is_file():
    sys.exit('Web UI release archive has no index.html.')
PY
    rm -- "$stage/ui.tar.gz"
}

build_release() {
    local stage=$1 tag=$2 backend=$3 jobs=$4 previous=$5 commit devices targets
    local -a flags=(-DCMAKE_BUILD_TYPE=Release -DLLAMA_BUILD_SERVER=ON
        -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF
        -DGGML_CUDA=OFF -DGGML_VULKAN=OFF)
    valid_build_tag "$tag" && [[ "$jobs" =~ ^([1-9]|[1-5][0-9]|6[0-4])$ ]] || return 1
    platform_build_flags "$backend" || return 1
    flags+=("${BUILD_FLAGS[@]}")
    printf 'Downloading llama.cpp %s (%s)...\n' "$tag" "$backend"
    git -c core.hooksPath=/dev/null clone --depth 1 --single-branch --branch "$tag" \
        https://github.com/ggml-org/llama.cpp.git "$stage/source" || return 1
    commit=$(git -C "$stage/source" rev-parse HEAD) || return 1
    [[ "$commit" =~ ^[a-f0-9]{40,64}$ ]] || return 1
    [[ $(git -C "$stage/source" rev-parse --verify "refs/tags/$tag^{commit}") == "$commit" ]] || {
        printf 'The requested version is not an official release tag.\n' >&2
        return 1
    }
    if [[ -f "$stage/source/scripts/ui-assets.cmake" ]]; then
        prepare_build_ui "$stage" "$tag" || return 1
        flags+=(-DLLAMA_USE_PREBUILT_UI=OFF)
    fi
    cmake -S "$stage/source" -B "$stage/build" "${flags[@]}" || return 1
    cmake --build "$stage/build" --config Release --target llama-server --parallel "$jobs" || return 1
    # Keep optional memory planning when this upstream version provides it.
    targets=$(cmake --build "$stage/build" --target help) || return 1
    if [[ "$targets" == *llama-fit-params* ]]; then
        cmake --build "$stage/build" --config Release --target llama-fit-params --parallel "$jobs" ||
            printf 'WARNING: optional memory planner could not be built.\n'
    fi
    [[ -x "$stage/build/bin/llama-server" ]] || return 1
    # Keep probes in the worker group so Cancel also stops a stalled driver probe.
    platform_build_probe "$stage/build/bin/llama-server" --version || return 1
    platform_build_probe "$stage/build/bin/llama-server" --help || return 1
    devices=$(platform_build_probe "$stage/build/bin/llama-server" --list-devices) || return 1
    printf '%s\n' "$devices"
    if [[ "$backend" != cpu && ! "$devices" =~ (^|$'\n')[[:space:]]+[^[:space:]]+:[[:space:]] ]]; then
        printf 'No accelerator is available. Check GPU drivers and device permissions before retrying.\n' >&2
        return 1
    fi
    # Upstream can finish successfully without Web UI assets after a download
    # failure. Do not activate that result for a browser-based launcher.
    if [[ ! -s "$stage/build/tools/ui/dist/index.html" && ! -s "$stage/source/tools/ui/dist/index.html" &&
        ! -s "$stage/source/tools/server/public/index.html.gz" && ! -s "$stage/source/tools/server/public/index.html" &&
        ! -s "$stage/source/examples/server/public/index.html.gz" && ! -s "$stage/source/examples/server/public/index.html" ]]; then
        printf 'Web UI assets are missing. Check the build log and network access; the previous installation was kept.\n' >&2
        return 1
    fi
    printf 'format=1\ntag=%s\ncommit=%s\nbackend=%s\nprevious=%s\n' \
        "$tag" "$commit" "$backend" "$previous" > "$stage/mir-build.conf" || return 1
    printf '\nBuild verified. Ready for activation.\n'
}

activate_build() {
    local path=$1 previous=$LLAMA_CPP_PATH
    read_build "$path" && [[ -x "$path/build/bin/llama-server" ]] || return 1
    LLAMA_CPP_PATH=$path
    if ! save_paths; then LLAMA_CPP_PATH=$previous; return 1; fi
    SERVER="$path/build/bin/llama-server"
    CAPABILITIES_SERVER=''; MEMORY_KEY=''
}
