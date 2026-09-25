pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils
import qs.modules.nexus.common

// Confirmation and progress for uninstalling an app, shown over rootParent (usually the page's flickable)
Item {
    id: root

    required property Item rootParent
    property DesktopEntry app
    property var info: null
    property bool checking
    property bool purge
    property bool cascade
    property string error
    property bool open

    readonly property bool running: !!app && Uninstaller.busyAppId === app.id
    readonly property bool needsCascade: (info?.dependents.length ?? 0) > 0
    // pacman lists the package itself too, and not necessarily first
    readonly property var extraTargets: (info?.targets ?? []).filter(t => t.split(" ")[0] !== info.package)
    readonly property var extraCascade: (info?.cascade ?? []).filter(t => t.split(" ")[0] !== info.package)
    readonly property bool canUninstall: !!info?.removable && !running && !Uninstaller.busy && (!needsCascade || (cascade && info.cascadeProtected.length === 0))

    function openFor(entry: DesktopEntry): void {
        app = entry;
        info = null;
        error = "";
        purge = false;
        cascade = false;
        open = true;
        inspect();
    }

    function inspect(): void {
        const id = app?.id;
        if (!id)
            return;

        checking = true;
        Uninstaller.inspect(app, result => {
            // Ignore it if the dialog is gone or moved on to another app in the meantime
            if (root?.app?.id !== id)
                return;
            root.checking = false;
            root.info = result;
        });
    }

    function formatList(items: var): string {
        const max = 6;
        const names = items.map(i => i.split(" ")[0]);
        if (names.length <= max)
            return names.join(", ");
        // TRANSLATORS: %1 = a list of package names, %n = how many more there are
        return Tr.trN("%1 and %n more", "%1 and %n more", names.length - max).arg(names.slice(0, max).join(", "));
    }

    function description(): string {
        const name = app?.name ?? "";
        switch (info?.source) {
        case "pacman":
            if (needsCascade)
                // TRANSLATORS: %1 = an app name, %2 = a list of package names
                return Tr.tr("%1 is needed by other installed packages: %2").arg(name).arg(formatList(info.dependents));
            if (extraTargets.length > 0)
                return Tr.trN("Its package and %n other package nothing else needs will be removed: %1", "Its package and %n other packages nothing else needs will be removed: %1", extraTargets.length).arg(formatList(extraTargets));
            return Tr.tr("Its package will be removed. You'll be asked for your password.");
        case "flatpak":
            return Tr.tr("It will be removed from your Flatpak installation. Runtimes other apps might use are kept.");
        case "snap":
            return Tr.tr("The snap and all of its revisions will be removed. You'll be asked for your password.");
        case "nix-profile":
            return Tr.tr("It will be removed from your Nix profile.");
        case "appimage":
            return Tr.tr("The AppImage will be moved to the trash, and its menu entry and icons removed.");
        case "local":
            return Tr.tr("This only removes the menu shortcut. It isn't part of a package, so there's nothing else to uninstall.");
        case "steam":
            return Tr.tr("Steam will open and ask you to confirm uninstalling the game.");
        case "wine":
            return Tr.tr("Wine's uninstaller will open, pick the program to remove there.");
        }
        return "";
    }

    function reasonText(): string {
        switch (info?.reason) {
        case "protected":
            // TRANSLATORS: %1 = a package name
            return Tr.tr("%1 is needed by the system or the shell itself, so it can't be uninstalled from here.").arg(info.package ?? app?.name ?? "");
        case "declarative":
            return Tr.tr("This app is installed declaratively with Nix. Remove it from your NixOS or Home Manager configuration instead.");
        case "foreign":
            // TRANSLATORS: %1 = a package manager
            return Tr.tr("This app is managed by %1. Uninstall it with your system's package manager instead.").arg(Uninstaller.sourceLabel(info));
        case "unknown":
            return Tr.tr("This app wasn't installed by a package manager the shell knows about, so it can't be uninstalled from here.");
        }
        return info?.error || Tr.tr("Unable to check how this app was installed");
    }

    function purgeText(): string {
        switch (info?.source) {
        case "pacman":
            return Tr.tr("Don't keep backups of changed system config files");
        case "flatpak":
            return Tr.tr("Also delete app data");
        case "snap":
            return Tr.tr("Don't keep a snapshot of app data");
        }
        return "";
    }

    function purgeSubtext(): string {
        switch (info?.source) {
        case "pacman":
            return Tr.tr("Removes the .pacsave copies pacman would leave behind");
        case "flatpak":
            return info.data ? Paths.shortenHome(info.data) : Tr.tr("Settings and files kept in ~/.var/app");
        case "snap":
            return Tr.tr("Snap saves one by default, in case you reinstall it");
        }
        return "";
    }

    parent: rootParent
    anchors.fill: parent
    z: 2
    visible: opacity > 0
    opacity: open ? 1 : 0

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    Connections {
        function onFinished(appId: string, success: bool, error: string): void {
            if (appId !== root.app?.id)
                return;
            if (success)
                root.open = false;
            else
                root.error = error;
        }

        target: Uninstaller
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.open
        hoverEnabled: true
        onClicked: root.open = false
        onWheel: event => event.accepted = true

        StyledRect {
            anchors.fill: parent
            color: Colours.palette.m3scrim
            opacity: 0.3
        }
    }

    StyledRect {
        id: card

        anchors.centerIn: parent
        width: Math.min(parent.width - Tokens.padding.extraLarge * 2, Math.round(Tokens.sizes.nexus.maxDialogWidth * 1.25))
        implicitHeight: layout.implicitHeight + Tokens.padding.extraLarge + Tokens.padding.largeIncreased

        radius: Tokens.rounding.extraLargeIncreased
        color: Colours.palette.m3surfaceContainerHighest
        scale: root.open ? 1 : 0.9

        Behavior on scale {
            Anim {}
        }

        Behavior on implicitHeight {
            Anim {}
        }

        Elevation {
            anchors.fill: parent
            radius: parent.radius
            z: -1
            level: 4
        }

        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: layout

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.extraLarge
            anchors.bottomMargin: Tokens.padding.largeIncreased
            spacing: Tokens.spacing.medium

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.large

                IconImage {
                    asynchronous: true
                    implicitSize: Math.round(Tokens.font.icon.large.pointSize * 2.2)
                    source: Quickshell.iconPath(root.app?.icon, "image-missing")
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: root.info?.source === "local" ? Tr.tr("Remove %1?").arg(root.app?.name ?? "") : Tr.tr("Uninstall %1?").arg(root.app?.name ?? "")
                        font: Tokens.font.title.builders.large.weight(Font.Normal).build()
                        wrapMode: Text.WordWrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: !!root.info
                        text: {
                            const parts = [Uninstaller.sourceLabel(root.info)];
                            if (root.info?.package)
                                parts.push([root.info.package, root.info.version ?? ""].join(" ").trim());
                            return parts.join(" · ");
                        }
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.small
                        elide: Text.ElideRight
                    }
                }
            }

            // Checking or uninstalling
            RowLayout {
                Layout.fillWidth: true
                visible: root.checking || root.running
                spacing: Tokens.spacing.medium

                LoadingIndicator {
                    implicitSize: Math.round(Tokens.font.body.medium.pointSize * 2)
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.running ? Tr.tr("Uninstalling… approve the password prompt if one appears") : Tr.tr("Checking how this app was installed…")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    wrapMode: Text.WordWrap
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: text && !root.checking && !root.running
                text: {
                    if (!root.info)
                        return "";
                    return root.info.removable ? root.description() : root.reasonText();
                }
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
                wrapMode: Text.WordWrap
            }

            StyledText {
                Layout.fillWidth: true
                visible: text && !root.running
                text: root.error
                color: Colours.palette.m3error
                font: Tokens.font.body.small
                wrapMode: Text.WordWrap
            }

            // Options
            ColumnLayout {
                Layout.fillWidth: true
                visible: !!root.info?.removable && !root.checking && !root.running && (root.needsCascade || root.purgeText())
                spacing: Tokens.spacing.extraSmall / 2

                ToggleRow {
                    visible: root.needsCascade
                    first: true
                    last: !root.purgeText()
                    text: Tr.trN("Also uninstall the %n package that needs it", "Also uninstall the %n packages that need it", root.info?.dependents.length ?? 0)
                    subtext: {
                        const blocked = root.info?.cascadeProtected ?? [];
                        if (blocked.length > 0)
                            // TRANSLATORS: %1 = a list of package names
                            return Tr.tr("Not possible, it would remove %1, which the system needs").arg(root.formatList(blocked));
                        // TRANSLATORS: %1 = a list of package names
                        return Tr.tr("Removes %1").arg(root.formatList(root.extraCascade));
                    }
                    disabled: (root.info?.cascadeProtected.length ?? 0) > 0
                    checked: root.cascade
                    onToggled: root.cascade = checked
                }

                ToggleRow {
                    visible: !!root.purgeText()
                    first: !root.needsCascade
                    last: true
                    text: root.purgeText()
                    subtext: root.purgeSubtext()
                    checked: root.purge
                    onToggled: root.purge = checked
                }
            }

            // Buttons
            RowLayout {
                Layout.topMargin: Tokens.spacing.small
                Layout.alignment: Qt.AlignRight
                spacing: Tokens.spacing.extraSmall

                TextButton {
                    type: TextButton.Text
                    isRound: true
                    horizontalPadding: Tokens.padding.largeIncreased
                    verticalPadding: Tokens.padding.medium
                    text: root.info?.removable === false ? Tr.trCtx("Close", "button") : Tr.trCtx("Cancel", "button")
                    onClicked: root.open = false
                }

                TextButton {
                    visible: !!root.error || root.info?.reason === "error"
                    type: TextButton.Text
                    isRound: true
                    horizontalPadding: Tokens.padding.largeIncreased
                    verticalPadding: Tokens.padding.medium
                    disabled: root.checking || root.running
                    text: Tr.trCtx("Try again", "button")
                    onClicked: {
                        root.error = "";
                        root.inspect();
                    }
                }

                TextButton {
                    visible: !!root.info?.removable
                    type: TextButton.Filled
                    isRound: true
                    horizontalPadding: Tokens.padding.largeIncreased
                    verticalPadding: Tokens.padding.medium
                    inactiveColour: Colours.palette.m3error
                    inactiveOnColour: Colours.palette.m3onError
                    disabled: !root.canUninstall
                    text: Uninstaller.actionLabel(root.info)
                    onClicked: {
                        root.error = "";
                        Uninstaller.uninstall(root.app, root.info, root.purge, root.cascade);
                    }
                }
            }
        }
    }
}
