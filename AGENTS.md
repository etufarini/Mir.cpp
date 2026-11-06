# Instructions for mir.sh

## Scope and purpose

These instructions apply to `mir/mir.sh`, `README.md`, these instructions and files created specifically to support the launcher.

Keep the visible repository root limited to `README.md`, `AGENTS.md` and the `mir/` software folder. Keep the source entry point and `dialogrc` together inside `mir/`, modules in `mir/lib/`, tests in `mir/tests/`, the installer in `mir/sh/install.sh`, and the user guide and screenshots in `mir/docs/`. Resolve runtime paths from `MIR_ROOT`, independently of the working directory. Keep the installed `mir` command and existing installation layout compatible when reorganizing source files.

The script is a Bash launcher for the local llama.cpp server and its browser-based Web UI. Its `dialog` terminal interface discovers GGUF files under a user-selected models directory and lets the user select a model and configure context size, generation, port and performance settings before starting the server on CPU or a backend supported by the installed llama.cpp build. While running, it shows server status and offers log viewing and server shutdown. A model path and environment variables allow direct startup without the TUI. All script comments, menus, messages and project documentation must be in English.

## Platform boundaries

Keep shared launcher behavior in `mir/lib/` and system operations in `mir/lib/platform/linux.sh` and `macos.sh`. Detect the OS in `runtime.sh`, then load only the selected adapter through `platform.sh`. Keep Homebrew discovery and the pre-4.4 Bash bootstrap in `platform/macos-bootstrap.sh`; Linux startup must work without any macOS files or Homebrew commands. Shared configuration, profiles, model/device arguments, TUI, port status formatting, shutdown confirmations and PID identity checks must not branch on the OS. Use the platform contract for listeners, browser opening, bounded commands, model discovery, atomic activation, memory presentation style and native memory snapshots. Adapters define functions without effects on import; unsupported OS values and attempts to mix adapters must fail clearly.

Use explicit module loading through `lib/launcher.sh` in the entry point and isolated test helpers; never recursively source all shell files. Core tests use `tests/helpers/fake.sh`; platform contract tests live in `tests/platform/` and real OS tests in `tests/native/`. Keep `bash mir/tests/run.sh common` and `linux` usable on Linux without macOS dependencies; `all` additionally runs cross-platform fixtures and any native tests available on the current host. Keep Ubuntu and macOS CI checks independent and report skipped native checks honestly.

Treat `mir/sh/install.sh` as a generated standalone artifact. Edit `install-core.sh`, the canonical bootstrap or adapters, regenerate with `bash mir/sh/build-install.sh`, and verify with `--check`. The bundle must include only installer-required adapter functions, keep the existing curl URL and installation layout, and retain Bash 3.2 bootstrap compatibility. Do not hand-edit generated copies of platform logic.

## Release scope

The launcher targets Linux with CPU, Vulkan and CUDA builds of llama.cpp, and macOS with CPU and Metal builds. CUDA compatibility is expected from the existing generic device support, but validation on NVIDIA hardware is still pending; do not describe it as hardware-verified until those checks pass. macOS support requires Bash 4.4 or newer and the documented Homebrew launcher dependencies. Bootstrap with syntax accepted by macOS Bash 3.2, automatically finding compatible Homebrew Bash and tools for source, piped installer and installed-command startup. Never require users to change their login shell or shell configuration; dependency PATH additions must stay within the program process and preserve existing command precedence. Distinguish simulated tests, native device discovery and actual inference validation; do not claim hardware coverage beyond the checks performed. Keep device discovery delegated to the installed llama.cpp; the documented release scope must not introduce hardcoded backend names or restrict otherwise valid model and device arguments.

## TUI organization

Keep the main menu in this order: Launch server, Model settings, Performance, Server & port, Saved configurations, Folders and Quit. Initially select Launch server, preserving all launch validation. Show the current configuration, model, compact context, device and port status above these entries. Hide internal menu tags and display readable values while preserving stored values and command-line arguments. Keep menus readable at 80×24 characters. Group model selection, context and Generation under Model settings; group port editing, status refresh and stopping an occupying process under Server & port. Keep complete process details available there and in shutdown confirmations. Order saved configuration actions as Load configuration, Update current, Save as new configuration, Delete configuration and Back, keeping deletion after the other operations.

