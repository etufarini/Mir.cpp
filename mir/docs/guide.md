# Mir.cpp user guide

For requirements, installation and first launch, see the [README](../../README.md).
This guide covers optional settings, maintenance and development checks.

The first release targets Linux with CPU, Vulkan and CUDA builds of llama.cpp.
CUDA compatibility is expected from the generic device controls, but validation
on NVIDIA hardware is still pending. macOS and Metal support are planned for
the second release. The backend and available devices come from your llama.cpp
build; **Performance → Device** lists the detected devices.

To run from a source checkout, keep the `mir/` folder together and run
`bash mir/mir.sh` from the repository root. The installer is at
`mir/sh/install.sh`; the installed command is `mir`.

## Update or remove

Program files are installed in `~/.local/share/mir.cpp/`, or `$XDG_DATA_HOME/mir.cpp/` when set. The command remains `~/.local/bin/mir`.

Run the same curl installation command again to update or reinstall a clean copy of the program. Downloads are checked in a temporary folder before activation; failed downloads, missing files or invalid Bash syntax keep the previous installation active. After successful activation, old installer-managed copies and interrupted staging folders under `releases/` are removed. A cleanup permission error is reported as a warning while the new copy remains active. Missing or damaged wrappers carrying the Mir.cpp ownership marker are recreated. An unrelated existing `~/.local/bin/mir` command is never overwritten.

Updates preserve model files, llama.cpp and saved settings. Settings use `~/.config/mir.cpp/` (or under `XDG_CONFIG_HOME`). On first launch, if this folder does not exist, settings are copied atomically from `sputnik.cpp`, or from the older `llama-launcher` folder when `sputnik.cpp` is absent. Originals are kept, and existing Mir.cpp settings are never merged or overwritten. Import failures stop startup with a clear error so you can correct permissions and retry. Later changes in Mir.cpp are saved separately from the old settings. Existing Sputnik.cpp installations and commands are kept. Close the launcher before updating.

To remove the installed launcher and its downloaded releases, stop the server,
close the launcher, then run:

```bash
mir --uninstall
```

Confirm with `y` or `yes`; Enter cancels. Without a terminal, use
`mir --uninstall --yes`. If `mir` is not on your PATH, use
`~/.local/bin/mir --uninstall`. Older installations need one update first to gain
this command. Removal uses the paths recorded at installation, even if HOME or
XDG variables have since changed. It keeps models, llama.cpp, saved settings,
previous Sputnik.cpp installations, and unrelated files and symlinks outside
installer-managed release directories. The command must still carry its Mir.cpp
ownership marker and target this installation. Unrecognized or replaced files
are refused. Removal does not stop a running launcher or server for you.

Installation and removal share a lock; concurrent operations are rejected with
a clear message. The lock is released automatically on exit, including after a
forced interruption. The small `.install.flock` file and containing directories
remain after removal so concurrent operations always use the same lock; they do
not prevent reinstallation. Unrelated files are left in place. Legacy
`.install.lock` directories are ignored. The installer and uninstaller use
`flock` from the `util-linux` package. Permission failures are reported without
sudo; correct the permissions and retry, or reinstall to repair a partial removal.

## Using the menu

Use the arrow keys to highlight an item, **Enter** or **Select** to open it, and **Tab** to move between buttons. Menus offer **Select / Back**; the main screen offers **Select / Quit**. Cancel an individual setting with **Back** or **Esc** to keep its previous value. **Quit** or **Esc** on the main screen exits the launcher.

The main screen shows the current configuration and model, context and reasoning on one line, then device, port status and estimated free memory. Long names are shortened in summaries, keeping their beginning and end; stored values are unchanged. Launch server is first; setup and management menus follow. Internal menu codes are hidden to keep the display clear at 80×24 characters. It has seven entries:

| Menu | What it contains |
| --- | --- |
| Launch server | Start the model with the settings shown above. |
| Model settings | Select the GGUF model, context, reasoning and generation settings. |
| Performance | Adjust device, CPU threads, GPU layers and prompt processing. |
| Server & port | Choose the port, refresh its status, view process details or stop its listeners. |
| Saved configurations | Load, save, update or delete named groups of settings. |
| Folders | Choose and remember the llama.cpp and models folders. |
| Quit | Exit the launcher. |

Menus remember the selected entry when you return from an option. Setting selectors highlight the current value when available and use specific screen titles. Each submenu puts its settings and actions before Back. Use **Back** or **Esc** to return from a submenu. Start with **Auto** context and reasoning in **Model settings**. In **Server & port**, the default port is `9931`.

