pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property string query: search.text.trim().toLowerCase()

    function matches(app: DesktopEntry): bool {
        return !query || [app.name, app.genericName, app.id].some(s => s?.toLowerCase().includes(query));
    }

    title: Tr.tr("All apps")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SearchBar {
            id: search

            Layout.fillWidth: true
            Layout.bottomMargin: Tokens.spacing.large - parent.spacing

            placeholderText: Tr.tr("Search apps")
            font: Tokens.font.body.large
            searchIcon.fontStyle: Tokens.font.icon.medium
        }

        Repeater {
            id: list

            model: [...DesktopEntries.applications.values].filter(a => root.matches(a)).sort((a, b) => a.name.localeCompare(b.name))

            ConnectedRect {
                id: appItem

                required property DesktopEntry modelData
                required property int index

                Layout.fillWidth: true
                first: index === 0
                last: index === list.count - 1
                implicitHeight: appRow.implicitHeight + appRow.anchors.margins * 2

                StateLayer {
                    onClicked: {
                        root.nState.selectedApp = appItem.modelData;
                        root.nState.openSubPage(2);
                    }
                }

                RowLayout {
                    id: appRow

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    anchors.leftMargin: Tokens.padding.largeIncreased
                    anchors.rightMargin: Tokens.padding.largeIncreased
                    spacing: Tokens.spacing.medium

                    IconImage {
                        asynchronous: true
                        implicitSize: Math.round(Tokens.font.icon.large.pointSize * 1.8)
                        source: Quickshell.iconPath(appItem.modelData.icon, "image-missing")
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: appItem.modelData.name
                            font: Tokens.font.body.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: text
                            text: (appItem.modelData.comment || appItem.modelData.genericName) ?? ""
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    MaterialIcon {
                        visible: Strings.testRegexList(GlobalConfig.launcher.favouriteApps, appItem.modelData.id)
                        text: "favorite"
                        fill: 1
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.small
                    }

                    LoadingIndicator {
                        visible: Uninstaller.busyAppId === appItem.modelData.id
                        implicitSize: uninstallBtn.implicitHeight
                    }

                    IconButton {
                        id: uninstallBtn

                        visible: Uninstaller.busyAppId !== appItem.modelData.id
                        icon: "delete"
                        type: IconButton.Text
                        onClicked: uninstallDialog.openFor(appItem.modelData)
                    }

                    MaterialIcon {
                        text: "chevron_right"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.medium
                    }
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
                    text: "search_off"
                    color: Colours.palette.m3outlineVariant
                    fontStyle: Tokens.font.icon.extraLarge
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: root.query ? Tr.tr("No apps match \"%1\"").arg(search.text.trim()) : Tr.tr("No apps installed")
                    color: Colours.palette.m3outlineVariant
                    font: Tokens.font.body.small
                }
            }
        }

        UninstallDialog {
            id: uninstallDialog

            rootParent: root.flickable
        }
    }
}
