pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.misc
import qs.services

// One clipboard history row.
//
// Text entries show cliphist's own preview line, which is the entry's first line
// truncated. Image entries show an actual thumbnail, decoded lazily - that is the
// whole reason this mode exists, since the alternative is the string
// "[[ binary data 210 KiB png 1918x1033 ]]".
Item {
    id: root

    required property var modelData
    required property ListView list
    required property ScreenState screenState

    readonly property bool isImage: modelData?.isImage ?? false
    readonly property bool wantsThumb: ClipHistory.shouldPreview(modelData)

    implicitHeight: Tokens.sizes.launcher.itemHeight

    anchors.left: parent?.left
    anchors.right: parent?.right

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: {
            ClipHistory.copy(root.modelData);
            root.screenState.launcher = false;
        }
    }

    // Decoding is started by the row rather than the preview panel so a thumbnail is
    // already on disk by the time an entry is focused. The script is a no-op when the
    // file exists, so a row rebuilt by scrolling costs nothing.
    Process {
        id: decoder

        running: root.wantsThumb
        command: root.wantsThumb ? ClipHistory.decodeCommand(root.modelData) : []

        stdout: StdioCollector {
            onStreamFinished: {
                if (text)
                    thumb.source = `file://${text}`;
            }
        }
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: Tokens.padding.medium
        anchors.rightMargin: Tokens.padding.medium
        anchors.margins: Tokens.padding.small

        StyledClippingRect {
            id: thumbWrapper

            anchors.verticalCenter: parent.verticalCenter

            implicitWidth: Tokens.sizes.launcher.clipboardThumbSize
            implicitHeight: Tokens.sizes.launcher.clipboardThumbSize

            color: root.isImage ? Colours.tPalette.m3surfaceContainerHigh : "transparent"
            radius: Tokens.rounding.small

            // A chequerboard behind transparent images, so a screenshot of a menu with
            // an alpha channel does not read as a broken or empty thumbnail.
            Loader {
                anchors.fill: parent
                active: root.isImage
                asynchronous: true

                sourceComponent: Chequerboard {
                    cellSize: Math.round(Tokens.sizes.launcher.clipboardThumbSize / 5)
                }
            }

            MaterialIcon {
                anchors.centerIn: parent
                visible: !root.isImage || thumb.status !== Image.Ready
                text: root.isImage ? "image" : "notes"
                color: Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.large
            }

            Image {
                id: thumb

                anchors.fill: parent
                visible: status === Image.Ready

                asynchronous: true
                cache: false
                fillMode: Image.PreserveAspectCrop
                // Decoded at thumbnail size rather than full: a 1918x1033 screenshot
                // otherwise costs 8 MB of pixmap per visible row.
                sourceSize.width: Tokens.sizes.launcher.clipboardThumbSize * 2
                sourceSize.height: Tokens.sizes.launcher.clipboardThumbSize * 2
            }
        }

        Item {
            anchors.left: thumbWrapper.right
            anchors.leftMargin: Tokens.spacing.medium
            anchors.right: parent.right
            anchors.verticalCenter: thumbWrapper.verticalCenter

            implicitHeight: title.implicitHeight + subtitle.implicitHeight

            StyledText {
                id: title

                anchors.left: parent.left
                anchors.right: parent.right

                text: {
                    if (root.isImage)
                        return qsTr("%1 image").arg(root.modelData?.type?.toUpperCase() ?? "");
                    // Whitespace collapsed: a copied code block is mostly indentation, and
                    // rendered raw the row would be blank with the text pushed off the end.
                    return (root.modelData?.preview ?? "").replace(/\s+/g, " ").trim();
                }
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }

            StyledText {
                id: subtitle

                anchors.top: title.bottom
                anchors.left: parent.left
                anchors.right: parent.right

                text: {
                    if (root.isImage)
                        return `${root.modelData?.width ?? 0} × ${root.modelData?.height ?? 0} · ${root.modelData?.sizeText ?? ""}`;

                    const chars = root.modelData?.preview?.length ?? 0;
                    const lines = (root.modelData?.preview?.match(/\n/g)?.length ?? 0) + 1;
                    return lines > 1 ? qsTr("%1 lines · %2 characters").arg(lines).arg(chars) : qsTr("%1 characters").arg(chars);
                }
                font: Tokens.font.body.small
                color: Colours.palette.m3outline
                elide: Text.ElideRight
            }
        }
    }
}
