pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n

// Finds out how apps were installed and uninstalls them through whatever installed them (see
// assets/app-uninstall.sh). One uninstall runs at a time, and it carries on if Nexus is closed.
Singleton {
    id: root

    readonly property string script: Quickshell.shellPath("assets/app-uninstall.sh")
    readonly property bool busy: busyAppId !== ""
    property string busyAppId
    property string busyAppName
    property var busyInfo: null

    // error is empty on success
    signal finished(appId: string, success: bool, error: string)

    // Calls back with what inspect reports about the app, see parse()
    function inspect(app: DesktopEntry, callback: var): void {
        const proc = inspectComp.createObject(root, {
            callback: callback
        });
        proc.exec(["bash", script, "inspect", app.id]);
    }

    function parse(text: string): var {
        const info = {
            removable: false,
            foreign: false,
            targets: [],
            dependents: [],
            cascade: [],
            cascadeProtected: []
        };
        const lists = {
            target: "targets",
            dependent: "dependents",
            cascade: "cascade",
            cascadeprotected: "cascadeProtected"
        };

        for (const line of text.split("\n")) {
            const sep = line.indexOf("=");
            if (sep <= 0)
                continue;
            const key = line.slice(0, sep);
            const value = line.slice(sep + 1);
            if (lists[key])
                info[lists[key]].push(value);
            else if (key === "removable" || key === "foreign")
                info[key] = value === "1";
            else
                info[key] = value;
        }

        return info;
    }

    function errorInfo(error: string): var {
        return Object.assign(parse(""), {
            reason: "error",
            error: error
        });
    }

    function removeArgs(info: var): var {
        switch (info.source) {
        case "pacman":
            return ["pacman", info.package];
        case "flatpak":
            return ["flatpak", info.scope, info.package];
        case "snap":
            return ["snap", info.package];
        case "nix-profile":
            return ["nix-profile", info.package];
        case "appimage":
            return ["appimage", info.file, info.appimage ?? ""];
        case "local":
            return ["local", info.file];
        case "steam":
            return ["steam", info.steamid];
        case "wine":
            return ["wine", info.wineprefix];
        }
        return null;
    }

    function uninstall(app: DesktopEntry, info: var, purge: bool, cascade: bool): void {
        const args = info?.removable ? removeArgs(info) : null;
        if (busy || !args)
            return;

        if (purge)
            args.push("--purge");
        if (cascade)
            args.push("--cascade");
        if (info.override)
            args.push("--override", info.override);

        busyAppId = app.id;
        busyAppName = app.name;
        busyInfo = info;
        uninstallProc.exec(["bash", script, "remove", ...args]);
    }

    // Steam and Wine have their own uninstallers, which only get opened here
    function isHandoff(info: var): bool {
        return info?.source === "steam" || info?.source === "wine";
    }

    function sourceLabel(info: var): string {
        switch (info?.source) {
        case "pacman":
            return info.foreign ? Tr.tr("Pacman (AUR or local package)") : Tr.tr("Pacman");
        case "flatpak":
            return info.scope === "user" ? Tr.tr("Flatpak (user)") : Tr.tr("Flatpak (system)");
        case "snap":
            return Tr.tr("Snap");
        case "appimage":
            return Tr.tr("AppImage");
        case "nix":
            return Tr.tr("Nix");
        case "nix-profile":
            return Tr.tr("Nix profile");
        case "steam":
            return Tr.tr("Steam");
        case "wine":
            return Tr.tr("Wine");
        case "local":
            return Tr.tr("Shortcut");
        case "dpkg":
            return Tr.tr("dpkg");
        case "rpm":
            return Tr.tr("RPM");
        }
        return Tr.trCtx("Unknown", "app install source");
    }

    function actionLabel(info: var): string {
        switch (info?.source) {
        case "steam":
            return Tr.trCtx("Uninstall in Steam", "button");
        case "wine":
            return Tr.trCtx("Open Wine uninstaller", "button");
        case "local":
            return Tr.trCtx("Remove shortcut", "button");
        }
        return Tr.trCtx("Uninstall", "button");
    }

    // Package managers print a lot, the actual reason is usually the last error line
    function errorMessage(text: string): string {
        const lines = text.split("\n").map(l => l.trim()).filter(l => l);
        const error = lines.filter(l => l.startsWith("error:")).pop() ?? lines.pop() ?? "";
        return error.replace(/^error:\s*/, "");
    }

    // Drops the app from the launcher lists, leaving regex entries alone
    function forgetApp(id: string): void {
        const favourites = GlobalConfig.launcher.favouriteApps;
        if (favourites.includes(id))
            GlobalConfig.launcher.favouriteApps = favourites.filter(a => a !== id);

        const hidden = GlobalConfig.launcher.hiddenApps;
        if (hidden.includes(id))
            GlobalConfig.launcher.hiddenApps = hidden.filter(a => a !== id);
    }

    function handleExit(code: int, stderr: string): void {
        const id = busyAppId;
        const name = busyAppName;
        const info = busyInfo;
        busyAppId = "";
        busyAppName = "";
        busyInfo = null;

        if (code === 0) {
            if (isHandoff(info)) {
                Toaster.toast(Tr.tr("Opened the %1 uninstaller").arg(sourceLabel(info)), Tr.tr("Finish uninstalling %1 there").arg(name), "open_in_new");
            } else {
                forgetApp(id);
                Toaster.toast(Tr.tr("%1 uninstalled").arg(name), Tr.tr("Removed with %1").arg(sourceLabel(info)), "delete", Toast.Success);
            }
            finished(id, true, "");
            return;
        }

        let error;
        if (code === 126)
            error = Tr.tr("Authentication was cancelled");
        else if (code === 127)
            error = Tr.tr("Authentication failed, or no polkit authentication agent is running");
        else if (code === 3)
            error = Tr.tr("Another package manager is running, try again once it's done");
        else
            error = errorMessage(stderr) || Tr.tr("The uninstaller exited with code %1").arg(code);

        Toaster.toast(Tr.tr("Unable to uninstall %1").arg(name), error, "error", code === 126 ? Toast.Info : Toast.Error);
        finished(id, false, error);
    }

    Process {
        id: uninstallProc

        property bool exited

        stderr: StdioCollector {
            id: uninstallErr
        }

        onRunningChanged: {
            if (running) {
                exited = false;
                return;
            }
            if (!exited && root.busy)
                root.handleExit(-1, Tr.tr("Unable to run the uninstaller"));
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            exited = true;
            Qt.callLater(() => root.handleExit(code, uninstallErr.text));
        }
    }

    Component {
        id: inspectComp

        Process {
            id: proc

            property var callback
            property bool exited

            stdout: StdioCollector {
                id: inspectOut
            }
            stderr: StdioCollector {
                id: inspectErr
            }

            onRunningChanged: {
                if (running || exited)
                    return;
                proc.callback?.(root.errorInfo(Tr.tr("Unable to run the uninstaller")));
                proc.destroy();
            }
            onExited: code => { // qmllint disable signal-handler-parameters
                exited = true;
                Qt.callLater(() => {
                    if (code === 0) {
                        proc.callback?.(root.parse(inspectOut.text));
                    } else {
                        proc.callback?.(root.errorInfo(root.errorMessage(inspectErr.text) || Tr.tr("Unable to check how this app was installed")));
                    }
                    proc.destroy();
                });
            }
        }
    }
}
