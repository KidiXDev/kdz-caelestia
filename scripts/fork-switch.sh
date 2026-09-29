#!/usr/bin/env bash
# Switch the running Caelestia shell between this fork and the upstream (AUR) install.
# Usage: fork-switch.sh [fork|upstream|update|status]   (no arg = interactive menu)

set -euo pipefail

repo=$(dirname "$(dirname "$(readlink -f "$0")")")
prefix=$HOME/.local/share/caelestia-fork
link=${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia

current() {
    if [[ -L $link && $(readlink -f "$link") == "$prefix/shell" ]]; then
        echo fork
    elif [[ -e $link ]]; then
        echo "local copy ($link)"
    else
        echo upstream
    fi
}

restart() {
    echo ":: Restarting shell"
    caelestia shell -r -d
}

# Moves a real (non-symlink) config dir aside so it is never lost.
stash() {
    if [[ -e $link && ! -L $link ]]; then
        local bak="$link.bak-$(date +%Y%m%d-%H%M%S)"
        mv "$link" "$bak"
        echo ":: Backed up existing config to $bak"
    fi
}

update() {
    echo ":: Building fork from $repo"
    if [[ ! -f $repo/build/release/build.ninja ]]; then
        cmake -S "$repo" -B "$repo/build/release" -G Ninja -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX="$prefix" -DINSTALL_QSCONFDIR=shell -DINSTALL_QMLDIR=qml \
            -DINSTALL_LIBDIR=lib -DDISTRIBUTOR=kdz-fork
    fi
    cmake --build "$repo/build/release"
    cmake --install "$repo/build/release" > /dev/null
    # Tie the fork's plugin to the fork's config, so upstream never loads it
    sed -i -e "1i //@ pragma Env QML2_IMPORT_PATH=$prefix/qml\n//@ pragma Env CAELESTIA_LIB_DIR=$prefix/lib" \
        -e '/^\/\/@ pragma Env \(QML2_IMPORT_PATH\|CAELESTIA_LIB_DIR\)=/d' "$prefix/shell/shell.qml"
    echo ":: Installed to $prefix"
    [[ $(current) == fork ]] && restart || true
}

use_fork() {
    [[ -f $prefix/shell/shell.qml ]] || update
    stash
    ln -sfn "$prefix/shell" "$link"
    restart
}

use_upstream() {
    [[ -f /etc/xdg/quickshell/caelestia/shell.qml ]] || { echo "!! Upstream not installed (caelestia-shell-git)" >&2; exit 1; }
    [[ -L $link ]] && rm "$link"
    stash
    restart
}

run() {
    case $1 in
        fork) use_fork ;;
        upstream) use_upstream ;;
        update) update ;;
        status) echo "Current: $(current)" ;;
        *) echo "Usage: $0 [fork|upstream|update|status]" >&2; exit 1 ;;
    esac
}

if [[ $# -gt 0 ]]; then
    run "$1"
    exit
fi

echo "Current: $(current)"
PS3="Choose: "
select opt in "Use fork" "Use original (upstream)" "Update fork (rebuild + install)" "Quit"; do
    case $REPLY in
        1) run fork ;;
        2) run upstream ;;
        3) run update ;;
        *) ;;
    esac
    break
done
