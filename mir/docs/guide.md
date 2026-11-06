# Mir.cpp user guide

For platform support, installation and first launch, see the [README](../../README.md).
This guide covers configuration, maintenance and development.

## Dependencies and source startup

The installer asks before installing missing launcher packages through apt on
Ubuntu/Debian or Homebrew on macOS, including with `curl | bash`. Refusal, failure
or a missing terminal preserves the existing installation. Only apt operations
may use sudo; Mir.cpp and managed llama.cpp builds run as your user.

For manual installation on Ubuntu/Debian:

```bash
sudo apt-get update
sudo apt-get install bash curl ca-certificates coreutils findutils grep \
    util-linux tar gzip dialog iproute2 procps xdg-utils
```

Bash 4.4 or newer is required. `xdg-utils` enables automatic browser opening;
otherwise open the displayed address manually. Assisted installation does not
remove packages or upgrade the system. Other Linux distributions need equivalent
packages installed manually.

On macOS, install Homebrew separately, then install launcher packages manually if
preferred:

```bash
brew install bash coreutils findutils dialog flock
```

On macOS, the installer can start with system Bash 3.2 and may ask to install
compatible Bash before the other packages. Source and installed-command startup
only check dependencies. Homebrew is discovered through `brew --prefix` or its
standard Apple Silicon/Intel locations. Its bin directory is added only within
Mir.cpp, preserving command precedence and leaving the login shell and shell
files unchanged. Installing packages through Homebrew uses neither sudo nor an
explicit update.

To run from a source checkout, keep the whole `mir/` folder together:

```bash
bash mir/mir.sh
```

Run this command from the repository root; module lookup is independent of the
working directory. Python 3 is optional for GGUF filtering, but required by the
managed build workflow for release metadata.

## Using the menu

Use arrow keys to select an item, **Enter** or **Select** to open it and **Tab** to
move between buttons. **Back** or **Esc** cancels a setting or returns from a
submenu. **Quit** or **Esc** on the main screen exits. Menus remember the selected
entry and highlight the current value where available.

The main screen shows the configuration, model, context, device and port status.
Long names are shortened only for display. All seven actions fit an 80×24 terminal:

| Menu | Purpose |
| --- | --- |
| Launch server | Start the model with the displayed settings. |
| Model settings | Select a model, context, KV Cache types and generation settings. |
| Performance | Select devices, CPU threads, GPU layers and prompt processing. |
| Server & port | Edit the port, refresh status, inspect or stop listeners. |
| Saved configurations | Load, update, save or delete settings. |
| Folders | Manage llama.cpp builds and select llama.cpp and models folders. |
| Quit | Exit the launcher. |

The theme in `dialogrc` applies only to Mir.cpp. Colors and font follow your
terminal; status is also shown in text. Dialog windows recenter when resized.
Inherited `LINES`, `COLUMNS` and `DIALOGOPTS` are ignored only for dialog calls so
external sizing options cannot displace the menus.

### Defaults and compatibility

**Auto** and **Default** omit the corresponding launcher arguments, leaving native
llama.cpp settings in effect. K/V cache types default to **Q4_0** and are always
passed explicitly. Model support, context limits and memory requirements depend
on the installed llama.cpp build and hardware.

Before launch, Mir.cpp checks requested controls against server help and checks
explicit devices when discovery succeeds. Unsupported choices produce an error;
the TUI remains available for correction. Help/device probes have 15-second
limits. Without GNU `timeout` (`gtimeout` on macOS), probes are skipped and the
server reports startup errors. Auto and CPU only remain selectable.

Settings take effect at server launch. Browser chat settings and API requests can
override generation defaults; Mir.cpp never changes browser preferences or
conversations.

## Folders and model discovery

Open **Folders → llama.cpp folder** or **Models folder**. The browser displays the
current path, folder actions and alphabetically sorted directories. **Enter**
opens the highlighted directory; **Parent folder** goes up one level. **Enter
path** accepts a typed or pasted path, including spaces and `~/`. Navigation alone
does not save: choose **Use this folder** to confirm. **Back/Esc** cancels.

Dot-prefixed folders are hidden initially. **Show hidden folders** and **Hide
hidden folders** toggle their display; manual paths can always access them.
Select a readable folder. The llama.cpp folder must contain executable
`build/bin/llama-server` or `bin/llama-server`; the source-build layout takes
precedence. For a Homebrew build, select the path from `brew --prefix llama.cpp`.

