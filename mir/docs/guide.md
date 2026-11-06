# Mir.cpp user guide

For platform support, installation and first launch, see the [README](../../README.md).
This guide covers configuration, maintenance and development.

## Dependencies and source startup

The installer offers missing launcher packages through apt on Ubuntu/Debian and
Homebrew on macOS. Confirmation uses the terminal, including with `curl | bash`.
Declining, installation failure or a missing terminal stops the operation before
replacing an existing Mir.cpp installation. Only apt commands may use sudo;
Mir.cpp and managed llama.cpp builds run as your user.

For manual installation on Ubuntu/Debian:

```bash
sudo apt-get update
sudo apt-get install bash curl ca-certificates coreutils findutils grep util-linux tar gzip dialog iproute2 procps xdg-utils
```

The launcher requires Bash 4.4 or newer. `xdg-utils` enables automatic browser
opening; without it, open the displayed address manually. Assisted installation
installs missing required packages without removing packages or performing a
system-wide upgrade. Other Linux distributions require equivalent tools and
build libraries installed manually.

On macOS, install Homebrew separately, then install launcher packages manually if
preferred:

```bash
brew install bash coreutils findutils dialog flock
```

The installer can start with system Bash 3.2 and may ask separately for compatible
Bash before the remaining packages. Source and installed-command startup only
check dependencies. The bootstrap discovers Homebrew through `brew --prefix` or
its standard Apple Silicon/Intel locations and selects Bash 4.4 or newer. It adds
the Homebrew bin directory only to the program process and its children,
preserving command precedence. It never changes your login shell or shell files.
Homebrew package installation uses neither sudo nor an explicit package update.

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

The main screen shows the current configuration, model, context,
device, port status and estimated free memory. Long names are shortened only for
display. All seven actions fit an 80×24 terminal:

| Menu | Purpose |
| --- | --- |
| Launch server | Start the model with the displayed settings. |
| Model settings | Select a model, context, KV Cache types and generation settings. |
| Performance | Select devices, CPU threads, GPU layers and prompt processing. |
| Server & port | Edit the port, refresh status, inspect or stop listeners. |
| Saved configurations | Load, update, save or delete settings. |
| Folders | Manage llama.cpp builds and select llama.cpp and models folders. |
| Quit | Exit the launcher. |

After launch, the screen shows **Loading**, then **Ready** when the health check
succeeds. The browser opens at the displayed address, normally
`http://127.0.0.1:9931`. Open it manually if needed. **View log** shows server
output; **Stop server** stops the server and exits the launcher. Closing the
browser leaves the server running. Server logs are temporary and removed on exit.

The theme in `dialogrc` applies only to Mir.cpp. Colors and font follow your
terminal; status is also shown in text. Dialog windows recenter when resized.
Inherited `LINES`, `COLUMNS` and `DIALOGOPTS` are ignored only for dialog calls so
external sizing options cannot displace the menus.

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

Changing the models folder refreshes the list and retains the selected model if
present; otherwise it selects the first available model. Empty folders are saved
with a message. Add models and select the folder again to refresh. Missing paths
or models leave the menu open for correction; launching requires an executable
server and a readable model.

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
util-linux, coreutils and OpenSSL/curl development libraries. Vulkan adds
`libvulkan-dev`, `glslc`, `spirv-headers`, `vulkan-tools` and Mesa Vulkan drivers.
CUDA uses an existing `nvcc`, or installs `cuda-toolkit` from an already configured
NVIDIA repository when available, otherwise `nvidia-cuda-toolkit`. Package and
compiler compatibility depend on the distribution. Setup does not add external
repositories, replace kernel GPU drivers or reboot. See the
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
compiler jobs (default 2). Published releases may include pre-releases; latest
does not imply stable. More jobs use more RAM and do not affect inference threads.
The selected tag is resolved to a recorded commit and built in a new directory.
For releases using downloaded Web UI assets, Mir.cpp requires the archive for
that exact release and verifies its SHA-256 digest. Missing or mismatched assets
block activation; older releases use their bundled UI.

**View log** shows build output. **Cancel build** or **Esc** asks before
cancellation; a lock prevents concurrent managed builds. Before activation,
Mir.cpp checks version/help, device discovery and Web UI assets. GPU builds
require an accelerator. The optional `llama-fit-params` planner is also built when
upstream provides it. These checks do not validate inference or model capacity.

A successful build saves its path for TUI and direct startup. Failed or canceled
builds preserve the previous selection. **Check for updates** offers the latest
published tag with the current managed backend; use **Install / change build** to
change backend or choose a version. **Restore previous build** selects the
preceding managed build after confirmation, without network access or rebuilding.
External source trees, models, profiles and browser settings are preserved.