**Auto** context omits the context argument, allowing llama.cpp's native model, environment and memory choices. Fixed choices run from 4K to 256K; **Custom** also accepts smaller contexts, from 1 to 2147483647 tokens. Custom `0` explicitly requests the full model context and can require much more memory than Auto. Not every model supports every size or reasoning mode; automatic fitting is not a guarantee that a model will fit in RAM or GPU memory. Existing profiles keep their saved context.

After you select **Launch server**, loading may take a while. The browser opens when the server is ready. If it does not open, visit the displayed address (normally `http://127.0.0.1:9931`).

The running screen offers **View log** for details and **Stop server** to stop the model and exit. Closing the browser alone does not stop the server. Logs are temporary and are removed when the launcher exits.

The interface follows the Mir.cpp logo palette: a black background, light text, white-on-blue titles, selected items and active buttons, and thin light borders without shadows. A compact MIR.CPP / STATION CONTROL header identifies every screen once; window titles describe the current task, such as **Main menu**, **Model settings** or **Server log**. Aligned summaries separate configuration, model settings and server status, with consistent spacing throughout. Keep the `lib/` folder and `dialogrc` beside the script when moving the launcher; the theme applies only to this launcher. Exact shades and the monospaced font follow your terminal settings; the launcher does not redefine the terminal palette or change fonts. Status labels remain explicit without color, and the menus fit an 80×24 terminal.

## Folder paths

Open **Folders** to change **llama.cpp folder** or **Models folder**. The browser shows the current path, folder actions first and alphabetically sorted directories below. The Select button runs the highlighted action or opens the highlighted directory. Use **Up/Down** and **Enter** to open a folder; **Parent folder** goes up one level. Choose **Use this folder** to confirm the current folder. **Back** or **Esc** cancels without changing the saved path.

Hidden folders are excluded initially; **Show hidden folders** reveals them, and **Hide hidden folders** hides them again. Use **Enter path** to paste or type a path, including a hidden folder. Spaces and `~/` are supported. Entering a path navigates there; choose **Use this folder** afterward to save it.

Select the main llama.cpp folder: it must contain the compiled `build/bin/llama-server`. The models folder is searched recursively. Changing it refreshes the model list immediately and keeps the selected model if it is still listed; otherwise the first available model is selected. Empty folders are accepted with a message; add GGUF files and select the folder again to refresh.

Links to model files and to the selected root folder work; discovery does not descend through linked subfolders. When Python 3 is available, a bounded metadata reader omits recognized multimodal projectors, adapters and later parts of split models. Select the first part, keeping the other parts alongside it. Unknown formats and unreadable metadata stay listed so the installed llama.cpp can decide whether they work. Python is optional; without it, all discovered GGUF files are shown.

Valid changes are saved automatically in `~/.config/mir.cpp/paths.conf` (or under `XDG_CONFIG_HOME`). These paths apply to all profiles and direct startup, separately from named model configurations. If a folder moves, reopen **Folders** to correct it. Missing paths or an empty model list do not close the menu; launching requires an executable server and an existing selected model.

## Performance settings

The main screen uses one compact line, for example `Est. free GiB: RAM 16.3 | GPU 1.5`. Negative values indicate missing memory. `N/A` means unknown; `+N` means more pools are available through the **Next memory** button, shown only when needed. The line is limited to the space inside the box. All seven main menu actions are visible at 80×24. Estimates include model weights, context/state and compute buffers, using `llama-fit-params` beside your server. The planner and GNU `timeout` are optional: if unavailable or unsupported, the launcher says **Est. free: unavailable** and still allows startup. No model is loaded for inference to produce the estimate.

These are estimates, not launch guarantees. GPU budgets can share system RAM; never add the pools. Automatic placement is a snapshot, server slot/KV layouts can differ from the planner, and runtime overhead, multimodal projectors or other extra components may require more memory. Estimates are refreshed after configuration changes; available budgets are refreshed when returning to the main screen. Startup retains llama.cpp's own automatic choices.

While the server runs, `Free GiB: RAM ... | GPU ...` shows available system RAM and device-wide GPU budgets where the installed backend reports them. Availability reflects other programs too and may refer to shared memory rather than dedicated VRAM. Missing measurements show **N/A** or **unavailable**. No CPU/GPU utilization percentages, conversation recording or telemetry uploads are added.

Open **Performance** to adapt the launcher to another computer. Start with **Auto** and **Default**: these use llama.cpp's own choices, without fixed thread counts or a specific GPU.

