pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

ItemList {
    id: root

    property var nodes: []
    property int currentId: -1
    property string iconName: "speaker"

    signal selected(node: PwNode)

    last: true
    showList: true

    model: ScriptModel {
        values: [...root.nodes].sort((a, b) => Audio.deviceName(a).localeCompare(Audio.deviceName(b)))
    }

    delegate: Item {
        id: device

        required property PwNode modelData
        required property int index
        readonly property bool active: device.modelData?.id === root.currentId
        property bool editing: false

        function commit(): void {
            Audio.renameDevice(device.modelData, nameField.text);
            device.editing = false;
        }

        anchors.left: root.list.contentItem.left
        anchors.right: root.list.contentItem.right
        implicitHeight: deviceLayout.implicitHeight + deviceLayout.anchors.margins * 2

        StateLayer {
            radius: Tokens.rounding.extraSmall
            bottomLeftRadius: device.index === root?.list.count - 1 ? Tokens.rounding.extraLarge : radius
            bottomRightRadius: device.index === root?.list.count - 1 ? Tokens.rounding.extraLarge : radius
            onClicked: root.selected(device.modelData)
        }

        RowLayout {
            id: deviceLayout

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            anchors.leftMargin: Tokens.padding.largeIncreased
            anchors.rightMargin: Tokens.padding.largeIncreased
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: implicitHeight
                implicitHeight: devIcon.implicitHeight + Tokens.padding.small * 2
                radius: Tokens.rounding.full
                color: device.active ? Colours.palette.m3primary : Colours.palette.m3secondaryContainer

                MaterialIcon {
                    id: devIcon

                    anchors.centerIn: parent
                    text: root.iconName
                    color: device.active ? Colours.palette.m3onPrimary : Colours.palette.m3onSecondaryContainer
                    fontStyle: Tokens.font.icon.medium
                    fill: device.active ? 1 : 0

                    Behavior on fill {
                        Anim {}
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: !device.editing
                text: Audio.deviceName(device.modelData)
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledTextField {
                id: nameField

                Layout.fillWidth: true
                visible: device.editing
                verticalPadding: Tokens.padding.small
                placeholderText: device.modelData?.description || device.modelData?.name || ""
                supportingText: Tr.tr("Enter to save, Esc to cancel, empty to reset")
                onAccepted: device.commit()
                Keys.onEscapePressed: device.editing = false
                onActiveFocusChanged: {
                    if (!activeFocus)
                        device.editing = false;
                }
            }

            IconButton {
                type: IconButton.Text
                isRound: true
                icon: device.editing ? "check" : "edit"
                font: Tokens.font.icon.medium
                label.fill: 0
                onClicked: {
                    if (device.editing) {
                        device.commit();
                    } else {
                        nameField.text = Audio.customNames[device.modelData?.name] ?? "";
                        device.editing = true;
                        nameField.forceActiveFocus();
                    }
                }
            }

            MaterialIcon {
                text: "check"
                color: Colours.palette.m3primary
                fontStyle: Tokens.font.icon.medium
                opacity: device.active ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }
        }
    }
}
