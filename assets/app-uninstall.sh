#!/usr/bin/env bash

# Works out how an app was installed from its desktop entry, and removes it the way that installer expects.
# This script never runs as root, only the package manager command handed to pkexec does.
#
#   app-uninstall.sh inspect <desktop id>
#       Prints key=value lines describing the app. Keys holding a list are repeated.
#   app-uninstall.sh remove <source> <args...> [--purge] [--cascade] [--override <desktop file>]
#       Exits with 0 when done, 3 when the package database is locked, 126 when authentication was dismissed,
#       127 when not authorised (or there's no polkit agent) and anything else on failure, with the reason on stderr.

set -u
export LC_ALL=C

readonly data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
readonly user_apps="$data_home/applications"

# Packages the session can't do without. HoldPkg from pacman.conf is added to these.
readonly protected=(base filesystem glibc pacman sudo systemd 'systemd-*' 'polkit*' 'hyprland*' 'quickshell*'
    'caelestia-*' linux linux-lts linux-zen linux-hardened linux-rt 'linux-cachyos*' 'linux-firmware*')

fail() {
    printf '%s\n' "$2" >&2
    exit "$1"
}

emit() {
    printf '%s=%s\n' "$1" "$2"
}

valid_name() {
    [[ $1 =~ ^[A-Za-z0-9@._+][A-Za-z0-9@._+-]*$ ]]
}

is_protected() {
    local pattern hold
    for pattern in "${protected[@]}"; do
        # shellcheck disable=SC2053 # The patterns are globs on purpose
        [[ $1 == $pattern ]] && return 0
    done
    while IFS= read -r hold; do
        [ "$1" = "$hold" ] && return 0
    done < <(pacman-conf HoldPkg 2>/dev/null)
    return 1
}

