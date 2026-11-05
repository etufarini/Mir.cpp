<p align="center">
  <img src="mir/docs/images/logo.png" alt="Mir.cpp logo: space station and terminal prompt" width="220">
</p>

# Mir.cpp

Run local GGUF models with llama.cpp through a simple terminal menu on Linux and macOS.
Choose a model, adjust its settings, save configurations and chat in your browser.
Supports Linux with CPU, Vulkan and CUDA builds, and macOS with CPU and Metal.
CUDA still needs validation on NVIDIA hardware.
Named after the Mir space station.

[<img src="mir/docs/screenshots/main-menu.png" alt="Main menu showing the current configuration and launch controls" width="640">](mir/docs/screenshots/main-menu.png)

*Review your model and server settings before launching.*

## Requirements

- Linux or macOS, internet access and a terminal.
- On Linux: Bash 4.4 or newer, curl and working HTTPS certificates to start
  the installer. Ubuntu/Debian dependency installation is assisted; other
  distributions require equivalent packages installed manually.
- On macOS: [Homebrew](https://brew.sh/). The installer can start with the system
  Bash and offers to install missing Bash and launcher dependencies.
- At least one GGUF model supported by llama.cpp, with enough RAM or GPU memory.
  Model downloads and GPU drivers are configured separately.

The installer asks before installing missing dependencies using apt on
Ubuntu/Debian or Homebrew on macOS. Only apt operations may require sudo.
Install llama.cpp from **Folders → Install / update llama.cpp**, or select an
existing build. macOS compilation also requires Apple's command line tools.
See the [official llama.cpp build instructions](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md)
for platform and GPU requirements.

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/etufarini/Mir.cpp/main/mir/sh/install.sh | bash
```

Installs for your user in `~/.local/share/mir.cpp/` and creates
`~/.local/bin/mir`. Only Ubuntu/Debian dependency installation may ask for your sudo
password. Run the same command again to update Mir.cpp.
Close the launcher before updating.

To remove the installed program, stop the server and close the launcher, then run:

```bash
mir --uninstall
```

Confirm when prompted. Models, llama.cpp and saved configurations are kept.
For removal without a prompt, use `mir --uninstall --yes`.

## Start

```bash
mir
```

If the command is not found, use `~/.local/bin/mir` or add `~/.local/bin` to your PATH.

1. Open **Folders → Install / update llama.cpp** to build CPU/Vulkan/CUDA on Linux
   or CPU/Metal on macOS. You can also select an existing **llama.cpp folder**.
2. Choose your **Models folder** in **Folders**. Models can be organized in subfolders.
3. Choose a GGUF from the list in **Model settings → Model**, then review the settings.
   Start with **Auto** and **Default** values.
4. Select **Launch server**. The browser opens when ready, normally at
   `http://127.0.0.1:9931`. Keep the terminal open while chatting.

Update llama.cpp through **Folders → Install / update llama.cpp → Check for updates**.
Failed builds keep the working version; **Restore previous build** switches back.

[<img src="mir/docs/screenshots/model-settings.png" alt="Model settings menu with model, context, reasoning and generation controls" width="640">](mir/docs/screenshots/model-settings.png)

*Context size and reasoning depend on model support. Larger contexts need more memory.*

Terminal settings configure the server; browser chat settings can override generation defaults.
Use **View log** if loading fails and **Stop server** when finished. Closing the browser
does not stop the server. If the port is **IN USE**, choose another port or inspect
**Server & port**: stopping another process requires confirmation, and forcing it to
stop requires a separate confirmation.

See the [user guide](mir/docs/guide.md) for saved configurations, advanced settings,
troubleshooting and maintenance.