Builds are retained under
`${XDG_DATA_HOME:-$HOME/.local/share}/mir.cpp/llama.cpp/builds/`, each with source,
build tree and `mir-build.conf`. Failed builds are removed. **View build log**
opens `llama.cpp/build.log`, retained until the next attempt. When reclaiming disk
space, keep builds referenced by saved paths or running sessions. Launcher
updates and removal preserve managed builds and system dependency packages.
Use the same `XDG_DATA_HOME` to manage them later.

## Model and performance settings

Under **Model settings**, choose a model, context, KV Cache types and generation settings.
**Auto** context omits the context argument, leaving native model, environment
and memory choices in effect. Fixed choices range from 4K to 256K (1K = 1024
tokens). **Custom** accepts `auto` or 0–2147483647 tokens; `0` requests full model
context and may need much more memory. Context includes input and output. Available context sizes depend
on the model and installed llama.cpp.

### KV Cache

Open **Model settings → KV Cache** to select **K (keys)** and **V (values)**
separately. Both default to **Q4_0**, explicitly passed as `--cache-type-k q4_0`
and `--cache-type-v q4_0`. These types affect cached attention data, not the
quantization of the GGUF model weights.

The primary choices are **Q4_0** for lower memory use, **Q8_0** for less aggressive
quantization and **F16** for an unquantized cache using more memory. Lower
precision may affect output quality; compare your own tasks and context sizes.
**Other formats** lists additional types advertised by the selected server. For
example, build b12138 advertises F32, BF16, Q4_1, IQ4_NL, Q5_0 and Q5_1 as well.
Only advertised types are offered. If probing fails, existing values are kept.

Advertised types are parser capabilities, not a guarantee for every model or
backend. Quantized V requires Flash Attention; the installed b12138 build enables
it when automatic. Mir.cpp leaves Flash Attention automatic and preserves native
overrides. Explicitly disabling it can make quantized V fail. Mixed K/V types may
be unsupported or slower; use matching types when unsure. Some architectures
require matching K/V types. No type or precision is silently substituted by
Mir.cpp. Native compatibility errors remain available in **View log**; adjust the
cache types or select another build before retrying.

Cache choices persist in named configurations and are passed to the memory
planner too. A planner that cannot advertise both selected types leaves estimates
unavailable, without blocking launch or live memory readings.

### Performance

Start with **Auto** and **Default** under **Performance**:

| Option | Behavior |
| --- | --- |
| Device | **Auto**, **CPU only**, or a device discovered through `--list-devices`. CPU only disables GPU layers. |
| CPU threads | **auto** or 1–2147483647. More threads are not always faster. |
| GPU layers | **auto**, **all**, or 0–2147483647. Auto leaves native defaults in effect; all can exceed memory. CPU only shows **Ignored (CPU only)** and retains the chosen value for other devices. |
| Prompt processing | **Default** omits batch overrides. **Low memory** uses `--batch-size 512 --ubatch-size 128`; **Large batch** uses `--batch-size 2048 --ubatch-size 1024`. |

Batch sizes affect input processing, not the maximum answer length. Larger
batches need more memory and do not guarantee faster generation. CPU and GPU can
share memory on integrated graphics. Flash Attention stays automatic. Change one
setting at a time and compare equivalent model, context and input workloads.
If loading fails, try Auto/Default or a smaller context.

Before launch, Mir.cpp checks requested controls against server help and checks
explicit devices when discovery succeeds. Unsupported choices produce an error;
the TUI remains available for correction. Help/device probes have 15-second
limits. Without GNU `timeout` (`gtimeout` on macOS), probes are skipped and the
server reports startup errors. Auto and CPU only remain selectable.

## Memory estimates

Before launch, a compact line shows estimated remaining memory, for example
`Est. free GiB: RAM 16.3 | GPU 1.5`. While running it shows **Free GiB**.
Negative estimates indicate a predicted shortfall; **N/A** means unknown.
On Linux, **+N** indicates pools available through **Next memory**.

Forecasts require `llama-fit-params` beside the server, bounded commands and a
planner capable of reproducing effective server slots and KV-cache layout,
including native environment overrides. They include model, context/state and
compute allocations without running inference. Unsupported or malformed output
leaves the forecast unavailable and never blocks launch. Linux may show
**Est. free: unavailable**; live readings remain independent.

