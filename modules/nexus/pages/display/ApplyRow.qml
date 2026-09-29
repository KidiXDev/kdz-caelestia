import QtQuick
import Caelestia.Components
import Caelestia.Config
import Caelestia.I18n
import qs.components.controls
import qs.services

ButtonRow {
    id: root

    property bool showIdentify

    spacing: Tokens.spacing.small

    IconTextButton {
        visible: root.showIdentify
        icon: "screen_search_desktop"
        text: Tr.trCtx("Identify", "button")
        font: Tokens.font.body.large
        isRound: true
        shapeMorph: true
        type: IconTextButton.Tonal
        horizontalPadding: Tokens.padding.extraLarge
        verticalPadding: Tokens.padding.medium
        disabled: Monitors.identifying || Monitors.confirming
        onClicked: Monitors.identify()
    }

    IconTextButton {
        icon: "undo"
        text: Tr.trCtx("Reset", "button")
        font: Tokens.font.body.large
        isRound: true
        shapeMorph: true
        type: IconTextButton.Tonal
        horizontalPadding: Tokens.padding.extraLarge
        verticalPadding: Tokens.padding.medium
        disabled: !Monitors.hasChanges || Monitors.applying || Monitors.confirming
        onClicked: Monitors.discard()
    }

    IconTextButton {
        icon: "check"
        text: Tr.trCtx("Apply", "button")
        font: Tokens.font.body.large
        isRound: true
        shapeMorph: true
        type: IconTextButton.Filled
        horizontalPadding: Tokens.padding.extraLarge
        verticalPadding: Tokens.padding.medium
        disabled: !Monitors.hasChanges || Monitors.applying || Monitors.confirming
        onClicked: Monitors.apply()
    }
}
