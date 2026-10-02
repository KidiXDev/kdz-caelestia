pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Components
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services
import qs.modules.nexus.common

// Add or edit a VPN provider. editingVpnIndex (-1 = add) is read from NexusState.
PageBase {
    id: root

    readonly property int editIndex: nState.editingVpnIndex
    readonly property bool editing: editIndex >= 0
    readonly property var existing: editing ? (VPN.providers[editIndex] ?? null) : null
    readonly property bool isOpenVpn: nameField.text.trim() === "openvpn"
    property bool importing

    function splitCmd(arr: var): string {
        return arr?.join(" ") ?? "";
    }

    function joinCmd(str: string): var {
        const t = str.trim();
        return t.length > 0 ? t.split(/\s+/) : [];
    }

    function arrEq(a: var, b: var): bool {
        return a.length === b.length && a.every((x, i) => x === b[i]);
    }

    function submit(): void {
        const name = nameField.text.trim();
        if (name.length === 0) {
            nameField.isError = true;
            nameField.forceActiveFocus();
            return;
        }

        if (!isOpenVpn)
            return save();

        // OpenVPN: import the config and/or store credentials in NetworkManager
        // first, then save the provider pointing at the resulting connection.
        const file = ovpnField.text.trim();
        const conn = interfaceField.text.trim();
        if (!file && !conn) {
            ovpnField.isError = true;
            ovpnField.forceActiveFocus();
            return;
        }
        if (!file && !userField.text && !passField.text)
            return save();

        importing = true;
        VPN.importOpenVpn(file, conn, userField.text, passField.text, connName => {
            importing = false;
            if (!connName)
                return;
            interfaceField.text = connName;
            save();
        });
    }

    function save(): void {
        const name = nameField.text.trim();
        const data = {
            name: name,
            displayName: displayField.text.trim() || (isOpenVpn ? interfaceField.text.trim() : "") || name,
            interface: interfaceField.text.trim(),
            connectCmd: joinCmd(connectField.text),
            disconnectCmd: joinCmd(disconnectField.text)
        };

        if (editing) {
            const needsReload = existing.id === VPN.selectedProvider && VPN.connected && (existing.name !== name || existing.interface !== data.interface || !arrEq(existing.connectCmd, data.connectCmd) || !arrEq(existing.disconnectCmd, data.disconnectCmd));
            if (needsReload)
                VPN.disconnect();
            VPN.updateProvider(editIndex, data);
            if (needsReload) {
                if (!VPN.connecting && !VPN.disconnecting) {
                    VPN.connect();
                } else if (VPN.disconnecting) {
                    let onConnChanged = () => {
                        if (onConnChanged && !VPN.disconnecting) {
                            VPN.disconnectingChanged.disconnect(onConnChanged);
                            onConnChanged = null;
                            if (!VPN.connected)
                                VPN.connect();
                        }
                    };
                    VPN.disconnectingChanged.connect(onConnChanged);
                }
            }
        } else {
            VPN.addProvider(data);
        }

        nState.closeSubPage();
    }

    title: editing ? Tr.tr("Edit VPN provider") : Tr.tr("Add VPN provider")
    isSubPage: true

    Component.onCompleted: {
        if (existing) {
            nameField.text = existing.name;
            displayField.text = existing.displayName;
            interfaceField.text = existing.interface;
            connectField.text = splitCmd(existing.connectCmd);
            disconnectField.text = splitCmd(existing.disconnectCmd);
        }
    }

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            // TRANSLATORS: the five names in brackets are provider identifiers, leave them untranslated
            text: Tr.tr("Built-in names (wireguard, warp, tailscale, netbird, openvpn) auto-fill their commands. For others, provide the connect/disconnect commands.")
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            wrapMode: Text.WordWrap
        }

        StyledTextField {
            id: nameField

            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            placeholderText: Tr.tr("Provider name")
            leadingIcon: "vpn_key"
            // TRANSLATORS: id here means the provider identifier, e.g. wireguard
            supportingText: Tr.tr("Built-in id or a custom name")
            errorText: Tr.tr("Provider name is required")
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

            onAccepted: displayField.forceActiveFocus()
        }

        StyledTextField {
            id: displayField

            Layout.fillWidth: true
            placeholderText: Tr.tr("Display name")
            // TRANSLATORS: the name shown in the VPN provider list on the network page
            supportingText: Tr.tr("Shown in the list")
            leadingIcon: "label"
            inputMethodHints: Qt.ImhNoPredictiveText

            onAccepted: interfaceField.forceActiveFocus()
        }

        StyledTextField {
            id: interfaceField

            Layout.fillWidth: true
            placeholderText: root.isOpenVpn ? Tr.tr("Connection name") : Tr.trCtx("Interface", "network interface")
            leadingIcon: "lan"
            supportingText: root.isOpenVpn ? Tr.tr("NetworkManager connection, filled in on import") : Tr.tr("Network interface (for WireGuard / status checks)")
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

            onAccepted: connectField.forceActiveFocus()
        }

        SectionHeader {
            visible: root.isOpenVpn
            text: Tr.tr("OpenVPN")
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.isOpenVpn
            spacing: Tokens.spacing.small

            StyledTextField {
                id: ovpnField

                Layout.fillWidth: true
                placeholderText: Tr.tr("Config file (.ovpn)")
                leadingIcon: "description"
                supportingText: root.editing ? Tr.tr("Optional, imports a new connection") : Tr.tr("Imported into NetworkManager")
                errorText: Tr.tr("Pick a config file or enter a connection name")
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

                onAccepted: userField.forceActiveFocus()
            }

            IconButton {
                Layout.alignment: Qt.AlignTop
                type: IconButton.Tonal
                isRound: true
                icon: "folder_open"
                onClicked: ovpnDialog.open()
            }

            FileDialog {
                id: ovpnDialog

                title: Tr.tr("Select an OpenVPN config")
                filterLabel: Tr.tr("OpenVPN configs")
                filters: ["ovpn", "conf"]
                onAccepted: path => {
                    ovpnField.text = path;
                    ovpnField.isError = false;
                }
            }
        }

        StyledTextField {
            id: userField

            Layout.fillWidth: true
            visible: root.isOpenVpn
            placeholderText: Tr.tr("Username")
            leadingIcon: "person"
            supportingText: root.editing ? Tr.tr("Leave empty to keep the saved one") : ""
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

            onAccepted: passField.forceActiveFocus()
        }

        StyledTextField {
            id: passField

            Layout.fillWidth: true
            visible: root.isOpenVpn
            placeholderText: Tr.tr("Password")
            leadingIcon: "password"
            supportingText: Tr.tr("Stored by NetworkManager")
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText

            onAccepted: root.submit()
        }

        SectionHeader {
            text: Tr.tr("Custom commands (optional)")
        }

        StyledTextField {
            id: connectField

            Layout.fillWidth: true
            placeholderText: Tr.tr("Connect command")
            leadingIcon: "play_arrow"
            supportingText: Tr.tr("Leave empty to use the built-in default")
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

            onAccepted: disconnectField.forceActiveFocus()
        }

        StyledTextField {
            id: disconnectField

            Layout.fillWidth: true
            placeholderText: Tr.tr("Disconnect command")
            leadingIcon: "stop"
            supportingText: Tr.tr("Leave empty to use the built-in default")
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

            onAccepted: root.submit()
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: (root.editing ? Tokens.spacing.medium : Tokens.spacing.extraSmall) - parent.spacing
            spacing: Tokens.spacing.small

            IconTextButton {
                visible: root.editing
                isRound: true
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                inactiveColour: Colours.palette.m3errorContainer
                inactiveOnColour: Colours.palette.m3onErrorContainer
                iconLabel.fill: 1
                iconLabel.grade: 25
                icon: "delete_forever"
                text: Tr.tr("Delete")
                onClicked: {
                    if (root.existing.id === VPN.selectedProvider && VPN.connected)
                        VPN.disconnect();
                    VPN.deleteProvider(root.editIndex);
                    root.nState.closeSubPage();
                }
            }

            Item {
                Layout.fillWidth: true
            }

            ButtonRow {
                spacing: parent.spacing

                TextButton {
                    isRound: true
                    shapeMorph: true
                    horizontalPadding: Tokens.padding.extraLarge
                    verticalPadding: Tokens.padding.medium
                    type: TextButton.Tonal
                    text: Tr.trCtx("Cancel", "button")
                    onClicked: root.nState.closeSubPage()
                }

                TextButton {
                    isRound: true
                    shapeMorph: true
                    horizontalPadding: Tokens.padding.extraLarge
                    verticalPadding: Tokens.padding.medium
                    text: root.importing ? Tr.tr("Importing…") : root.editing ? Tr.trCtx("Save", "button") : Tr.trCtx("Add", "button")
                    disabled: !nameField.text.trim() || root.importing
                    onClicked: root.submit()
                }
            }
        }
    }
}
