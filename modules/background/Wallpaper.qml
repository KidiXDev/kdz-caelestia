pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.filedialog
import qs.components.images
import qs.services
import qs.utils

Item {
    id: root

    property string source: Wallpapers.current
    property bool paused
    property WallLayer current
    property bool completed

    onSourceChanged: {
        if (!source)
            current = null;
        else
            current = imgComp.createObject(this, {
                path: source
            });
    }

    Component.onCompleted: {
        if (source)
            Qt.callLater(() => {
                current = imgComp.createObject(this, {
                    path: source
                });
                completed = true;
            });
    }

    Loader {
        asynchronous: true
        anchors.fill: parent

        active: root.completed && !root.source

        sourceComponent: StyledRect {
            color: Colours.palette.m3surfaceContainer

            Row {
                anchors.centerIn: parent
                spacing: Tokens.spacing.largeIncreased

                MaterialIcon {
                    text: "sentiment_stressed"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.builders.extraLarge.scale(5).build()
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacing.small

                    StyledText {
                        text: Tr.tr("Wallpaper missing?")
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.body.builders.large.size(28 * 2).weight(Font.Bold).build()
                    }

                    StyledRect {
                        implicitWidth: selectWallText.implicitWidth + Tokens.padding.extraLargeIncreased
                        implicitHeight: selectWallText.implicitHeight + Tokens.padding.small

                        radius: Tokens.rounding.full
                        color: Colours.palette.m3primary

                        FileDialog {
                            id: dialog

                            title: Tr.tr("Select a wallpaper")
                            filterLabel: Tr.tr("Image files")
                            filters: [...Images.validImageExtensions, "gif", ...Images.validVideoExtensions]
                            onAccepted: path => Wallpapers.setWallpaper(path)
                        }

                        StateLayer {
                            radius: parent.radius
                            color: Colours.palette.m3onPrimary
                            onClicked: dialog.open()
                        }

                        StyledText {
                            id: selectWallText

                            anchors.centerIn: parent

                            text: Tr.tr("Set it now!")
                            color: Colours.palette.m3onPrimary
                            font: Tokens.font.body.large
                        }
                    }
                }
            }
        }
    }

    Component {
        id: imgComp

        WallLayer {}
    }

    component WallLayer: Item {
        id: img

        property string path
        property bool failed
        // A video that can't play falls back to its first frame as a still image
        readonly property bool animated: Images.isAnimated(path) && !failed
        readonly property bool ready: animated ? (video.item?.ready ?? false) : still.status === Image.Ready

        function fail(reason: string): void {
            failed = true;
            Wallpapers.reportVideoFailure(path, reason);
        }

        anchors.fill: parent

        opacity: 0

        onReadyChanged: {
            if (ready)
                anim.start();
        }

        CachingImage {
            id: still

            anchors.fill: parent
            path: img.animated ? "" : img.path
        }

        Loader {
            id: video

            anchors.fill: parent
            active: img.animated

            // FFmpeg backend decodes on the GPU API set by Wallpapers.decoderEnv, or in software if it fails
            sourceComponent: VideoOutput {
                id: output

                property bool ready
                // Keep playing until the first frame is shown so the fade in has something to show
                readonly property bool shouldPlay: !ready || !root.paused

                fillMode: VideoOutput.PreserveAspectCrop

                onShouldPlayChanged: shouldPlay ? player.play() : player.pause()

                MediaPlayer {
                    id: player

                    // No audioOutput, so audio is never decoded
                    source: `file://${img.path.split("/").map(encodeURIComponent).join("/")}`
                    videoOutput: output
                    loops: MediaPlayer.Infinite
                    Component.onCompleted: play()
                    onErrorOccurred: (error, errorString) => img.fail(errorString)
                }

                // Catches decoders that hang without reporting an error
                Timer {
                    running: !output.ready
                    interval: 15000
                    onTriggered: img.fail("no frame decoded after 15 seconds")
                }

                Connections {
                    function onVideoFrameChanged(): void {
                        output.ready = true;
                    }

                    target: output.videoSink
                    enabled: !output.ready
                }
            }
        }

        Anim on opacity {
            id: anim

            type: Anim.SlowEffects
            running: false
            from: 0
            to: 1
        }

        Timer {
            running: root.current !== img && (root.current?.ready ?? false)
            interval: anim.duration
            onTriggered: img.destroy()
        }
    }
}
