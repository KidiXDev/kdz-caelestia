pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Components
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Images
import qs.components
import qs.components.controls
import qs.components.images
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    // Set from the GPUs found in /sys/class/drm
    property string recommendedDecoder
    readonly property bool decoderPending: GlobalConfig.background.videoDecoder !== Wallpapers.appliedDecoder

    // Values match Wallpapers.decoderEnv
    readonly property list<MenuItem> decoderItems: [
        MenuItem {
            text: Tr.tr("Auto") + root.recommendedSuffix(value)
            value: "auto"
        },
        MenuItem {
            text: Tr.tr("Intel Quick Sync (QSV)") + root.recommendedSuffix(value)
            value: "qsv"
        },
        MenuItem {
            text: Tr.tr("VA-API") + root.recommendedSuffix(value)
            value: "vaapi"
        },
        MenuItem {
            text: Tr.tr("NVIDIA NVDEC (CUDA)") + root.recommendedSuffix(value)
            value: "cuda"
        },
        MenuItem {
            text: Tr.tr("Vulkan Video") + root.recommendedSuffix(value)
            value: "vulkan"
        },
        MenuItem {
            text: Tr.tr("Software (CPU)") + root.recommendedSuffix(value)
            value: "software"
        }
    ]
    readonly property var decoderInfo: ({
            qsv: Tr.tr("Intel iGPU and Arc. Stays on the Intel GPU on hybrid laptops."),
            vaapi: Tr.tr("AMD and Intel. Uses the first GPU, which may be NVIDIA on hybrid laptops."),
            cuda: Tr.tr("NVIDIA only. Keeps the NVIDIA GPU awake on hybrid laptops."),
            vulkan: Tr.tr("Experimental, often falls back to software."),
            software: Tr.tr("CPU only. Works everywhere, but uses the most CPU.")
        })

    function recommendedSuffix(value: string): string {
        return value === recommendedDecoder ? ` ${Tr.tr("(Recommended)")}` : "";
    }

    title: Tr.tr("Wallpaper & style")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        StyledClippingRect {
            id: wallWrapper

            Layout.alignment: Qt.AlignHCenter
            implicitWidth: {
                const screen = root.nState.screen;
                return implicitHeight / screen.height * screen.width;
            }
            implicitHeight: {
                const screen = root.nState.screen;
                const cWidth = root.cappedWidth;
                return Math.min(Math.round(cWidth * 0.4), cWidth / screen.width * screen.height);
            }

            color: Colours.tPalette.m3surfaceContainer
            radius: Tokens.rounding.large

            Loader {
                anchors.centerIn: parent
                opacity: Config.background.wallpaperEnabled ? 0 : 1
                active: opacity > 0

                sourceComponent: ColumnLayout {
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "hide_image"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.extraLarge
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Tr.tr("Wallpaper disabled")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.large
                    }
                }

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }
            }

            Item {
                anchors.fill: parent
                opacity: Config.background.wallpaperEnabled ? 1 : 0

                Behavior on opacity {
                    Anim {
                        type: Anim.SlowEffects
                    }
                }

                Loader {
                    id: wallIndicatorLoader

                    anchors.centerIn: parent

                    opacity: 0
                    active: opacity > 0

                    sourceComponent: StyledRect {
                        implicitWidth: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2
                        implicitHeight: wallLoadingIndicator.implicitSize + Tokens.padding.largeIncreased * 2

                        color: Colours.palette.m3primaryContainer
                        radius: Tokens.rounding.full

                        LoadingIndicator {
                            id: wallLoadingIndicator

                            anchors.centerIn: parent
                            containsIcon: true
                            implicitSize: Math.min(wallWrapper.implicitWidth, wallWrapper.implicitHeight) * 0.4
                        }
                    }

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }
                }

                Timer {
                    id: wallLoadDebounceTimer

                    interval: 100
                    onTriggered: {
                        if (wallImg.status !== Image.Ready)
                            wallIndicatorLoader.opacity = 1;
                    }
                }

                FadeImage {
                    id: wallImg

                    anchors.fill: parent
                    source: IUtils.urlForPath(Wallpapers.current, fillMode)
                    preventInit: wallIndicatorLoader.opacity > 0
                    fadeOutAnim: Anim.DefaultEffects
                    fadeInAnim: Anim.SlowEffects

                    onSourceChanged: wallLoadDebounceTimer.restart()

                    onStatusChanged: {
                        if (status === Image.Ready) {
                            wallLoadDebounceTimer.stop();
                            wallIndicatorLoader.opacity = 0;
                        }
                    }
                }
            }
        }

        ButtonRow {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "wallpaper"
                text: Tr.tr("Wallpapers")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                disabled: !Config.background.wallpaperEnabled
                onClicked: root.nState.openSubPage(1) // Wallpaper page
            }

            IconTextButton {
                icon: "palette"
                text: Tr.tr("Colours")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: root.nState.openSubPage(3) // Colours page
            }
        }

        ToggleRow {
            first: true
            text: Tr.tr("Display wallpaper")
            checked: Config.background.wallpaperEnabled
            onToggled: GlobalConfig.background.wallpaperEnabled = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            text: Tr.tr("Transparency")
            // TRANSLATORS: %1/%2 = opacity values from 0 to 1 for the base surface and layered surfaces
            subtext: Tr.tr("Base %1, layers %2").arg(Colours.transparency.base).arg(Colours.transparency.layers)
            checked: Colours.transparency.enabled
            onToggled: GlobalConfig.appearance.transparency.enabled = checked
        }

        ToggleRow {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            last: true
            text: Tr.tr("Dark theme")
            checked: !Colours.light
            onToggled: Colours.setMode(checked ? "dark" : "light")
        }

        SectionHeader {
            text: Tr.tr("Animated wallpapers")
        }

        SelectRow {
            first: true
            label: Tr.tr("Video decoder")
            subtext: root.decoderPending ? Tr.tr("Restart the shell to apply") : Tr.tr("The API used to decode video wallpapers")
            menuItems: root.decoderItems
            active: root.decoderItems.find(i => i.value === GlobalConfig.background.videoDecoder) ?? root.decoderItems[0]
            onSelected: item => GlobalConfig.background.videoDecoder = item.value
        }

        RowButton {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing

            visible: root.decoderPending
            icon: "restart_alt"
            text: Tr.tr("Restart shell")
            subtext: Tr.tr("The decoder is picked when the shell starts")
            onClicked: Quickshell.execDetached(["caelestia", "shell", "-r", "-d"])
        }

        ConnectedRect {
            Layout.topMargin: Tokens.spacing.extraSmall / 2 - parent.spacing
            Layout.fillWidth: true

            last: true
            implicitHeight: decoderInfoLayout.implicitHeight + Tokens.padding.large * 2

            Process {
                running: true
                command: ["sh", "-c", "cat /sys/class/drm/renderD*/device/vendor"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        // Intel QSV keeps decoding off a hybrid laptop's dGPU, so it wins over the others
                        const vendors = text.split("\n");
                        if (vendors.includes("0x8086"))
                            root.recommendedDecoder = "qsv";
                        else if (vendors.includes("0x1002"))
                            root.recommendedDecoder = "vaapi";
                        else if (vendors.includes("0x10de"))
                            root.recommendedDecoder = "cuda";
                        else
                            root.recommendedDecoder = "software";
                    }
                }
            }

            ColumnLayout {
                id: decoderInfoLayout

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.padding.large
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                Repeater {
                    model: root.decoderItems.filter(i => i.value !== "auto")

                    ColumnLayout {
                        id: decoderInfoItem

                        required property MenuItem modelData

                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: decoderInfoItem.modelData.text
                            color: decoderInfoItem.modelData.value === GlobalConfig.background.videoDecoder ? Colours.palette.m3primary : Colours.palette.m3onSurface
                            font: Tokens.font.body.small
                            wrapMode: Text.WordWrap
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.decoderInfo[decoderInfoItem.modelData.value] ?? ""
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }
}