The models folder is searched recursively for GGUF files. File symlinks and a
linked root folder work; linked subfolders are not traversed. With Python 3, a
bounded metadata reader filters recognized projectors, adapters and continuation
parts of split models. Select the first part and keep the others alongside it.
Unknown or unreadable metadata stays listed for llama.cpp to handle. Without
Python, all discovered GGUF files are shown.

Changing the models folder refreshes discovery, retaining the selected model if
still listed or selecting the first available model. Empty folders are accepted
with a message; select the folder again after adding files. Missing paths or
models can be corrected in the menu. Launching requires an executable server and
a readable model.

Accepted paths are saved atomically in
`${XDG_CONFIG_HOME:-$HOME/.config}/mir.cpp/paths.conf`. A failed save keeps previous
settings. These paths apply to all profiles and direct startup.

## Build and update llama.cpp

Open **Folders → Install / update llama.cpp → Install / change build**. Managed
backends are CPU, Vulkan and CUDA on Linux, or CPU and Metal on macOS. CUDA still
needs validation on NVIDIA hardware. Other builds and backends can be selected
through **llama.cpp folder**; available devices come from the installed server.

![llama.cpp setup menu with install, update, restore and build log controls](screenshots/llama-setup.png)

*The setup menu in a real 80×24 terminal, before selecting a managed build.*

