<p align="center">
  <img src="mir/docs/images/logo.png" alt="Mir.cpp logo: space station and terminal prompt" width="220">
</p>

# Mir.cpp

Run local GGUF models with llama.cpp through a simple Linux terminal menu.
Choose a model, adjust its settings, save configurations and chat in your browser.
This release targets Linux with CPU, Vulkan and CUDA builds of llama.cpp.
CUDA still needs validation on NVIDIA hardware.
Named after the Mir space station.

[<img src="mir/docs/screenshots/main-menu.png" alt="Main menu showing the current configuration and launch controls" width="640">](mir/docs/screenshots/main-menu.png)

*Review your model and server settings before launching.*

## Requirements

- Linux with Bash 4.4 or newer. The commands below are for Ubuntu/Debian.
- A working [llama.cpp build](https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md)
  containing `build/bin/llama-server`. Follow that guide for CPU or GPU setup.
- At least one GGUF model supported by your llama.cpp version, with enough
  memory for the model and selected context on your chosen CPU or GPU.

Install the launcher dependencies:

```bash
sudo apt update
sudo apt install bash coreutils findutils grep util-linux curl ca-certificates \
    tar gzip dialog iproute2 procps xdg-utils
```

`xdg-utils` opens the browser automatically; you can also open the address manually.
The installer does not build llama.cpp, install GPU drivers or download models.

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/etufarini/Mir.cpp/main/mir/sh/install.sh | bash
```

Installs for your user in `~/.local/share/mir.cpp/` and creates
`~/.local/bin/mir`, without sudo. Run the same command again to update.
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

1. On first launch, choose your **llama.cpp folder** and **Models folder** in **Folders**.
   Models can be organized in subfolders.
2. Choose a GGUF from the list in **Model settings → Model**, then review the settings.
   Start with **Auto** and **Default** values.
3. Select **Launch server**. The browser opens when ready, normally at
   `http://127.0.0.1:9931`. Keep the terminal open while chatting.

[<img src="mir/docs/screenshots/model-settings.png" alt="Model settings menu with model, context, reasoning and generation controls" width="640">](mir/docs/screenshots/model-settings.png)

*Context size and reasoning depend on model support. Larger contexts need more memory.*

Terminal settings configure the server; browser chat settings can override generation defaults.
Use **View log** if loading fails and **Stop server** when finished. Closing the browser
does not stop the server. If the port is **IN USE**, choose another port or inspect
**Server & port**: stopping another process requires confirmation, and forcing it to
stop requires a separate confirmation.

See the [user guide](mir/docs/guide.md) for saved configurations, advanced settings,
troubleshooting and maintenance.
