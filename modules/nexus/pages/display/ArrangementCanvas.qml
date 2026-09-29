pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.effects
import qs.services
import qs.modules.nexus

// Scaled down view of the output layout, drag an output to move it
StyledClippingRect {
    id: root

    required property NexusState nState

    readonly property var rects: Monitors.layout
    readonly property var bounds: {
        if (rects.length === 0)
            return {
                x: 0,
                y: 0,
                w: 1,
                h: 1
            };
        const minX = Math.min(...rects.map(r => r.x));
        const minY = Math.min(...rects.map(r => r.y));
        return {
            x: minX,
            y: minY,
            w: Math.max(...rects.map(r => r.x + r.w)) - minX,
            h: Math.max(...rects.map(r => r.y + r.h)) - minY
        };
    }
    readonly property real factor: Math.max(0.0001, Math.min((width - Tokens.padding.extraExtraLarge * 2) / bounds.w, (height - Tokens.padding.extraExtraLarge * 2) / bounds.h))
    readonly property real offsetX: (width - bounds.w * factor) / 2 - bounds.x * factor
    readonly property real offsetY: (height - bounds.h * factor) / 2 - bounds.y * factor

    Layout.fillWidth: true
    implicitHeight: Math.round(width * 0.4)

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.large

    StyledText {
        anchors.centerIn: parent
        visible: root.rects.length === 0
        text: Tr.tr("No displays found")
        color: Colours.palette.m3outline
        font: Tokens.font.body.large
    }

    Repeater {
        model: ScriptModel {
            values: root.rects.map(r => r.name)
        }

        StyledRect {
            id: tile

            required property string modelData
            readonly property var rect: root.rects.find(r => r.name === modelData) ?? {
                x: 0,
                y: 0,
                w: 0,
                h: 0
            }
            readonly property real targetX: root.offsetX + rect.x * root.factor
            readonly property real targetY: root.offsetY + rect.y * root.factor
            readonly property bool held: mouse.drag.active
            readonly property bool changed: !!Monitors.pending[modelData]

            x: targetX
            y: targetY
            z: held ? 1 : 0
            implicitWidth: rect.w * root.factor
            implicitHeight: rect.h * root.factor

            radius: Tokens.rounding.small
            color: held || mouse.containsMouse ? Colours.palette.m3primaryContainer : Colours.palette.m3secondaryContainer
            border.width: changed ? 2 : 0
            border.color: Colours.palette.m3primary

            Behavior on x {
                enabled: !tile.held

                Anim {}
            }

            Behavior on y {
                enabled: !tile.held

                Anim {}
            }

            Behavior on implicitWidth {
                Anim {}
            }

            Behavior on implicitHeight {
                Anim {}
            }

            Behavior on color {
                CAnim {}
            }

            Elevation {
                anchors.fill: parent
                radius: parent.radius
                z: -1
                level: tile.held ? 3 : 0
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - Tokens.padding.small * 2
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: tile.modelData
                    color: tile.held || mouse.containsMouse ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSecondaryContainer
                    font: Tokens.font.title.small
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: tile.height > implicitHeight * 3
                    horizontalAlignment: Text.AlignHCenter
                    text: {
                        const st = Monitors.state(tile.modelData);
                        return st ? Monitors.resolutionLabel(st.width, st.height) : "";
                    }
                    color: tile.held || mouse.containsMouse ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSecondaryContainer
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }

            MouseArea {
                id: mouse

                property bool dragged

                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                enabled: !Monitors.confirming
                cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor

                drag.target: tile
                drag.minimumX: -tile.width / 2
                drag.maximumX: root.width - tile.width / 2
                drag.minimumY: -tile.height / 2
                drag.maximumY: root.height - tile.height / 2

                onPressed: dragged = false
                onPositionChanged: {
                    if (drag.active)
                        dragged = true;
                }
                onReleased: {
                    if (!dragged)
                        return;

                    // Snap into place, then hand the position back to the binding so it animates there
                    Monitors.setPosition(tile.modelData, Math.round((tile.x - root.offsetX) / root.factor), Math.round((tile.y - root.offsetY) / root.factor));
                    tile.x = Qt.binding(() => tile.targetX);
                    tile.y = Qt.binding(() => tile.targetY);
                }
                onClicked: {
                    if (dragged)
                        return;
                    root.nState.selectedMonitor = tile.modelData;
                    root.nState.openSubPage(1); // Monitor details
                }
            }
        }
    }
}
