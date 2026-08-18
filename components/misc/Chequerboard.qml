import QtQuick
import qs.services

// The alternating grid drawn behind anything that can be partly transparent.
//
// Without it, a half-transparent colour or a screenshot with an alpha channel blends
// into the surface behind it and reads as an opaque darker shade, or as nothing at
// all - which is indistinguishable from a failed load.
Grid {
    id: root

    property int cellSize: Tokens.padding.large / 2
    property color cellColour: Colours.palette.m3outlineVariant

    columns: Math.max(1, Math.ceil(width / cellSize))
    rows: Math.max(1, Math.ceil(height / cellSize))

    Repeater {
        model: root.columns * root.rows

        Rectangle {
            required property int index

            implicitWidth: root.cellSize
            implicitHeight: root.cellSize
            color: (index % root.columns + Math.floor(index / root.columns)) % 2 === 0 ? root.cellColour : "transparent"
        }
    }
}