| Option | Choices and advice |
| --- | --- |
| Device | **Auto**, **CPU only**, or a device detected by your installed llama.cpp. CPU only disables GPU layers. |
| CPU threads | **auto** or a positive number. Try a few values: using more threads is not always faster. |
| GPU layers | **auto**, **all**, or a number starting at 0. Auto lets llama.cpp fit layers to device memory; all can exceed it. The menu shows **Ignored (CPU only)** when it does not apply; the chosen layer count is kept for other devices. |
| Prompt processing | **Default**, **Low memory**, or **Large batch**. Low memory processes smaller chunks of input; Large batch tries larger chunks and needs more memory. |

Larger batches mainly affect how quickly input text is processed; they do not guarantee faster answer generation. On integrated graphics, the CPU and GPU share memory, so more GPU use is not always better. Flash Attention remains on llama.cpp's automatic setting.

Change one setting at a time and compare the same model, context and input. If loading fails, return to Auto/Default or reduce the context. To keep your choices after exit, save them under **Saved configurations**.

Before launch, the launcher checks requested options against the installed server's help and checks explicit devices when discovery succeeds. Missing options or devices produce a message; the TUI stays open for correction. A profile from another computer is not silently rewritten. Help and device probes have time limits; if GNU `timeout` is absent, they are skipped and llama.cpp reports startup errors itself. Auto and CPU only remain available in the device menu.

## Generation settings

Open **Model settings → Generation → Preset** to choose how text is sampled. Start with **Default**, which leaves llama.cpp's native settings and environment defaults unchanged. The other presets are starting points to compare on your model, not promises of accuracy or creativity. Follow the model author's recommendations when available.

| Preset | Temperature | Top-P | Top-K | Min-P |
| --- | --- | --- | --- | --- |
| Default | Native defaults | Native defaults | Native defaults | Native defaults |
| Focused | 0.6 | 0.95 | 20 | 0 |
| Exploratory | 1 | 0.95 | 20 | 0 |
| Min-P | 1 | 1 (disabled) | 0 (disabled) | 0.05 |
| Custom | Edit individual values | | | |

Presets are manual starting points for supported models; no model is detected or assigned a preset automatically. Explicit presets set repeat penalty to **1** and presence/frequency penalties to **0**, disabling those penalties. Presets do not change context, reasoning, hardware settings, seed or output length.

**Sampling parameters** shows all seven sampling values and lets you adjust them separately. Temperature controls randomness; Top-P, Top-K and Min-P filter token choices. Lower temperature does not guarantee correct answers. Penalties can reduce repetition but can also harm useful repeated text. Enter **auto** to leave a field to llama.cpp. Decimal inputs use a dot, a leading digit and at most nine decimal places. The preset label follows the exact sampling values; other combinations show **Custom**.

**Seed** accepts **auto**, **-1** for random, or an integer from **0** to **4294967295** (which also selects random). A fixed seed helps comparisons but does not guarantee identical results across runs, hardware or other settings. **Maximum output tokens** accepts **auto**, **-1** for no fixed generation limit, or **0–2147483647**; zero evaluates input without generating an answer. This is separate from context capacity. A short output limit can cut off reasoning before the answer.

These settings are **server defaults**. Explicit settings saved in your browser chat or sent by another client can override them. In the browser's generation settings, clear custom sampling values to use the server defaults; the launcher does not change browser preferences or conversations. Changes in the terminal take effect when you launch the server. If your llama.cpp build rejects an option, check **View log**, update llama.cpp or return that field to **auto**.

## Saved configurations

Choose your model and settings, then open **Saved configurations → Save as new configuration** and enter a name, such as `Gemma 8K` or `Qwen CPU`. Use **Load configuration** to restore a saved configuration, review its settings in the main menu, and select **Launch server** when ready. Loading does not start a server. **Delete configuration** removes a saved configuration; replacing or deleting one asks for confirmation.

Each configuration stores the model path, context, reasoning, port, all four Performance settings and all nine generation values, including seed and maximum output tokens. Older profiles without generation settings still load, restoring generation values to **auto**. New profiles require the complete set of fields; invalid or incomplete files leave all current settings unchanged. Profiles saved by this version require this version or newer to load. Conversations, extra command-line arguments and environment settings outside these menu controls are not saved. The main screen and Saved configurations menu show the current configuration name, or **Not saved**. Loading or saving a profile makes it current. Changes to its settings add **(Modified)**; restoring the saved values clears that marker. Choose **Update current** to overwrite the current profile after confirmation, or **Save as new configuration** to create another one. Nothing is saved automatically. Deleting the current profile keeps your settings and changes the label to **Not saved**. The current profile is tracked only for the open launcher session. Global folder paths are stored separately and are not compared; changing the models folder can still mark a profile Modified if it changes the selected model.