# Only desktop files in the user's own applications directory may be deleted directly
is_user_entry() {
    local dir apps
    [[ $1 == *.desktop ]] || return 1
    dir=$(realpath -m -- "$(dirname -- "$1")")
    apps=$(realpath -m -- "$user_apps")
    [[ $dir == "$apps" || $dir == "$apps"/* ]]
}

data_dirs() {
    local dir
    local -a dirs
    printf '%s\n' "$data_home"
    IFS=: read -ra dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    for dir in "${dirs[@]}"; do
        [ -n "$dir" ] && printf '%s\n' "$dir"
    done
}

# Every file providing a desktop id, highest priority first. Subdirectories are part of the id, so kde/foo is kde-foo.
find_entries() {
    local dir apps file rel
    while IFS= read -r dir; do
        apps="$dir/applications"
        [ -d "$apps" ] || continue
        if [ -f "$apps/$1.desktop" ]; then
            printf '%s\n' "$apps/$1.desktop"
            continue
        fi
        while IFS= read -r -d '' file; do
            rel=${file#"$apps"/}
            rel=${rel%.desktop}
            if [ "${rel//\//-}" = "$1" ]; then
                printf '%s\n' "$file"
                break
            fi
        done < <(find -L "$apps" -mindepth 2 -name '*.desktop' -print0 2>/dev/null)
    done < <(data_dirs)
}

# Value of a key in the [Desktop Entry] group
desktop_key() {
    awk -v key="$2" '
        /^[ \t]*\[/ { group = $0; next }
        group == "[Desktop Entry]" && match($0, "^" key "[ \t]*=[ \t]*") { print substr($0, RLENGTH + 1); exit }
    ' "$1"
}

appimage_path() {
    local try exec
    local quoted='"([^"]+\.[Aa][Pp][Pp][Ii][Mm][Aa][Gg][Ee])"'
    local plain='(^|[[:space:]])(/[^[:space:]"]+\.[Aa][Pp][Pp][Ii][Mm][Aa][Gg][Ee])([[:space:]]|$)'

    try=$(desktop_key "$1" TryExec)
    if [[ ${try,,} == *.appimage ]]; then
        printf '%s\n' "$try"
        return
    fi

    exec=$(desktop_key "$1" Exec)
    if [[ $exec =~ $quoted ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    elif [[ $exec =~ $plain ]]; then
        printf '%s\n' "${BASH_REMATCH[2]}"
    fi
}

inspect_pacman() {
    local pkg=$1 version preview line name blocked=0
    local -a dependents

    emit source pacman
    emit package "$pkg"
    version=$(pacman -Q -- "$pkg" 2>/dev/null) && emit version "${version#* }"
    pacman -Qqm -- "$pkg" > /dev/null 2>&1 && emit foreign 1

    if is_protected "$pkg"; then
        emit removable 0
        emit reason protected
        return
    fi

    # Dry run, doesn't need root or the database lock
    if preview=$(pacman -Rsp --print-format '%n %v' -- "$pkg" 2>&1); then
        while IFS= read -r line; do
            [ -n "$line" ] || continue
            emit target "$line"
            is_protected "${line%% *}" && blocked=1
        done <<< "$preview"

        if [ "$blocked" -eq 1 ]; then
            emit removable 0
            emit reason protected
        else
            emit removable 1
        fi
        return
    fi

    # Other packages need it, so it can only go along with them
    mapfile -t dependents < <(sed -n "s/^:: removing .* breaks dependency '.*' required by \(.*\)$/\1/p" <<< "$preview" | sort -u)
    if [ "${#dependents[@]}" -eq 0 ]; then
        emit removable 0
        emit reason error
        emit error "$(grep -m 1 '^error:' <<< "$preview")"
        return
    fi

    for name in "${dependents[@]}"; do
        emit dependent "$name"
    done
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        emit cascade "$line"
        is_protected "${line%% *}" && emit cascadeprotected "${line%% *}"
    done < <(pacman -Rscp --print-format '%n %v' -- "$pkg" 2>/dev/null)
    emit removable 1
}

inspect_nix() {
    local file=$1 real=$2 store name paths element="" line
    local profiles="${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles"

    if [[ $file != "$HOME/.nix-profile/"* && $file != "$profiles/"* ]] || ! command -v nix > /dev/null; then
        emit source nix
        emit removable 0
        emit reason declarative
        return
    fi

    # Find the profile element whose store path the desktop file lives in
    store=$(cut -d / -f 1-4 <<< "$real")
    while IFS= read -r line; do
        case $line in
            Name:*) read -r _ name <<< "$line" ;;
            "Store paths:"*)
                read -r _ _ paths <<< "$line"
                [[ " $paths " == *" $store "* ]] && element=$name
                ;;
        esac
    done < <(nix profile list 2> /dev/null | sed 's/\x1b\[[0-9;]*m//g')

    # Home Manager and friends install everything as one element, which has to be changed in their config
    if [ -z "$element" ] || [ "$element" = home-manager-path ]; then
        emit source nix
        emit removable 0
        emit reason declarative
        return
    fi

    emit source nix-profile
    emit package "$element"
    emit removable 1
}

inspect() {
    local id=$1 file real pkg value exec scope version
    local -a entries

    [[ $id =~ ^[^/]+$ && $id != .* ]] || fail 2 "Invalid desktop id: $id"
    mapfile -t entries < <(find_entries "$id")
    [ "${#entries[@]}" -gt 0 ] || fail 2 "No desktop entry found for $id"

    file=${entries[0]}
    emit path "$file"

    # A copy in the user's applications directory hiding a system entry: the app itself comes from the system one
    if [ "${#entries[@]}" -gt 1 ] && is_user_entry "$file"; then
        emit override "$file"
        file=${entries[1]}
    fi
    emit file "$file"
    real=$(realpath -e -- "$file" 2> /dev/null || printf '%s' "$file")

    value=$(desktop_key "$file" X-Flatpak)
    if [ -n "$value" ]; then
        scope=system
        [[ $file == "$data_home/flatpak/"* || $real == "$data_home/flatpak/"* ]] && scope=user
        emit source flatpak
        emit package "$value"
        emit scope "$scope"
        version=$(flatpak info "--$scope" "$value" 2> /dev/null | sed -n 's/^[[:space:]]*Version:[[:space:]]*//p')
        [ -n "$version" ] && emit version "$version"
        [ -d "$HOME/.var/app/$value" ] && emit data "$HOME/.var/app/$value"
        emit removable 1
        return
    fi

    value=$(desktop_key "$file" X-SnapInstanceName)
    if [ -n "$value" ] || [[ $file == /var/lib/snapd/desktop/applications/* ]]; then
        [ -n "$value" ] || value=$(basename -- "$file" .desktop)
        emit source snap
        emit package "${value%%_*}"
        emit removable 1
        return
    fi

    if [[ $real == /nix/store/* ]]; then
        inspect_nix "$file" "$real"
        return
    fi

    if command -v pacman > /dev/null && pkg=$(pacman -Qqo -- "$file" 2> /dev/null) && [ -n "$pkg" ]; then
        inspect_pacman "$pkg"
        return
    fi

    if command -v dpkg > /dev/null && pkg=$(dpkg -S -- "$file" 2> /dev/null) && [ -n "$pkg" ]; then
        pkg=${pkg%%: *}
        emit source dpkg
        emit package "${pkg%%:*}"
        emit removable 0
        emit reason foreign
        return
    fi

    if command -v rpm > /dev/null && pkg=$(rpm -qf --qf '%{NAME}\n' -- "$file" 2> /dev/null) && [ -n "$pkg" ]; then
        emit source rpm
        emit package "$pkg"
        emit removable 0
        emit reason foreign
        return
    fi

    value=$(appimage_path "$file")
    if [ -n "$value" ] || [ -n "$(desktop_key "$file" X-AppImage-Version)$(desktop_key "$file" X-AppImage-Identifier)" ]; then
        emit source appimage
        if [ -n "$value" ]; then
            emit appimage "$value"
            emit package "$(basename -- "$value")"
        fi
        if is_user_entry "$file"; then
            emit removable 1
        else
            emit removable 0
            emit reason unknown
        fi
        return
    fi

    exec=$(desktop_key "$file" Exec)
    if [[ $exec =~ steam://rungameid/([0-9]+) ]]; then
        emit source steam
        emit steamid "${BASH_REMATCH[1]}"
        emit removable 1
        return
    fi

    if [[ $file == "$user_apps/wine/"* || $exec =~ (^|[[:space:]/])wine[[:space:]] ]]; then
        value="$HOME/.wine"
        if [[ $exec =~ WINEPREFIX=\"([^\"]+)\" ]] || [[ $exec =~ WINEPREFIX=([^[:space:]\"]+) ]]; then
            value=${BASH_REMATCH[1]}
        fi
        emit source wine
        emit wineprefix "$value"
        emit removable 1
        return
    fi

    if is_user_entry "$file"; then
        emit source local
        emit removable 1
        return
    fi

    emit source unknown
    emit removable 0
    emit reason unknown
}

remove_pacman() {
    local pkg=$1 purge=$2 cascade=$3 flags=-Rs dbpath err status target

    valid_name "$pkg" || fail 2 "Invalid package name: $pkg"
    is_protected "$pkg" && fail 2 "$pkg is needed by the system and can't be uninstalled here"
    if [ "$cascade" -eq 1 ]; then
        while read -r target _; do
            is_protected "$target" && fail 2 "Uninstalling $pkg would also remove $target, which the system needs"
        done < <(pacman -Rscp --print-format '%n %v' -- "$pkg" 2> /dev/null)
    fi

    dbpath=$(pacman-conf DBPath 2> /dev/null)
    dbpath=${dbpath:-/var/lib/pacman/}
    [ -e "${dbpath%/}/db.lck" ] && fail 3 "The package database is locked (${dbpath%/}/db.lck), another package manager is probably running"

    [ "$purge" -eq 1 ] && flags+=n
    [ "$cascade" -eq 1 ] && flags+=c

    # pkexec refuses shells missing from /etc/shells, and fish often is
    err=$(SHELL=/bin/sh pkexec pacman "$flags" --noconfirm --noprogressbar -- "$pkg" 2>&1 > /dev/null)
    status=$?
    [ -n "$err" ] && printf '%s\n' "$err" >&2
    [ "$status" -ne 0 ] && [[ $err == *"unable to lock database"* ]] && return 3
    return "$status"
}

remove_flatpak() {
    local scope=$1 id=$2 purge=$3
    local -a cmd

    [[ $scope == user || $scope == system ]] || fail 2 "Invalid Flatpak installation: $scope"
    valid_name "$id" || fail 2 "Invalid Flatpak app id: $id"

    # Flatpak asks polkit itself for system installs, running it as root would target root's own installation
    cmd=(flatpak uninstall "--$scope" --noninteractive)
    [ "$purge" -eq 1 ] && cmd+=(--delete-data)
    "${cmd[@]}" -- "$id"
}

remove_snap() {
    local name=$1 purge=$2
    local -a cmd

    valid_name "$name" || fail 2 "Invalid snap name: $name"

    # The snap CLI only lets polkit ask for a password from a terminal
    cmd=(snap remove)
    [ "$purge" -eq 1 ] && cmd+=(--purge)
    SHELL=/bin/sh pkexec "${cmd[@]}" -- "$name"
}

remove_appimage() {
    local desktop=$1 appimage=$2 hash icon

    is_user_entry "$desktop" || fail 2 "Refusing to remove $desktop"

    if [ -n "$appimage" ] && [ -e "$appimage" ]; then
        [[ ${appimage,,} == *.appimage && $appimage == "$HOME"/* ]] || fail 2 "Refusing to remove $appimage, delete it manually"
        if command -v gio > /dev/null; then
            gio trash -- "$appimage" || fail 1 "Unable to move $appimage to the trash"
        else
            rm -f -- "$appimage" || fail 1 "Unable to delete $appimage"
        fi
    fi

    # AppImageLauncher names icons after the hash in the desktop file name, Gear Lever keeps them next to the AppImage
    if [[ $(basename -- "$desktop") =~ ^appimagekit_([0-9a-f]{32}) ]]; then
        hash=${BASH_REMATCH[1]}
        find "$data_home/icons" -name "appimagekit_${hash}_*" -delete 2> /dev/null
    fi
    icon=$(desktop_key "$desktop" Icon)
    if [ -n "$appimage" ] && [[ $icon == "$(dirname -- "$appimage")/.icons/"* ]]; then
        rm -f -- "$icon"
    fi

    rm -f -- "$desktop" || fail 1 "Unable to delete $desktop"
    command -v update-desktop-database > /dev/null && update-desktop-database -q "$user_apps" 2> /dev/null
    return 0
}

remove() {
    local source=${1:-} purge=0 cascade=0 override="" status
    local -a args=()

    [ $# -gt 0 ] && shift
    while [ $# -gt 0 ]; do
        case $1 in
            --purge) purge=1 ;;
            --cascade) cascade=1 ;;
            --override)
                override=${2:-}
                shift
                ;;
            *) args+=("$1") ;;
        esac
        shift
    done

    [ -z "$override" ] || is_user_entry "$override" || fail 2 "Refusing to remove $override"

    case $source in
        pacman) remove_pacman "${args[0]:-}" "$purge" "$cascade" ;;
        flatpak) remove_flatpak "${args[0]:-}" "${args[1]:-}" "$purge" ;;
        snap) remove_snap "${args[0]:-}" "$purge" ;;
        nix-profile)
            valid_name "${args[0]:-}" || fail 2 "Invalid profile element: ${args[0]:-}"
            nix profile remove "${args[0]}"
            ;;
        appimage) remove_appimage "${args[0]:-}" "${args[1]:-}" ;;
        local)
            is_user_entry "${args[0]:-}" || fail 2 "Refusing to remove ${args[0]:-}"
            rm -f -- "${args[0]}"
            ;;
        steam)
            [[ ${args[0]:-} =~ ^[0-9]+$ ]] || fail 2 "Invalid Steam app id: ${args[0]:-}"
            # Steam shows its own confirmation
            setsid -f xdg-open "steam://uninstall/${args[0]}" > /dev/null 2>&1
            ;;
        wine)
            [[ ${args[0]:-} == /* && -d ${args[0]:-} ]] || fail 2 "Invalid Wine prefix: ${args[0]:-}"
            setsid -f env WINEPREFIX="${args[0]}" wine uninstaller > /dev/null 2>&1
            ;;
        *) fail 2 "Unable to uninstall apps from $source" ;;
    esac
    status=$?

    [ "$status" -eq 0 ] && [ -n "$override" ] && rm -f -- "$override"
    return "$status"
}

case ${1:-} in
    inspect)
        [ $# -eq 2 ] || fail 2 "Usage: $0 inspect <desktop id>"
        inspect "$2"
        ;;
    remove)
        shift
        remove "$@"
        ;;
    *) fail 2 "Usage: $0 inspect <desktop id> | remove <source> <args...>" ;;
esac