Use descriptive screen titles, Back controls in submenus and current-value selection where available. Remember the selected entry when returning from a setting or submenu. Loading a profile must still return to the main screen for review. Keep the running server screen's status, address, log access and Stop server control.

## Visual style

Keep the theme in `dialogrc` beside the script and apply it only to dialog invocations through `DIALOGRC`, never to the user's global configuration. Reflect the logo with standard terminal colors: a black background, light body text, white-on-blue titles, indicators, selected items and active buttons, and light thin borders. Use bold white for inactive button shortcuts. Blue identifies branding and focus; errors and status must remain explicit in text. Use the compact `MIR.CPP / STATION CONTROL` backtitle throughout, with readable descriptive screen titles and no decorative art. Keep body text in normal case, reserve uppercase for branding and existing status labels, and leave font selection to the terminal. Use flat borders without shadows, padded titles and consistent label/value alignment. Preserve spacing centrally with `--no-collapse`; keep the same style for menus, inputs, confirmations and the running server screen. Status must remain explicit in text, including FREE, IN USE, Modified, Loading and Ready; never rely on color alone. Use the existing shared color definitions rather than duplicating them. Exact shades follow the terminal palette; do not redefine that palette to reproduce the logo's RGB values. Preserve 80×24 readability and all existing navigation and safety controls. Do not add runtime dependencies beyond the documented platform requirements.

## Configurable paths

Keep llama.cpp and models paths configurable through the Folders menu, without fixed project-relative paths. Use a menu-based folder browser: Up/Down selects, Enter opens a directory, Parent folder goes up, Enter path accepts a typed or pasted path, and Use this folder separately confirms the current directory. Display the current path and brief instructions. Sort directories alphabetically, hide dot-prefixed directories initially and provide a Show/Hide hidden folders action. Back/Esc cancels without saving; manual paths must still allow hidden directories. Validate readable directories; the llama.cpp folder must contain executable `build/bin/llama-server` or `bin/llama-server`, preferring the source-build layout when both exist. Save accepted changes atomically in `${XDG_CONFIG_HOME:-$HOME/.config}/mir.cpp/paths.conf`, separately from model profiles. Read this file as data, never source or eval. If saving fails, keep previous settings.

Allow first-time configuration and correction of missing or invalid paths from the TUI. Empty model folders must show a clear message without exiting. Refresh recursive GGUF discovery when the folder changes and retain the selected model if still listed. Block launch with a clear message when the server or model is unavailable. Direct startup uses saved paths, with `MIR_LLAMA_CPP_DIR` and `MIR_MODELS_DIR` overrides supported.

## Port and process management

Check whether the selected TCP port is occupied when showing the configuration menu, after changing the port and immediately before startup. Show process IDs, names and owners when available. Unidentified listeners still block startup. Direct startup must report an occupied port and exit.

Never automatically terminate an existing process. Before stopping listeners, show the affected processes and request explicit confirmation. Attempt normal shutdown with SIGTERM first; SIGKILL requires a separate confirmation. Check process identity before signalling to reduce the risk of acting on a reused PID. Report permission failures clearly and do not automatically elevate privileges. Preserve the running session's Stop server control and cleanup of its own server process.

## Memory presentation

Keep a compact advisory free-memory line on Linux and macOS behind adapter services, without OS branches in shared modules. Use Est. free GiB before launch and Free GiB while running. On macOS, show approximate available system RAM with a ~ marker, using native vm_stat free, inactive and speculative pages and the reported page size. On Apple Silicon, subtract the planner's CPU/Metal allocations from the shared physical pool once for the prelaunch forecast; on other Macs, leave accelerator forecasts unknown rather than treating separate GPU memory as RAM. Never describe a separate Metal probe's process-local allocation margin as system-wide free memory. Do not show RSS, pressure, swap, total RAM or device budgets in the compact telemetry. Only estimate when the planner can reproduce the effective server slots and KV layout, including native environment overrides; otherwise leave the forecast unavailable while retaining live measurements. Missing, unsupported or malformed measurements show N/A and never block launch. Preserve Linux's device-pool pagination, 80×24 readability and the Linux/macOS architecture boundary. Keep the existing Linux screenshots; do not add macOS screenshots.