Files are stored in `~/.config/mir.cpp/profiles/` (or under `XDG_CONFIG_HOME` when set). You can back up that folder. If a model has moved or a profile is incomplete or invalid, loading leaves your current settings unchanged. A saved device must still be supported by your computer; choose Auto or CPU only after loading if needed. The launcher checks the selected port again before startup.

## If the port is already occupied

The main menu shows **IN USE**. Open **Server & port → View process details** to see process IDs, owners and names when available. Use **Up/Down** to scroll through long lists; **Back** or **Esc** returns to the port menu.

Choose another port, or open **Server & port → Stop process using port**. Check the displayed processes before confirming: they may belong to another application. Both shutdown confirmations include process details; use **Up/Down** to scroll if needed. The launcher first requests a normal shutdown. If a process stays active, it asks for a separate confirmation before forcing it to stop.

The launcher cannot stop processes owned by another user without the necessary permissions. If process details are unavailable, choose another port. Startup is blocked while the selected port is occupied.

## Advanced command-line use

Start with `mir` and configure folders, discovered models and settings in the TUI.
The commands below are optional shortcuts for automation and advanced server options.

Optionally override saved folders for an invocation with `MIR_LLAMA_CPP_DIR` and `MIR_MODELS_DIR`. Choosing a folder in Folders saves the currently displayed paths:

```bash
MIR_LLAMA_CPP_DIR="/path/to/llama.cpp" MIR_MODELS_DIR="/path/to/models" ~/.local/bin/mir
```

Start a specific model directly, without the menu:

```bash
MIR_CTX_SIZE=8192 MIR_REASONING=auto MIR_PORT=9931 \
    ~/.local/bin/mir "/path/to/model.gguf"
```

Performance settings also work with direct startup. For example, use only the CPU, four threads and smaller input chunks:

```bash
MIR_DEVICE=none MIR_THREADS=4 MIR_PROMPT_PROCESSING=low-memory \
    ~/.local/bin/mir "/path/to/model.gguf"
```

The optional variables are `MIR_CTX_SIZE` (`auto`, `0` for full model context, or a positive token count), `MIR_DEVICE` (`auto`, `none`, or comma-separated device names such as `Vulkan0,Vulkan1`), `MIR_THREADS` (`auto` or a positive number), `MIR_GPU_LAYERS` (`auto`, `all`, or a nonnegative number), and `MIR_PROMPT_PROCESSING` (`auto`, `low-memory`, or `large-batch`). Defaults leave the corresponding llama.cpp arguments unset, so any native llama.cpp environment settings still apply. Explicit arguments after the model path are passed through to llama.cpp and can override launcher choices. Multi-device selections are preserved in profiles too.

For model capabilities beyond the chat menus, pass the installed server's options directly: for example `mir /path/to/model.gguf --mmproj /path/to/projector.gguf`, or `--embedding` / `--rerank` with a suitable model. These components and task options are not saved in launcher profiles. Follow the model author's template and component requirements; the launcher does not infer them from model names.

Generation presets and individual overrides also work for direct startup:

```bash
MIR_GENERATION_PRESET=focused MIR_TEMPERATURE=0.7 MIR_MAX_TOKENS=2048 \
    ~/.local/bin/mir "/path/to/model.gguf"
```

`MIR_GENERATION_PRESET` accepts `default`, `focused`, `exploratory` or `min-p`. Individual controls override that preset: `MIR_TEMPERATURE`, `MIR_TOP_P`, `MIR_TOP_K`, `MIR_MIN_P`, `MIR_REPEAT_PENALTY`, `MIR_PRESENCE_PENALTY`, `MIR_FREQUENCY_PENALTY`, `MIR_SEED` and `MIR_MAX_TOKENS`. Each accepts `auto` or a numeric value as described above; temperature must be nonnegative, Top-P/Min-P must be in 0–1, Top-K a nonnegative integer up to 2147483647, and repeat penalty positive. Presence and frequency penalties allow signed decimals. Native llama.cpp environment defaults apply where a field is `auto`; explicit trailing arguments still take precedence.

Stop a direct session with **Ctrl+C**. Direct startup reports an occupied port and exits; use the menu to manage the occupying process.

