import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

// Shown when saved display settings exist but the Hyprland config doesn't load them
ConnectedRect {
    id: root

    first: true
    last: true
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2
    color: Colours.palette.m3secondaryContainer

    RowLayout {
        id: layout

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Tokens.padding.largeIncreased
        spacing: Tokens.spacing.medium

        MaterialIcon {
            text: "info"
            color: Colours.palette.m3onSecondaryContainer
            fontStyle: Tokens.font.icon.medium
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: Tr.tr("Saved display settings aren't loaded by Hyprland")
                color: Colours.palette.m3onSecondaryContainer
                font: Tokens.font.body.small
                wrapMode: Text.WordWrap
            }

            StyledText {
                Layout.fillWidth: true
                text: {
                    const include = Monitors.usingLua ? `require("hypr-monitors")` : `source = ${Paths.shortenHome(Monitors.managedFile)}`;
                    if (Monitors.userFileExists)
                        // TRANSLATORS: %1 = a line of Hyprland config, %2 = a file path
                        return Tr.tr("Add %1 to %2 so they are kept after Hyprland reloads").arg(include).arg(Paths.shortenHome(Monitors.userFile));
                    // TRANSLATORS: %1 = a line of Hyprland config
                    return Tr.tr("Add %1 to your Hyprland config so they are kept after it reloads").arg(include);
                }
                color: Colours.palette.m3onSecondaryContainer
                font: Tokens.font.label.small
                wrapMode: Text.WordWrap
            }
        }

        TextButton {
            visible: Monitors.userFileExists
            type: TextButton.Filled
            isRound: true
            horizontalPadding: Tokens.padding.large
            verticalPadding: Tokens.padding.small
            text: Tr.trCtx("Add", "button")
            onClicked: Monitors.addInclude()
        }
    }
}