## Portable performance settings

Keep the Performance submenu limited to device selection, CPU threads, GPU layers and prompt processing. Use llama.cpp's automatic choices by default: do not hardcode a GPU name, CPU thread count or a hardware-specific profile. Discover selectable devices through the installed server's `--list-devices`; keep Auto and CPU only available even when no accelerator is detected. CPU only must disable GPU layers, regardless of the selected layer count.

Preserve the same controls for direct startup through `MIR_DEVICE`, `MIR_THREADS`, `MIR_GPU_LAYERS` and `MIR_PROMPT_PROCESSING`. Validate thread and layer counts before launching. Automatic controls omit their corresponding arguments and allow native llama.cpp configuration to apply; explicit pass-through arguments remain supported.

Prompt processing choices are Default (no batch overrides), Low memory (`--batch-size 512 --ubatch-size 128`) and Large batch (`--batch-size 2048 --ubatch-size 1024`). Explain the memory tradeoff and distinguish input processing from answer generation. Leave Flash Attention automatic and do not introduce cache quantization or model-specific tuning as defaults. Never promise a universal speed improvement; compare equivalent workloads before making performance claims.

## Generation settings

Keep Default, Focused, Exploratory, Min-P and Custom sampling choices under Model settings → Generation. Default omits sampling arguments. Focused uses temperature 0.6, Top-P 0.95, Top-K 20 and Min-P 0; Exploratory changes temperature to 1; Min-P uses temperature 1, Top-P 1, Top-K 0 and Min-P 0.05. All three explicit presets set repeat penalty to 1 and presence/frequency penalties to 0. Treat presets as manual starting points, never universal quality guarantees or automatic model-family rules. Preserve context, device and performance settings when selecting a preset.

Allow custom sampling values and separate seed and maximum output token controls. Applying a sampling preset preserves seed and output length. Derive the preset label from actual sampling values; persist values rather than a potentially stale label. Validate numeric inputs without evaluating them as code. Keep automatic values unset on the server command line and sampling arguments out of memory planning. Support direct startup through MIR_GENERATION_PRESET and individual MIR_* generation controls, with legacy LLAMA_* aliases and explicit trailing arguments preserved. Explain that browser chat overrides can replace server defaults; never overwrite browser preferences or conversations.

## Saved configurations

Keep named profiles in `${XDG_CONFIG_HOME:-$HOME/.config}/mir.cpp/profiles/`, one plain `key=value` file per profile. Read profiles as data; never use source or eval. Save the model path, context, port, device, threads, GPU layers, prompt processing, temperature, Top-P, Top-K, Min-P, repeat penalty, presence penalty, frequency penalty, seed and maximum output tokens. Require all sixteen fields; do not support previous profile formats. Do not persist conversations, arbitrary trailing arguments or unrelated environment settings.

Validate every field and the model file before applying any loaded settings; failures must preserve all current settings. Loading returns to the main menu without launching, and existing port checks still apply. Confirm replacement and deletion. Use safe profile names and atomic writes, report storage failures, and preserve direct startup behavior. Keep the menu and documentation in English.

Show the current profile name (or Not saved) in the main summary and Saved configurations menu. Track the exact saved values of all sixteen profile fields to show Modified only when they differ. Successful load and Save as set the current profile; successful Update current refreshes it after explicit overwrite confirmation. Share serialization between saving and comparison. Failed or canceled operations must preserve tracking and saved files. Deleting the current profile clears its association only after successful deletion while preserving current settings. Track the association for the running launcher session only; global paths remain separate, though selecting another model through folder discovery changes the profile's model field.

## User documentation

Keep `README.md` in English, short, practical and understandable without programming knowledge. Aim for 80–100 lines or fewer and keep the first-launch instructions easy to scan. Lead with what Mir.cpp does, then cover Linux and macOS support and CUDA validation status, minimal bootstrap prerequisites, assisted dependency installation on Ubuntu/Debian and macOS, quick installation with curl, starting `mir`, first-time folder selection and model selection through the TUI. Present the menus as the normal workflow: users choose discovered GGUF files inside Model settings rather than typing a model path into a command. Keep direct startup, environment overrides and pass-through arguments in the advanced user guide, preserving their functionality and compatibility. Keep complete manual dependency commands in the advanced guide. Distinguish launcher dependencies from the separate llama.cpp build, GPU drivers and model files; link to the official llama.cpp build instructions instead of duplicating them.