On Ubuntu/Debian, setup offers missing Git, CMake, Make, C/C++ compilers, Python 3,
util-linux, coreutils and OpenSSL/curl development libraries. Vulkan also needs
`libvulkan-dev`, `glslc`, `spirv-headers`, `vulkan-tools` and Mesa Vulkan drivers.
CUDA uses an existing `nvcc`, or offers `cuda-toolkit` from an already configured
NVIDIA repository, falling back to `nvidia-cuda-toolkit`. Compatibility depends on
the distribution; setup does not add repositories, replace kernel drivers or
reboot. See the
[llama.cpp build instructions](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md)
and [NVIDIA installation guide](https://docs.nvidia.com/cuda/cuda-installation-guide-linux/)
for platform requirements.

On macOS, run `xcode-select --install` and complete Apple's command line tools
setup first. Mir.cpp checks the compiler tools and macOS SDK, then offers missing
CMake, Python 3 and GNU timeout through Homebrew. It does not install Homebrew or
change the developer directory. CPU builds disable Metal; Metal builds must
expose an accelerator before activation. Device availability depends on the Mac,
SDK and llama.cpp release.

Package installation temporarily replaces the menu with terminal confirmation
and output, including sudo authentication on Linux if needed. Press **Enter**
after success, failure or cancellation to return. No handoff occurs when all
dependencies are present.

Choose **Latest published release** or **Specific release tag**, then 1–64
compiler jobs (default 2). Latest can include pre-releases and does not imply
stable. More jobs use more RAM; they do not change inference threads.
Each build records the selected tag's commit in a new directory. Downloaded Web UI
assets must match that release and its SHA-256 digest; missing or mismatched
assets block activation. Releases with bundled UI assets use those instead.

**View log** shows build output. **Cancel build** or **Esc** asks before
cancellation; a lock prevents concurrent managed builds. Before activation,
Mir.cpp checks version/help, device discovery and Web UI assets. GPU builds
require an accelerator. These checks do not validate inference or model capacity.

A successful build saves its path for both menu and direct startup. Failure or
cancellation keeps the previous selection. **Check for updates** offers the latest
published release for the current managed backend; **Install / change build** lets
you change backend or version.
**Restore previous build** selects the preceding managed build after confirmation,
offline and without rebuilding. External source trees, models, profiles and
browser settings are preserved.

Builds are retained under
`${XDG_DATA_HOME:-$HOME/.local/share}/mir.cpp/llama.cpp/builds/`, each with source,
build tree and `mir-build.conf`. Failed builds are removed. **View build log**
opens `llama.cpp/build.log`, retained until the next attempt. When reclaiming disk
space, keep builds referenced by saved paths or running sessions. Launcher
updates and removal preserve managed builds and system dependency packages.
Use the same `XDG_DATA_HOME` to manage them later.

## Model settings

Choose a discovered GGUF in **Model settings → Model**.

### Context

Context includes input and output. **Auto** leaves context selection to llama.cpp.
Fixed choices range from 4K to 256K (1K = 1024 tokens). **Custom** accepts `auto` or
0–2147483647 tokens; `0` requests full model context and may need much more memory.
The selected model and build must support the requested context size.

### KV Cache

Open **Model settings → KV Cache** to select **K (keys)** and **V (values)**
separately. Both default to **Q4_0**, explicitly passed as `--cache-type-k q4_0`
and `--cache-type-v q4_0`. These types affect cached attention data, not the
quantization of the GGUF model weights.

The primary choices are **Q4_0** for lower memory use, **Q8_0** for less aggressive
quantization and **F16** for an unquantized cache using more memory. Lower precision
may affect output quality. **Other formats** lists additional types. Only types
advertised by the selected server are offered; failed probing preserves current
values.

Advertised types are not a guarantee of model/backend compatibility. Quantized V
requires Flash Attention, which Mir.cpp leaves automatic while preserving native
overrides. Disabling it can make quantized V fail. Mixed K/V types may be slower or
unsupported; some architectures require matching types. Mir.cpp never silently
substitutes a type. Check **View log** for native compatibility errors, then adjust
the cache types or build.

### Generation settings

Open **Model settings → Generation → Preset**:

| Preset | Temperature | Top-P | Top-K | Min-P |
| --- | --- | --- | --- | --- |
| Default | Native | Native | Native | Native |
| Focused | 0.6 | 0.95 | 20 | 0 |
| Exploratory | 1 | 0.95 | 20 | 0 |
| Min-P | 1 | 1 (disabled) | 0 (disabled) | 0.05 |
| Custom | Edit individual sampling values | | | |

The three explicit presets set repeat penalty to 1 and presence/frequency
penalties to 0. They are manual starting points, with no model-family detection
or quality guarantee. Applying one preserves context, performance, seed and output
length. The label follows the exact sampling values; other combinations show
**Custom**.

**Sampling parameters** edits all seven values. Temperature controls randomness;
Top-P, Top-K and Min-P filter token choices. Penalties can reduce repetition but
also harm useful repeated text. Lower temperature does not guarantee accuracy.
Use **auto** for native defaults. Numeric fields accept integers or, where
allowed, decimals with a leading digit, a dot and up to nine fractional digits.
Ranges appear in the [command-line reference](#advanced-command-line-use).

**Seed** accepts **auto**, **-1** or 0–4294967295; -1 and 4294967295 select random.
A fixed seed helps comparisons but does not guarantee identical results across
hardware or settings. **Maximum output tokens** accepts **auto**, **-1** for no
fixed generation limit, or 0–2147483647. Zero evaluates input without generating
an answer. This limit is separate from context; short limits can truncate output.

To follow these defaults in browser chat, use the Web UI's server-default
sampling settings. If the server rejects an option, inspect **View log**, update
llama.cpp or return that field to **auto**.

## Performance

Start with **Auto** and **Default** under **Performance**:

| Option | Behavior |
| --- | --- |
| Device | **Auto**, **CPU only**, a discovered device, or **Select multiple devices** on Linux when at least two devices report usable memory. Auto can already use multiple GPUs. Space selects devices in the checklist; Enter applies, Back/Esc cancels. CPU only disables GPU layers. |
| CPU threads | **auto** or 1–2147483647. More threads are not always faster. |
| GPU layers | **auto**, **all**, or 0–2147483647. Auto leaves native defaults in effect; all can exceed memory. CPU only shows **Ignored (CPU only)** and retains the chosen value for other devices. |
| Prompt processing | **Default** omits batch overrides. **Low memory** uses `--batch-size 512 --ubatch-size 128`; **Large batch** uses `--batch-size 2048 --ubatch-size 1024`. |
| GPU memory | Linux only, with multiple usable devices active or selected through Auto. Controls split mode, relative GPU proportions and memory margin; all default to **Auto**. |

Batch sizes affect input processing, not answer length. Larger batches need more
memory and do not guarantee faster generation. CPU and GPU can share memory on
integrated graphics. Flash Attention stays automatic. Compare changes using the
same model, context and input; try Auto/Default or a smaller context if loading fails.

### GPU memory

This panel is optional. Keep Auto unless you need to correct placement or
leave room for other GPU applications:

- **Memory margin (MiB)** sets the free-memory target used by llama.cpp's automatic
  fitting (`--fit-target`). One integer applies to every device; a comma-separated
  list sets margins in device order, for example `2048,1024`. This is not a limit
  on process RAM or a guarantee of free VRAM. It has no effect when native fitting
  is disabled and cannot make a fixed configuration fit by itself.
- **Split mode** offers modes advertised by the selected build: layer distribution,
  row distribution and experimental tensor parallelism where available. Model and
  backend restrictions still apply. No mode guarantees a speed improvement.
- **GPU proportions** passes relative weights to `--tensor-split`, for example
  `2,1`, not GiB or fixed memory reservations. Values must be nonnegative, with at
  least one positive value. Effective placement also depends on split mode and
  native fitting. The numbers follow the displayed device order; recheck them
  after changing devices. With Auto devices, use native `--list-devices` order.

The checklist is offered only on Linux when at least two distinct native device
names report positive capacity and valid free memory. Missing or zero-capacity
entries do not count; a failed probe hides the controls. Existing selections keep
their order, followed by new devices in discovery order. Native lists cannot tell
whether different backends expose the same physical GPU.

The GPU memory panel requires multiple eligible devices active. It is hidden on
macOS or with CPU only. While hidden, its saved values are kept but the TUI omits
its launcher arguments. Direct startup and native arguments remain available.
llama.cpp checks model/backend restrictions at startup. The other performance
controls and all model settings remain available on macOS.

## Saved configurations

After selecting a model and settings, open **Saved configurations**:

| Action | Result |
| --- | --- |
| Load configuration | Restore validated settings and return to the main screen for review, without launching. |
| Update current | Replace the current profile after confirmation. |
| Save as new configuration | Save under a name; confirm before replacing an existing profile. |
| Delete configuration | Remove a profile after confirmation. Current settings are kept. |

Names allow 1–80 letters, digits, spaces, dots, underscores or hyphens, starting
with a letter or digit. Profiles are saved only through **Save as new
configuration** or **Update current**. Loading or saving sets the session's
current profile. **Modified** appears only when values differ from the saved
ones; deleting the current profile changes its label to **Not saved**.

Profiles are plain `key=value` files under
`${XDG_CONFIG_HOME:-$HOME/.config}/mir.cpp/profiles/`; back up this folder to retain
them. New saves contain the current settings: model, context, port, device,
threads, GPU layers, prompt processing, K/V cache types, GPU split mode,
proportions, memory margin and nine generation values.
Loading ignores unknown or removed fields. Only the model path is required.
Missing settings use launcher defaults: port 9931, Q4_0 for both cache types and
Auto for the remaining controls, independently of current settings or environment
overrides. Invalid or duplicate recognized fields, malformed lines and missing
models reject the entire load, keeping current settings unchanged. Saved devices
and cache types are checked against the current server before launch. Loading
does not rewrite the file; saving again writes only currently supported fields.

Profiles exclude conversations, trailing arguments and unrelated environment
settings. Global folder paths are stored separately; changing the models folder
can still mark a profile Modified if it changes the selected model.

## Running and stopping the server

After launch, the screen shows **Loading**, then **Ready** when the health check
succeeds. The browser opens at the displayed address, normally
`http://127.0.0.1:9931`. Open it manually if needed. **View log** shows server
output; **Stop server** stops the server and exits the launcher. Closing the
browser leaves the server running. Server logs are temporary and removed on exit.

### Live memory

The running server screen shows **Free GiB**. On Linux it reports available system
RAM and native device memory; **+N** indicates pools available through **Next memory**.
Device numbers follow discovery order. CPU only shows **GPU off**. Missing or
malformed measurements show **N/A** and never block server controls.

On macOS the line shows approximate available system RAM with a `~` marker, using
native `vm_stat` free, inactive and speculative pages and the reported page size,
following [psutil's available-memory calculation](https://github.com/giampaolo/psutil/blob/master/psutil/arch/osx/mem.c).

These readings do not guarantee a model will fit or prevent swapping. The line
omits RSS, pressure, swap, total RAM and device budgets. Mir.cpp does not monitor
utilization, record conversations or upload telemetry. llama.cpp retains its
native automatic memory fitting.

### Occupied ports

The default port is `9931`. **Server & port** checks listeners and offers process
IDs, owners and names when available. **View process details** and shutdown
confirmations support **Up/Down** scrolling. An unidentified listener still blocks
launch; choose another port if it cannot be inspected or stopped.

**Stop process using port** first asks before SIGTERM. If listeners remain, a
separate confirmation is required for SIGKILL. Identity checks reduce the risk of
signalling a reused PID. Permission failures are reported without privilege
elevation. Mir.cpp never automatically stops an existing listener and checks the
port again immediately before launch.

## Advanced command-line use

Passing a model path starts directly without the TUI:

```bash
MIR_CTX_SIZE=8192 MIR_PORT=9931 \
    ~/.local/bin/mir "/path/to/model.gguf"
```

Saved folders apply to direct startup; override them for one invocation with
`MIR_LLAMA_CPP_DIR` and `MIR_MODELS_DIR`.

| Control | Accepted values; default |
| --- | --- |
| `MIR_LLAMA_CPP_DIR`, `MIR_MODELS_DIR` | Folder paths; saved paths when available. |
| `MIR_CTX_SIZE` | `auto` or 0–2147483647; `auto`. Zero requests full model context. |
| `MIR_PORT` | 1–65535; `9931`. |
| `MIR_HOST` | Explicit server bind address; otherwise native host settings or `127.0.0.1`. |
| `MIR_DEVICE` | `auto`, `none` (CPU only), or comma-separated discovered device names; `auto`. |
| `MIR_THREADS` | `auto` or 1–2147483647; `auto`. |
| `MIR_GPU_LAYERS` | `auto`, `all` or 0–2147483647; `auto`. |
| `MIR_SPLIT_MODE` | `auto`, `none`, `layer`, `row` or `tensor`; `auto`. |
| `MIR_TENSOR_SPLIT` | `auto` or comma-separated nonnegative proportions, at least one positive; `auto`. |
| `MIR_FIT_TARGET` | `auto`, one nonnegative MiB integer or a comma-separated list; `auto`. |
| `MIR_PROMPT_PROCESSING` | `auto`, `low-memory`, `large-batch`; `auto`. |
| `MIR_CACHE_TYPE_K`, `MIR_CACHE_TYPE_V` | Lowercase type advertised by the server; `q4_0` for each unless configured otherwise. |

For example, use the CPU, four threads and smaller input chunks:

```bash
MIR_DEVICE=none MIR_THREADS=4 MIR_PROMPT_PROCESSING=low-memory \
    ~/.local/bin/mir "/path/to/model.gguf"
```

GPU memory controls override `LLAMA_ARG_SPLIT_MODE`, `LLAMA_ARG_TENSOR_SPLIT`
and `LLAMA_ARG_FIT_TARGET`, respectively. **Auto** leaves those native settings
in effect; empty values are invalid. Margins and proportion integer parts are
limited to 2147483647; proportions allow up to nine fractional digits. The
[GPU memory panel](#gpu-memory) explains device order and TUI visibility.
For two discovered devices:

```bash
MIR_DEVICE=CUDA0,CUDA1 MIR_TENSOR_SPLIT=2,1 MIR_FIT_TARGET=2048 \
    ~/.local/bin/mir "/path/to/model.gguf"
```

Use device names from your build, not the example names if they differ.

Cache types fall back to the respective native `LLAMA_ARG_CACHE_TYPE_K` and
`LLAMA_ARG_CACHE_TYPE_V` values, then `q4_0` when unset. Empty values are invalid.
For example, use matching Q8_0 caches:

```bash
MIR_CACHE_TYPE_K=q8_0 MIR_CACHE_TYPE_V=q8_0 \
    ~/.local/bin/mir "/path/to/model.gguf"
```

`MIR_GENERATION_PRESET` accepts `default`, `focused`, `exploratory` or `min-p`.
Individual controls override its values; each accepts `auto`:

| Control | Numeric values |
| --- | --- |
| `MIR_TEMPERATURE` | Nonnegative decimal. |
| `MIR_TOP_P`, `MIR_MIN_P` | Decimal from 0 to 1. |
| `MIR_TOP_K` | Integer from 0 to 2147483647. |
| `MIR_REPEAT_PENALTY` | Positive decimal. |
| `MIR_PRESENCE_PENALTY`, `MIR_FREQUENCY_PENALTY` | Signed decimal. |
| `MIR_SEED`, `MIR_MAX_TOKENS` | Ranges described under Generation settings. |

Decimal integer parts are limited to 2147483647 in magnitude. For example:

```bash
MIR_GENERATION_PRESET=focused MIR_TEMPERATURE=0.7 MIR_MAX_TOKENS=2048 \
    ~/.local/bin/mir "/path/to/model.gguf"
```

Arguments after the model path pass unchanged to llama.cpp and can override
launcher choices. Use them for capabilities beyond the menus, such as
`--mmproj /path/to/projector.gguf`, `--embedding` or `--rerank` with a suitable
model and build. Follow the model author's component and template requirements;
these options are not inferred from filenames or saved in profiles.

Legacy `LLAMA_*` launcher aliases remain supported: replace the `MIR_` prefix
with `LLAMA_`, except `MIR_LLAMA_CPP_DIR` maps to `LLAMA_CPP_DIR` and the cache
and GPU memory controls use the native variables described above. Explicit
`MIR_*` values take precedence even when empty and are validated. Empty legacy
values retain fallback defaults for paths and basic controls; empty individual
generation aliases are invalid. Native `LLAMA_ARG_*` variables remain unchanged.

Endpoint checks, readiness and browser opening follow effective `--host` and
`--port` arguments, including IPv6. Wildcard binds use a local browser address.
A socket-only bind is checked through curl without opening a browser. Direct
startup reports an occupied TCP port and exits; use the TUI to manage listeners.
Stop a direct session with **Ctrl+C**.

## Update, remove and recover

Close the launcher and rerun the README's curl command to update. Files and Bash
syntax are checked in a temporary folder before activation; failures preserve
the active installation. Success removes old managed releases and interrupted
staging folders; cleanup failures leave the new copy active with a warning.
Reinstalling repairs a managed wrapper but refuses an unrelated existing `mir`.

| Data | Location |
| --- | --- |
| Installed command | `~/.local/bin/mir` |
| Program releases | `${XDG_DATA_HOME:-$HOME/.local/share}/mir.cpp/releases/` |
| Active program link | `${XDG_DATA_HOME:-$HOME/.local/share}/mir.cpp/current` |
| Paths and profiles | `${XDG_CONFIG_HOME:-$HOME/.config}/mir.cpp/` |
| Managed llama.cpp builds and log | `${XDG_DATA_HOME:-$HOME/.local/share}/mir.cpp/llama.cpp/` |

If Mir.cpp settings do not yet exist, startup imports `llama-launcher` from the
same configuration parent using a temporary copy and atomic activation. Originals
are preserved; existing Mir.cpp settings are never merged or overwritten. Import
failure stops startup with an error; correct permissions and retry. Configuration
files are read as data, never sourced or evaluated.

To remove the installed launcher, stop its server and close it, then run:

```bash
mir --uninstall
```

Confirm with `y` or `yes`; Enter cancels. Use `mir --uninstall --yes` without a
prompt, or `~/.local/bin/mir --uninstall` if the command is not on PATH. Older
installations may need an update to gain this command. Removal uses paths recorded
at installation, independent of later HOME/XDG changes. It preserves models,
llama.cpp builds, saved settings, dependency packages and unrelated files.
It verifies the command ownership marker and target before removal and does not
stop a running launcher or server.

Installation and removal share a nonblocking `flock` lock, released on exit or
interruption. The small `.install.flock` file and containing directories remain
for reuse; legacy `.install.lock` directories are ignored. Permission failures
never trigger sudo; correct permissions and retry, or reinstall to repair a
partial removal.

## Common problems

- **Menu missing or clipped:** use a terminal, install `dialog` and allow at least 80×24 characters.
- **No models found:** check **Folders → Models folder** for GGUF files, including subfolders.
- **llama-server missing:** select a compiled llama.cpp folder or use **Install / update llama.cpp**. Direct startup can use `MIR_LLAMA_CPP_DIR`.
- **Build failed:** inspect **View build log**, network access, disk/RAM, developer packages and GPU setup. Try fewer compiler jobs or another published tag. The previous selection remains active.
- **Model fails to load:** inspect **View log**, check llama.cpp model support and try a smaller context or model.
- **Device error:** check the selected server with `/path/to/llama.cpp/build/bin/llama-server --list-devices` (or `bin/llama-server` for package layouts). For Vulkan, also check `vulkaninfo --summary`. Try **Auto** or **CPU only** under **Performance**.

## Development and checks

`mir/mir.sh` is the source entry point. `runtime.sh` detects the OS and selects
Bash; only macOS loads the Bash 3.2-compatible Homebrew bootstrap. `platform.sh`
loads one adapter, then `launcher.sh` explicitly loads shared modules. Runtime
paths resolve from `MIR_ROOT`. Never recursively source every shell file.

| Area under `mir/` | Responsibility |
| --- | --- |
| `lib/runtime.sh`, `lib/platform.sh` | Bootstrap, adapter selection and dependency checking. |
| `lib/platform/` | OS tools, listeners, browser, discovery, memory, atomic moves and build services. |
| `lib/config.sh`, `lib/paths.sh`, `lib/profiles.sh` | Controls, model discovery and persistence. |
| `lib/server.sh`, `lib/processes.sh`, `lib/memory.sh` | Arguments, lifecycle, listener safety and live memory telemetry. |
| `lib/build.sh`, `lib/gguf.py` | Managed releases and optional GGUF metadata filtering. |
| `lib/tui/`, `dialogrc` | Navigation, terminal geometry and theme. |
| `tests/helpers/`, `tests/platform/`, `tests/native/` | Isolated helpers, adapter fixtures and real OS checks. |

Modules define functions without side effects on import. Shared logic does not
choose OS commands, invoke Homebrew or parse native process data. Adapters expose
`platform_required_tools`, `platform_dependency_hint`, `platform_browser_command`,
`platform_open_url`, `platform_find_models`, `platform_move`, `platform_timeout`,
`platform_memory_style`, `platform_memory_snapshot`, `platform_multi_gpu_ui` and
`platform_listeners`.
Build services are `platform_build_backends`, `platform_build_flags`,
`platform_start_worker`, `platform_build_probe`, `platform_gpu_build_note` and
`platform_ensure_dependencies`.

Call state-returning services in the current shell: listeners set `LISTENERS` and
`PIDS`; memory snapshots set `RAM_AVAILABLE` in MiB (empty means unknown, zero is a
valid measurement). Memory styles are `margins` for separate RAM/device pools,
`system` for approximate RAM-only readings. Telemetry formatting and pagination
stay shared. Listener inspection failures return failure; missing
optional probes do not block startup. Atomic moves accept source, destination
and `replace` or `no-clobber`. `load_platform` accepts `linux` or `macos` and rejects
mixing adapters.

Run suites from the repository root:

```bash
bash mir/tests/run.sh common
bash mir/tests/run.sh linux
bash mir/tests/run.sh macos
bash mir/tests/run.sh all
```

`common` checks architecture, generated installer, Bash syntax, ShellCheck when
available, configuration/profiles, arguments, memory and real dialog geometry.
`linux` and `macos` add adapter, managed-build and installer fixtures plus native
checks for the current host. `all` runs all suites. The runner selects compatible
Bash on macOS. Linux suites need no macOS files or Homebrew; unavailable native
checks report **SKIP**. CI runs shared and platform checks independently on Ubuntu
and macOS.

Tests require Python 3 and launcher dependencies; geometry checks use real
`dialog --trace`. Core tests use a fake adapter and isolated commands; adapter
contracts run in separate Bash processes. Tests use temporary settings and owned
sockets without loading real models or stopping existing services. For optional
comparison with an older standalone launcher, run
`bash mir/tests/regression.sh /path/to/old-launcher.sh`. Direct test scripts need
Bash 4.4 or newer on PATH.

The standalone `mir/sh/install.sh` is generated. Edit `install-core.sh`, the
canonical bootstrap or adapters, then regenerate and commit the bundle:

```bash
bash mir/sh/build-install.sh
bash mir/sh/build-install.sh --check
```

Generation needs Bash 4.4 or newer; on macOS use
`"$(brew --prefix bash)/bin/bash" mir/sh/build-install.sh` if necessary, adding
`--check` to verify. The bundle includes only installer-required adapter functions
and remains compatible with Bash 3.2 bootstrap. Installed runtime files include
only the selected adapter. Users need no generation step.

The optional `bash mir/tests/download.sh` network check installs and updates in a
temporary HOME using real GitHub downloads, checks preserved settings and removes
the program if that published version supports removal. It tests published
`main`, which can differ from the checkout; local installer fixtures cover local
removal behavior.

Automated fixtures and native OS checks do not establish GPU inference coverage.
Recorded Apple M4 smoke checks used Auto, CPU only and explicit Metal with
`stories260K.gguf`, covering health, Web UI, completion and shutdown. They do not
establish performance, large-model capacity or Intel Mac coverage. NVIDIA CUDA
hardware validation remains pending.
