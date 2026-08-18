pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// A Hyprland colour option: label, live swatch, free-text value.
//
// Deliberately a text field rather than a colour wheel. Hyprland colours are not
// just colours - `general:col.active_border` takes a gradient of any number of
// stops plus an angle ("rgba(aabbccdd) rgba(11223344) 45deg"), and the shell's own
// config sets exactly that. A picker would silently flatten gradients to one stop,
// so the field stays authoritative and the swatch is a read-only preview of the
// first stop.
ConnectedRect {
    id: root

    property alias label: label.text
    property string subtext
    property string value

    // Hyprland *reports* colours as bare AARRGGBB hex words, but *accepts* rgba()/
    // rgb()/0x forms too, so the preview has to read all of them. Note the digit
    // order differs: 8 hex digits are AARRGGBB when bare or 0x-prefixed, but
    // RRGGBBAA inside rgba().
    readonly property color swatch: {
        const s = `${value}`.trim();
        const m = s.match(/(?:rgba\(|rgb\(|0x)?([0-9a-fA-F]{6,8})\)?/);
        if (!m)
            return "transparent";

        const h = m[1];
        if (h.length === 8)
            return s.startsWith("rgba(") ? `#${h.slice(6)}${h.slice(0, 6)}` : `#${h}`;
        return `#${h}`;
    }

    signal editingFinished(value: string)

    Layout.fillWidth: true
    implicitHeight: row.implicitHeight + Tokens.padding.large * 2

    Component.onDestruction: {
        if (value !== input.text)
            editingFinished(input.text);
    }

    RowLayout {
        id: row

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Tokens.padding.largeIncreased
        anchors.rightMargin: Tokens.padding.largeIncreased
        spacing: Tokens.spacing.medium

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                id: label

                Layout.fillWidth: true
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.subtext
                text: root.subtext
                color: Colours.palette.m3outline
                font: Tokens.font.label.small
                elide: Text.ElideRight
            }
        }

        // Chequerboard behind the swatch, so alpha is visible rather than blending
        // into the surface and reading as an opaque darker colour.
        StyledClippingRect {
            id: swatchTile

            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Tokens.padding.large * 2
            implicitHeight: implicitWidth
            radius: Tokens.rounding.full
            color: Colours.palette.m3surfaceContainerHighest

            Grid {
                anchors.centerIn: parent
                columns: 4
                rows: 4

                Repeater {
                    model: 16

                    Rectangle {
                        required property int index

                        implicitWidth: Tokens.padding.large / 2
                        implicitHeight: implicitWidth
                        color: (index % 4 + Math.floor(index / 4)) % 2 === 0 ? Colours.palette.m3outlineVariant : "transparent"
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                // StyledClippingRect wraps its children, so `parent` here is that wrapper
                // rather than the tile - address the tile by id.
                radius: swatchTile.radius
                color: root.swatch
                border.width: 1
                border.color: Qt.alpha(Colours.palette.m3outline, 0.5)
            }
        }

        StyledTextField {
            id: input

            Layout.preferredWidth: Tokens.sizes.nexus.textFieldWidth
            Layout.maximumWidth: root.width / 2
            Layout.alignment: Qt.AlignVCenter
            verticalPadding: Tokens.padding.small

            text: root.value
            placeholderText: "rgba(11111100)"

            onEditingFinished: root.editingFinished(text)
        }
    }
}
