pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property string name: root.nState.selectedMonitor
    readonly property var mon: Monitors.monitor(name)
    readonly property var st: mon ? Monitors.state(name) : null
    readonly property bool active: !!st && !st.disabled
    readonly property var rates: st ? Monitors.rates(mon, st.width, st.height) : []

    title: mon ? Monitors.displayName(mon) : Tr.tr("Display")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        ConnectedRect {
            Layout.fillWidth: true
            visible: !root.mon
            first: true
            last: true
            implicitHeight: gone.implicitHeight + Tokens.padding.extraLarge * 2

            ColumnLayout {
                id: gone

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
                    text: Tr.tr("This display is no longer connected")
                    color: Colours.palette.m3outlineVariant
                    font: Tokens.font.body.small
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: !!root.mon
            spacing: parent.spacing

            // Output
            SectionHeader {
                first: true
                text: Tr.tr("Output")
            }

            ToggleRow {
                first: true
                last: !root.active
                text: Tr.tr("Use this display")
                subtext: root.st && !root.st.disabled && !Monitors.canDisable(root.name) ? Tr.tr("At least one display has to stay on") : Monitors.summary(root.name)
                checked: root.active
                disabled: Monitors.confirming || (root.active && !Monitors.canDisable(root.name))
                onToggled: Monitors.setDisabled(root.name, !checked)
            }

            DialogSelectButton {
                visible: root.active
                rootParent: root.flickable
                icon: "aspect_ratio"
                label: Tr.tr("Resolution")
                subtext: root.st ? Monitors.resolutionLabel(root.st.width, root.st.height) : ""
                header: Tr.tr("Resolution")
                acceptLabel: Tr.trCtx("Select", "button")
                model: root.mon ? Monitors.resolutions(root.mon).map(r => ({
                            id: `${r.width}x${r.height}`,
                            label: r.width === root.st?.width && r.height === root.st?.height ? Tr.tr("%1 (current)").arg(Monitors.resolutionLabel(r.width, r.height)) : Monitors.resolutionLabel(r.width, r.height)
                        })) : []
                onAccepted: {
                    if (!selectedItem)
                        return;

                    const [width, height] = selectedItem.split("x").map(Number);
                    Monitors.setMode(root.name, width, height, Monitors.nearestRate(root.mon, width, height, root.st.rate));
                }
            }

            // Mode
            SectionHeader {
                visible: root.active
                text: Tr.tr("Mode")
            }

            SelectRow {
                visible: root.active
                first: true
                label: Tr.tr("Refresh rate")
                subtext: Tr.tr("How many times per second the display updates")
                active: menuItems.find(i => Monitors.sameValue("rate", i.value, root.st?.rate ?? 0)) ?? null
                fallbackText: root.st ? Monitors.rateLabel(root.st.rate) : ""
                onSelected: item => Monitors.setMode(root.name, root.st.width, root.st.height, item.value)

                menuItems: rateItems.instances

                Variants {
                    id: rateItems

                    model: root.rates

                    MenuItem {
                        required property real modelData

                        text: Monitors.rateLabel(modelData)
                        value: modelData
                    }
                }
            }

            SelectRow {
                visible: root.active
                label: Tr.tr("Rotation")
                subtext: Tr.tr("Orientation of the picture")
                active: menuItems.find(i => i.value === root.st?.transform) ?? null
                menuOnTop: true
                onSelected: item => Monitors.setTransform(root.name, item.value)

                menuItems: transformItems.instances

                Variants {
                    id: transformItems

                    model: [0, 1, 2, 3, 4, 5, 6, 7]

                    MenuItem {
                        required property int modelData

                        text: Monitors.transformLabel(modelData)
                        value: modelData
                    }
                }
            }

            DialogSelectButton {
                visible: root.active
                rootParent: root.flickable
                icon: "zoom_in"
                label: Tr.tr("Scale")
                subtext: root.st ? Monitors.scaleLabel(root.st.scale) : ""
                header: Tr.tr("Scale")
                acceptLabel: Tr.trCtx("Select", "button")
                model: root.st ? Monitors.scaleOptions(root.st).map(s => ({
                            id: String(s),
                            label: Monitors.sameValue("scale", s, root.st.scale) ? Tr.tr("%1 (current)").arg(Monitors.scaleLabel(s)) : Monitors.scaleLabel(s)
                        })) : []
                onAccepted: {
                    if (selectedItem)
                        Monitors.setScale(root.name, Number(selectedItem));
                }
            }

            ApplyRow {
                Layout.topMargin: Tokens.spacing.large - parent.spacing
                Layout.alignment: Qt.AlignHCenter
            }

            // Details
            SectionHeader {
                text: Tr.tr("Details")
            }

            InfoRow {
                first: true
                label: Tr.tr("Connector")
                value: root.mon?.name ?? ""
            }

            InfoRow {
                visible: !!root.mon?.make
                label: Tr.tr("Manufacturer")
                value: root.mon?.make ?? ""
            }

            InfoRow {
                visible: !!root.mon?.model
                label: Tr.tr("Model")
                value: root.mon?.model ?? ""
            }

            InfoRow {
                visible: !!root.mon?.serial
                label: Tr.tr("Serial number")
                value: root.mon?.serial ?? ""
            }

            InfoRow {
                visible: (root.mon?.physicalWidth ?? 0) > 0
                label: Tr.tr("Physical size")
                // TRANSLATORS: %1 = width, %2 = height, in millimetres
                value: Tr.tr("%1 × %2 mm").arg(root.mon?.physicalWidth ?? 0).arg(root.mon?.physicalHeight ?? 0)
            }

            InfoRow {
                last: true
                label: Tr.tr("Configured in")
                subtext: Tr.tr("Where the Hyprland rule for this display comes from")
                value: root.mon ? Monitors.ruleSource(root.mon) : ""
            }
        }
    }
}