The previous `SPUTNIK_*` controls remain compatibility aliases with the same suffixes as `MIR_*`. The older `LLAMA_CPP_DIR`, `LLAMA_MODELS_DIR`, `LLAMA_CTX_SIZE`, `LLAMA_REASONING`, `LLAMA_PORT`, `LLAMA_DEVICE`, `LLAMA_THREADS`, `LLAMA_GPU_LAYERS`, `LLAMA_PROMPT_PROCESSING`, `LLAMA_HOST` and generation aliases remain supported too. `LLAMA_CPP_DIR` maps to `MIR_LLAMA_CPP_DIR`.

For each setting, explicitly set `MIR_*` values take precedence over `SPUTNIK_*`, which take precedence over `LLAMA_*`. Explicitly empty `MIR_*` and `SPUTNIK_*` values also take precedence and are validated; legacy empty-value defaults stay compatible. Use `MIR_HOST` for an explicit server bind address. Native llama.cpp settings such as `LLAMA_ARG_*` and pass-through arguments remain supported. Port checks, readiness and browser opening follow effective `--host` / `--port` overrides, including IPv6; wildcard binds use a local address. A socket-only bind is checked through curl, and does not open a browser.

## Common problems

- **The menu does not appear:** run the launcher inside a terminal and make sure `dialog` is installed. Enlarge the terminal if the menu does not fit.
- **No models found:** choose the correct folder in **Folders → Models folder** and check for `.gguf` files in it or its subfolders.
- **llama-server not found:** follow the [llama.cpp build guide](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md) and select its llama.cpp folder in **Folders**. For direct startup, configure it in the TUI first or set `MIR_LLAMA_CPP_DIR`.
- **The model fails to load:** open **View log**. Try a smaller context or a smaller model, and check that your llama.cpp version supports it.
- **Vulkan device error:** check `vulkaninfo --summary`. Try **Auto** or **CPU only** under Performance settings. Devices shown there depend on the installed llama.cpp build. You can also run `~/Documenti/llama.cpp/build/bin/llama-server --list-devices` to see available devices.

## Code organization and checks

`mir.sh` loads the modules in `lib/`, initializes settings and coordinates configuration and startup. Keep the whole launcher folder together; you can run it from any working directory.

| Module | Responsibility |
| --- | --- |
| `lib/config.sh` | Initial settings and validation. |
| `lib/paths.sh` | Saved folder paths and recursive GGUF discovery. |
| `lib/gguf.py` | Optional metadata-only filtering, without reading model weights. |
| `lib/profiles.sh` | Profile data, validation, atomic writes and change tracking. |
| `lib/processes.sh` | Port inspection and confirmed listener shutdown. |
| `lib/server.sh` | Shared model arguments, startup, monitoring and cleanup. |
| `lib/memory.sh` | Optional native memory planning, available budgets and live memory. |
| `lib/tui/` | Dialog helpers, menus, folder navigation and running screen. |

Modules define functions without starting the application. They share the current configuration (`MODEL`, `CTX_SIZE`, `REASONING`, `PORT`, `DEVICE`, `THREADS`, `GPU_LAYERS`, `PROMPT_PROCESSING`, the `GENERATION` map and its ordered `GENERATION_KEYS`), folder paths and profile tracking in the launcher's shell. Port inspection supplies `LISTENERS`, `PIDS` and `PORT_STATUS`; server preparation supplies `ARGS` and `URL`. Lifecycle state, especially `SERVER_PID` and `LOG_FILE`, remains available to the exit trap. Temporary function variables are local. Load modules through the entry point, which applies Bash strict mode and the fixed module order.

For development, run these checks from the repository root:

```bash
find mir -name '*.sh' -exec bash -n {} \;
shellcheck -x -P SCRIPTDIR -P mir mir/mir.sh mir/sh/*.sh mir/tests/*.sh
bash mir/tests/regression.sh
bash mir/tests/installation.sh
bash mir/tests/memory.sh
bash mir/tests/portability.sh
```

ShellCheck follows the module imports from the entry point so it can check shared variables in context. The regression and installer checks additionally require Python 3, use temporary folders and simulated commands, and do not load real models or stop existing services. To compare direct startup and TUI flows with an earlier standalone launcher, pass its path to `bash mir/tests/regression.sh /path/to/old-launcher.sh`.

For an optional network check, run `bash mir/tests/download.sh`. It executes the
published README curl command twice in a temporary HOME, checking installation,
update and saved settings with real GitHub downloads. It tests published `main`,
which may differ from your checkout, and checks removal only when that version
includes it. The local installer tests always check the checkout's removal code.
