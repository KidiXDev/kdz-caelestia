pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: Tr.tr("Display")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ArrangementCanvas {
            nState: root.nState
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small - parent.spacing
            horizontalAlignment: Text.AlignHCenter
            text: Tr.tr("Drag a display to move it, click it for more options")
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
            wrapMode: Text.WordWrap
        }

        ApplyRow {
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            Layout.alignment: Qt.AlignHCenter
            showIdentify: true
        }

        Loader {
            Layout.topMargin: Tokens.spacing.large - parent.spacing
            Layout.fillWidth: true
            active: Monitors.includeMissing
            visible: active

            sourceComponent: IncludeBanner {}
        }

        SectionHeader {
            text: Tr.tr("Displays")
        }

        Repeater {
            id: list

            model: Monitors.monitors

            NavRow {
                id: row

                required property var modelData
                required property int index

                first: index === 0
                last: index === list.count - 1
                icon: "monitor"
                text: `${Monitors.displayName(modelData)} (${modelData.name})`
                subtext: Monitors.summary(modelData.name)
                subLabel.color: Monitors.pending[modelData.name] ? Colours.palette.m3primary : Colours.palette.m3outline
                onClicked: {
                    root.nState.selectedMonitor = row.modelData.name;
                    root.nState.openSubPage(1); // Monitor details
                }
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            visible: list.count === 0
            first: true
            last: true
            implicitHeight: empty.implicitHeight + Tokens.padding.extraLarge * 2

            ColumnLayout {
                id: empty

                anchors.centerIn: parent
                width: parent.width - Tokens.padding.largeIncreased * 2
                spacing: Tokens.padding.extraSmall

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "desktop_access_disabled"
                    color: Colours.palette.m3outlineVariant
                    fontStyle: Tokens.font.icon.extraLarge
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: Tr.tr("Unable to get displays from Hyprland")
                    color: Colours.palette.m3outlineVariant
                    font: Tokens.font.body.small
                }
            }
        }
    }
}