Include two readable screenshots captured from the real terminal interface: the main menu and Model settings. Store them under `mir/docs/screenshots/`, use relative Markdown links, provide descriptive alt text and a short explanatory caption, and update them when the pictured interface changes. Do not fabricate interface elements, results or server readiness; omit unrelated desktop content and private paths. Keep images supplementary to usable text instructions.

Keep installation steps, paths, menu labels, defaults and examples aligned with the actual script and installer. Explain port shutdown confirmations, model capability and memory limits, and the distinction between terminal configuration and browser chat in a few plain sentences. Do not claim that every model supports every context size. Put detailed menus, environment controls, sampling tables, maintenance, troubleshooting and development checks in `mir/docs/guide.md`, linked once from the README. Avoid a manual table of contents, exhaustive option tables, repeated explanations and implementation details in the README.

## General model compatibility

The launcher MUST WORK WITH EVERY GGUF MODEL supported by the installed llama.cpp version and the available hardware. Model architecture, context limits, chat templates and memory requirements vary: respect those capabilities and report unsupported configurations clearly.

Do not hardcode behavior for a particular model, family, filename or directory layout. Do not assume that every model supports the same context length. Preserve configuration options so other GGUF models can be used without editing the script. A model that exceeds hardware resources or is unsupported by llama.cpp cannot be made compatible by the launcher alone.

## Mandatory user approval before changes

EVERY MODIFICATION MUST WAIT FOR THE USER'S EXPLICIT APPROVAL BEFORE IT IS APPLIED. This includes changes to the launcher, supporting files and these instructions, as well as renaming or deleting them.

Read-only inspection is allowed. Before editing, present the proposed changes and their purpose, then wait for approval. A general request to investigate, improve or fix the script is not approval of an unreviewed implementation. Approval applies only to the changes presented; additional changes require new approval. An explicit request to create this initial AGENTS.md authorizes its initial creation.

## Mandatory final code elision

At the end of every development task, the developer MUST APPLY CODE ELISION: review the code and remove redundant, unused or unnecessary portions while preserving required functionality, model compatibility and clear error handling.

Include this cleanup in the proposed changes submitted for approval. If further cleanup is discovered after approval, present it and wait for approval before applying it. Do not remove useful validation or configuration merely to shorten the script. If no removable code remains, state that the review found none.

Verify the approved result with Bash syntax checks and ShellCheck when available, plus focused checks appropriate to the changed behavior. Report the changes, verification results and any remaining limitations.

## Mir.cpp identity and compatibility

Use `Mir.cpp` as the product name, `mir.sh` as the main source entry point, `mir` as the installed command, `MIR_ROOT` as the module root, and `MIR_*` for launcher-specific environment controls, including `MIR_LLAMA_CPP_DIR`, `MIR_MODELS_DIR` and `MIR_HOST`. Names describing llama.cpp itself, its executable, arguments and native environment settings must remain accurate. Keep descriptive generic module, function and state names rather than adding unnecessary branding.

Use only `mir.sh` as the source entry point. Centralize launcher-control resolution with precedence `MIR_*`, then legacy `LLAMA_*` aliases. Explicitly set `MIR_*` values take precedence even when empty; retain the existing empty-value behavior of `LLAMA_*` aliases. Keep `LLAMA_CPP_DIR` as the legacy alias of `MIR_LLAMA_CPP_DIR`, and leave native llama.cpp variables such as `LLAMA_ARG_*` unchanged. Read values literally without eval, without altering the environment or leaving stale aliases between initializations.

When `${XDG_CONFIG_HOME:-$HOME/.config}/mir.cpp` is absent, import the previous `llama-launcher` directory. Use a temporary copy and atomic activation, preserving originals and never merging with or overwriting existing Mir.cpp settings. Import failures must be clear and preserve the original data. Installing Mir.cpp creates its own command and data directory; preserve unrelated installations and commands. Old product names may appear only where required for compatibility, migration, documentation of those behaviors and their tests.
