pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services

// Confirmation for new display settings and the identify labels. Shown on every output, so it can still be
// answered if one of them goes black, and it doesn't depend on Nexus staying open.
Scope {
    LazyLoader {
        active: Monitors.confirming || Monitors.identifying

        Variants {
            model: Quickshell.screens

            StyledWindow {
                id: win

                required property ShellScreen modelData
                readonly property var mon: Monitors.monitor(modelData.name)
                readonly property bool focusedOutput: Hypr.focusedMonitor?.name === modelData.name

                screen: modelData
                name: "display-overlay"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.keyboardFocus: Monitors.confirming && focusedOutput ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
                mask: Monitors.confirming ? null : passthrough

                anchors.top: true
                anchors.bottom: true
                anchors.left: true
                anchors.right: true

                Region {
                    id: passthrough
                }

                StyledRect {
                    anchors.fill: parent
                    color: Colours.palette.m3scrim
                    opacity: Monitors.confirming ? 0.5 : 0

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                // Identify
                StyledRect {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: Tokens.padding.extraExtraLarge

                    visible: Monitors.identifying && !Monitors.confirming
                    implicitWidth: identifyLayout.implicitWidth + Tokens.padding.extraLarge * 2
                    implicitHeight: identifyLayout.implicitHeight + Tokens.padding.large * 2
                    radius: Tokens.rounding.extraLarge
                    color: Colours.palette.m3primaryContainer

                    Elevation {
                        anchors.fill: parent
                        radius: parent.radius
                        z: -1
                        level: 3
                    }

                    ColumnLayout {
                        id: identifyLayout

                        anchors.centerIn: parent
                        spacing: 0

                        StyledText {
                            text: win.modelData.name
                            color: Colours.palette.m3onPrimaryContainer
                            font: Tokens.font.headline.large
                        }

                        StyledText {
                            visible: text
                            text: win.mon ? Monitors.displayName(win.mon) : ""
                            color: Colours.palette.m3onPrimaryContainer
                            font: Tokens.font.body.large
                        }
                    }
                }

                // Confirmation
                Item {
                    anchors.fill: parent
                    focus: true
                    visible: Monitors.confirming

                    Keys.onReturnPressed: Monitors.keep()
                    Keys.onEnterPressed: Monitors.keep()
                    Keys.onEscapePressed: Monitors.revert()

                    MouseArea {
                        anchors.fill: parent
                    }

                    StyledRect {
                        anchors.centerIn: parent

                        width: Math.min(parent.width - Tokens.padding.extraExtraLarge * 2, implicitWidth)
                        implicitWidth: confirmLayout.implicitWidth + Tokens.padding.extraLarge * 2
                        implicitHeight: confirmLayout.implicitHeight + Tokens.padding.extraLarge * 2
                        radius: Tokens.rounding.extraLarge
                        color: Colours.palette.m3surfaceContainerHigh

                        scale: 0
                        Component.onCompleted: scale = Qt.binding(() => Monitors.confirming ? 1 : 0)

                        Behavior on scale {
                            Anim {
                                type: Anim.FastSpatial
                            }
                        }

                        Elevation {
                            anchors.fill: parent
                            radius: parent.radius
                            z: -1
                            level: 3
                        }

                        ColumnLayout {
                            id: confirmLayout

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.extraLarge
                            spacing: Tokens.spacing.large

                            RowLayout {
                                spacing: Tokens.spacing.large

                                Item {
                                    implicitWidth: countdown.implicitWidth
                                    implicitHeight: countdown.implicitHeight

                                    CircularProgress {
                                        id: countdown

                                        anchors.fill: parent
                                        implicitSize: seconds.implicitHeight * 2 + thickness
                                        value: Monitors.secondsLeft / Monitors.confirmTimeout

                                        // Ticks once a second, so drain linearly between ticks
                                        Behavior on clampedVal {
                                            NumberAnimation {
                                                duration: 1000
                                            }
                                        }
                                    }

                                    StyledText {
                                        id: seconds

                                        anchors.centerIn: parent
                                        text: Monitors.secondsLeft
                                        color: Colours.palette.m3primary
                                        font: Tokens.font.title.large
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.maximumWidth: Tokens.sizes.nexus.maxDialogWidth
                                    spacing: Tokens.spacing.extraSmall

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Tr.tr("Keep these display settings?")
                                        font: Tokens.font.title.medium
                                        wrapMode: Text.WordWrap
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Tr.trN("Reverting to the previous settings in %n second.", "Reverting to the previous settings in %n seconds.", Monitors.secondsLeft)
                                        color: Colours.palette.m3onSurfaceVariant
                                        font: Tokens.font.body.small
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignRight
                                spacing: Tokens.spacing.small

                                TextButton {
                                    type: TextButton.Text
                                    isRound: true
                                    horizontalPadding: Tokens.padding.largeIncreased
                                    verticalPadding: Tokens.padding.medium
                                    text: Tr.trCtx("Revert", "button")
                                    onClicked: Monitors.revert()
                                }

                                TextButton {
                                    type: TextButton.Filled
                                    isRound: true
                                    horizontalPadding: Tokens.padding.largeIncreased
                                    verticalPadding: Tokens.padding.medium
                                    text: Tr.trCtx("Keep changes", "button")
                                    onClicked: Monitors.keep()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
