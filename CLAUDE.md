# kdz-caelestia

Personal fork of [caelestia-dots/shell](https://github.com/caelestia-dots/shell), a Quickshell (QML + C++ plugin) desktop shell.

- `origin`: `git@github.com:KidiXDev/kdz-caelestia.git`
- `upstream`: `git@github.com:caelestia-dots/shell.git`
- The fork changes C++ as well as QML (e.g. `plugin/src/Caelestia/Services/hyprextras.cpp`), so fork QML needs the fork's plugin. Don't run fork QML against the system plugin or the reverse.

## Layout

- `shell.qml`, `modules/`, `services/`, `components/`, `utils/`, `assets/`: QML config, installed as the Quickshell config
- `plugin/`: C++ QML modules (`Caelestia.*`), built to `build/qml`
- `extras/`: `version` helper, found via `CAELESTIA_LIB_DIR` (`utils/Paths.qml`, default `/usr/lib/caelestia`)
- `scripts/`: lint and translation tools, plus `fork-switch.sh`

## Dev workflow

`.envrc` (direnv) configures and builds `build/` (RelWithDebInfo), then exports `QML2_IMPORT_PATH=$PWD/build/qml` and `CAELESTIA_LIB_DIR=$PWD/build/lib`. That makes the dev plugin override the system one.

## How the shell runs on this machine

- The upstream shell comes from the AUR package `caelestia-shell-git`: QML in `/etc/xdg/quickshell/caelestia`, plugin in `/usr/lib/qt6/qml/Caelestia`, `/usr/lib/caelestia/version`. `quickshell-git` and `caelestia-cli` are also installed.
- `caelestia shell -d` / `-r` / `-k` run `qs -c caelestia`. `-r` without `-d` restarts in the foreground, so Ctrl+C kills the shell. Scripts must use `-r -d`. Quickshell looks in `~/.config/quickshell/caelestia` first, then `/etc/xdg/quickshell/caelestia`.
- To see which config is running: `qs list --all` (look for `Config path`).
- Never `sudo cmake --install` to `/`. It overwrites files owned by the pacman package.

## Running the fork: `scripts/fork-switch.sh`

It's symlinked into PATH as `~/.local/bin/caelestia-fork`. Run it with no argument for a menu, or pass `fork|upstream|update|status`.

- **`update`:** Release build in `build/release` (git-ignored via `build/`), installed to `~/.local/share/caelestia-fork/{shell,qml,lib}`.
  - It then adds two lines at the top of the installed `shell.qml`:
    ```
    //@ pragma Env QML2_IMPORT_PATH=~/.local/share/caelestia-fork/qml
    //@ pragma Env CAELESTIA_LIB_DIR=~/.local/share/caelestia-fork/lib
    ```
    (with absolute paths). This ties the fork's plugin to the fork's config, so the upstream config never loads it.
  - It works without Hyprland `env =` lines or a re-login. This was checked with a test config: the fork's `libcaelestia-servicesplugin.so` showed up in `/proc/<pid>/maps`.
  - It only restarts the shell if the fork is the active config.
- **`fork`:** runs `update` if nothing is installed yet, then links `~/.config/quickshell/caelestia` → `~/.local/share/caelestia-fork/shell` and restarts.
- **`upstream`:** removes the link so the AUR shell in `/etc/xdg` runs, then restarts.
- **Backups:** a real (non-symlink) `~/.config/quickshell/caelestia` is moved to `caelestia.bak-<timestamp>`, never deleted. Before the switcher existed, that folder was a hand-copied, tweaked config that differs from both upstream and the fork.
- **Snapshot:** the installed fork is a copy (`watchFiles: false`), so changes in the repo don't reach the running shell until `update`.
- **Full removal:** `rm -r ~/.local/share/caelestia-fork ~/.local/bin/caelestia-fork`.
