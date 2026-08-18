pragma ComponentBehavior: Bound

import "items"
import QtQuick
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services

// The launcher's clipboard history mode: the list on the left, the focused entry in
// full on the right.
//
// A vertical list rather than the carousel the wallpaper and GIF pickers use, because
// clipboard entries are mostly text and are chosen by reading them. The preview panel
// is the whole point of moving this into the launcher - cliphist's one-line summary
// cannot show an image at all, and truncates text at the first line.
Item {
    id: root

    required property SearchBar search
    required property var screenState
    required property var panels
    required property var content

    readonly property alias list: entryList
    readonly property alias count: entryList.count
    readonly property alias currentItem: entryList.currentItem
    readonly property alias currentIndex: entryList.currentIndex

    readonly property var focused: entryList.model.values[entryList.currentIndex] ?? null
    readonly property bool showPreview: GlobalConfig.clipboard.showPreview

    // Everything after the `>clipboard ` prefix.
    readonly property string query: search.text.split(" ").slice(1).join(" ")

    function decrementCurrentIndex(): void {
        entryList.decrementCurrentIndex();
    }

    function incrementCurrentIndex(): void {
        entryList.incrementCurrentIndex();
    }

    implicitWidth: Tokens.sizes.launcher.clipboardWidth + (showPreview ? Tokens.sizes.launcher.clipboardPreviewWidth + Tokens.spacing.large : 0)

    // Reload on open, since the history changes while the launcher is closed and a
    // stale list is worse here than a brief blank one.
    Component.onCompleted: ClipHistory.refresh()

    StyledListView {
        id: entryList

        objectName: "launcherClipboardList"

        width: Tokens.sizes.launcher.clipboardWidth

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left

        spacing: Tokens.spacing.small
        orientation: Qt.Vertical

        preferredHighlightBegin: 0
        preferredHighlightEnd: height
        highlightRangeMode: ListView.ApplyRange

        highlightFollowsCurrentItem: false
        highlight: StyledRect {
            radius: Tokens.rounding.large
            color: Colours.palette.m3onSurface
            opacity: 0.08

            y: entryList.currentItem?.y ?? 0
            implicitWidth: entryList.width
            implicitHeight: entryList.currentItem?.implicitHeight ?? 0

            Behavior on y {
                Anim {}
            }
        }

        model: ScriptModel {
            id: scriptModel

            values: ClipHistory.query(root.query)
            onValuesChanged: entryList.currentIndex = 0
        }

        delegate: ClipboardItem {
            list: entryList
            screenState: root.screenState
        }

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: entryList
        }
    }

    Loader {
        active: root.showPreview && root.count > 0
        asynchronous: true

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right

        width: Tokens.sizes.launcher.clipboardPreviewWidth

        sourceComponent: ClipboardPreview {
            entry: root.focused
        }
    }
}