Linux uses available system RAM and device reports. macOS shows approximate
system RAM with a `~` marker, using native `vm_stat` free, inactive and speculative
pages and the reported page size, following
[psutil's available-memory calculation](https://github.com/giampaolo/psutil/blob/master/psutil/arch/osx/mem.c).
On Apple Silicon, CPU/Metal allocations are subtracted once from shared RAM.
On other Macs, forecasts involving separate accelerator memory show **N/A**.
GPU probes are never treated as system-wide available RAM on macOS.

Estimates refresh after configuration changes and remain advisory. Reclaimable
memory, placement, memory mapping, runtime overhead, projectors and extra server
arguments can differ from the plan. They do not guarantee that a model fits or
prevent swapping. The compact line omits RSS, pressure, swap, total RAM and device
budgets; no utilization monitoring, conversation recording or telemetry uploads
are performed.

## Generation settings

Open **Model settings → Generation → Preset**:

| Preset | Temperature | Top-P | Top-K | Min-P |
| --- | --- | --- | --- | --- |
| Default | Native | Native | Native | Native |
| Focused | 0.6 | 0.95 | 20 | 0 |
| Exploratory | 1 | 0.95 | 20 | 0 |
| Min-P | 1 | 1 (disabled) | 0 (disabled) | 0.05 |
| Custom | Edit individual sampling values | | | |

Default omits sampling arguments. The three explicit presets set repeat penalty
to 1 and presence/frequency penalties to 0. They are manual starting points, with
no model-family detection or quality guarantee. Applying one preserves context,
performance, seed and output length. The label follows the exact
sampling values; other combinations show **Custom**.

**Sampling parameters** edits all seven values. Temperature controls randomness;
Top-P, Top-K and Min-P filter token choices. Penalties can reduce repetition but
also harm useful repeated text. Lower temperature does not guarantee accuracy.
Enter **auto** to use native defaults. Decimal inputs require a dot, a leading
digit and at most nine decimal places. Numeric ranges appear in the CLI reference
below.

**Seed** accepts **auto**, **-1** or 0–4294967295; -1 and 4294967295 select random.
A fixed seed helps comparisons but does not guarantee identical results across
hardware or settings. **Maximum output tokens** accepts **auto**, **-1** for no
fixed generation limit, or 0–2147483647. Zero evaluates input without generating
an answer. This limit is separate from context; short limits can truncate output.

Terminal choices take effect at server launch. Browser chat settings and API
requests can override server defaults. Clear explicit browser sampling values to
use server defaults; Mir.cpp never changes browser preferences or conversations.
If a server rejects an option, inspect **View log**, update llama.cpp or return
that field to **auto**.

## Saved configurations

After selecting a model and settings, open **Saved configurations**:

| Action | Result |
| --- | --- |
| Load configuration | Restore validated settings and return to the main screen for review, without launching. |
| Update current | Replace the current profile after confirmation. |
| Save as new configuration | Save under a name; confirm before replacing an existing profile. |
| Delete configuration | Remove a profile after confirmation. Current settings are kept. |

Names allow 1–80 letters, digits, spaces, dots, underscores or hyphens, starting
with a letter or digit. Nothing is saved automatically. Loading or saving sets
the current profile for the launcher session. **Modified** appears only while
its values differ from the saved values. Deleting the current profile changes
the label to **Not saved**.

Profiles are plain `key=value` files under
`${XDG_CONFIG_HOME:-$HOME/.config}/mir.cpp/profiles/`; back up this folder to retain
them. Each stores 18 fields: model, context, port, device, threads, GPU layers,
prompt processing, K/V cache types and nine generation values. All fields are required. Partial
or invalid profiles and missing models leave current settings unchanged. Saved
devices and cache types are checked against the current server before launch.

Profiles exclude conversations, trailing arguments and unrelated environment
settings. Global folder paths are stored separately; changing the models folder
can still mark a profile Modified if it changes the selected model.

## Occupied ports

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

Saved folders apply to direct startup. Override them for one invocation with
`MIR_LLAMA_CPP_DIR` and `MIR_MODELS_DIR`. Choosing a folder in the TUI saves the
currently displayed paths.

| Control | Accepted values; default |
| --- | --- |
| `MIR_LLAMA_CPP_DIR`, `MIR_MODELS_DIR` | Folder paths; saved paths when available. |
| `MIR_CTX_SIZE` | `auto` or 0–2147483647; `auto`. Zero requests full model context. |
| `MIR_PORT` | 1–65535; `9931`. |
| `MIR_HOST` | Explicit server bind address; otherwise native host settings or `127.0.0.1`. |
| `MIR_DEVICE` | `auto`, `none` (CPU only), or comma-separated discovered device names; `auto`. |
| `MIR_THREADS` | `auto` or 1–2147483647; `auto`. |
| `MIR_GPU_LAYERS` | `auto`, `all` or 0–2147483647; `auto`. |
| `MIR_PROMPT_PROCESSING` | `auto`, `low-memory`, `large-batch`; `auto`. |
| `MIR_CACHE_TYPE_K`, `MIR_CACHE_TYPE_V` | Lowercase type advertised by the server; `q4_0` for each unless configured otherwise. |

Auto/Default omits the corresponding option and allows native llama.cpp settings
to apply. Multi-device selections also persist in profiles. For example, use the
CPU, four threads and smaller input chunks:

```bash
MIR_DEVICE=none MIR_THREADS=4 MIR_PROMPT_PROCESSING=low-memory \
    ~/.local/bin/mir "/path/to/model.gguf"
```

For cache types, `MIR_CACHE_TYPE_K` and `MIR_CACHE_TYPE_V` override the respective
native `LLAMA_ARG_CACHE_TYPE_K` and `LLAMA_ARG_CACHE_TYPE_V` values. If neither is
set, Mir.cpp uses `q4_0`. Empty values are invalid. K/V types are always passed
explicitly; trailing native arguments can override either component. For example:

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
these options are not inferred from filenames or saved in profiles. Sampling
arguments are excluded from memory planning.

Legacy `LLAMA_*` launcher aliases remain supported: replace the `MIR_` prefix
with `LLAMA_`, except `MIR_LLAMA_CPP_DIR` maps to `LLAMA_CPP_DIR` and the new cache
controls use only the native aliases described above. Explicitly set
`MIR_*` values take precedence even when empty and are validated. Empty legacy
values retain fallback defaults for paths and basic controls; empty individual
generation aliases are validated as invalid. Native `LLAMA_ARG_*` variables
remain unchanged; explicit trailing arguments take precedence.

Endpoint checks, readiness and browser opening follow effective `--host` and
`--port` arguments, including IPv6. Wildcard binds use a local browser address.
A socket-only bind is checked through curl without opening a browser. Direct
startup reports an occupied TCP port and exits; use the TUI to manage listeners.
Stop a direct session with **Ctrl+C**.

## Update, remove and recover

Close the launcher before updating. Run the README's curl command again to
replace program files. Downloads and Bash syntax are checked in a temporary
folder before activation; failures preserve the active installation. Successful
updates remove old installer-managed releases and interrupted staging folders.
Cleanup failures are warnings and leave the new copy active. A managed command
wrapper can be repaired by reinstalling; an unrelated existing `mir` is refused.

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
- **Build failed:** inspect **View build log**, network access, disk/RAM, developer packages and GPU drivers. Try fewer compiler jobs or another published tag. The previous selection remains active.
- **Model fails to load:** inspect **View log**, check llama.cpp model support and try a smaller context or model.
- **Device error:** check the selected server with `/path/to/llama.cpp/build/bin/llama-server --list-devices` (or `bin/llama-server` for package layouts). For Vulkan, also check `vulkaninfo --summary`. Try **Auto** or **CPU only** under **Performance**.

## Development and checks

`mir/mir.sh` is the source entry point. `runtime.sh` detects the OS and selects
Bash; only macOS loads the Bash 3.2-compatible Homebrew bootstrap. `platform.sh`
loads one adapter, then `launcher.sh` explicitly loads shared modules. Runtime
paths resolve from `MIR_ROOT`. Never recursively source every shell file.

| Area under `mir/` | Responsibility |
| --- | --- |
| `lib/runtime.sh`, `platform.sh` | Bootstrap, adapter selection and dependency checking. |
| `lib/platform/` | OS tools, listeners, browser, discovery, memory, atomic moves and build services. |
| `lib/config.sh`, `paths.sh`, `profiles.sh` | Controls, model discovery and persistence. |
| `lib/server.sh`, `processes.sh`, `memory.sh` | Arguments, lifecycle, listener safety and memory planning. |
| `lib/build.sh`, `lib/gguf.py` | Managed releases and optional GGUF metadata filtering. |
| `lib/tui/`, `dialogrc` | Navigation, terminal geometry and theme. |
| `tests/helpers/`, `tests/platform/`, `tests/native/` | Isolated helpers, adapter fixtures and real OS checks. |

Modules define functions without side effects on import. Shared logic does not
choose OS commands, invoke Homebrew or parse native process data. Adapters expose
`platform_required_tools`, `platform_dependency_hint`, `platform_browser_command`,
`platform_open_url`, `platform_find_models`, `platform_move`, `platform_timeout`,
`platform_memory_style`, `platform_memory_snapshot` and `platform_listeners`.
Build services are `platform_build_backends`, `platform_build_flags`,
`platform_start_worker`, `platform_build_probe` and `platform_ensure_dependencies`.

Call state-returning services in the current shell: listeners set `LISTENERS` and
`PIDS`; memory snapshots set `RAM_AVAILABLE` in MiB (empty means unknown, zero is a
valid measurement). Memory styles are `margins` for separate RAM/device pools,
`shared` for one physical pool and `system` for RAM-only forecasts. Planning and
pagination stay shared. Listener inspection failures return failure; missing
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
`bash mir/tests/regression.sh /path/to/old-launcher.sh` with Bash 4.4 or newer.

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
