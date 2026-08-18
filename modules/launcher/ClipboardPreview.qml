pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.misc
import qs.services

// The focused clipboard entry, in full.
//
// The reason this mode is in the launcher rather than a dmenu: an image is shown as an
// image, and text is shown as all of it rather than the first line cliphist reports.
StyledClippingRect {
    id: root

    required property var entry

    readonly property bool isImage: entry?.isImage ?? false
    readonly property bool canPreview: ClipHistory.shouldPreview(entry)

    color: Colours.tPalette.m3surfaceContainer
    radius: Tokens.rounding.large

    // Text entries need their full contents, which cliphist only gives on decode - its
    // list output is truncated to preview-width. Re-run per focused entry, so exactly
    // one decode is in flight regardless of how fast the selection moves.
    Process {
        id: textLoader

        running: !!root.entry && !root.isImage
        command: root.entry && !root.isImage ? ["cliphist", "decode", `${root.entry.id}`] : []

        stdout: StdioCollector {
            onStreamFinished: fullText.text = text
        }
    }

    Process {
        id: imageLoader

        running: root.canPreview
        command: root.canPreview ? ClipHistory.decodeCommand(root.entry) : []

        stdout: StdioCollector {
            onStreamFinished: {
                if (text)
                    image.source = `file://${text}`;
            }
        }
    }

    // Image preview.
    Loader {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large

        active: root.isImage
        asynchronous: true

        sourceComponent: Item {
            Chequerboard {
                anchors.fill: parent
                opacity: image.status === Image.Ready ? 1 : 0
            }

            Image {
                id: image

                anchors.fill: parent

                asynchronous: true
                cache: false
                fillMode: Image.PreserveAspectFit
                visible: status === Image.Ready
                // Bounded to the panel: previewing a 4K screenshot at full resolution
                // costs 30 MB of pixmap to draw it 300 px wide.
                sourceSize.width: root.width * 2
                sourceSize.height: root.height * 2
            }

            Column {
                anchors.centerIn: parent
                spacing: Tokens.spacing.small
                visible: image.status !== Image.Ready

                MaterialIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.canPreview ? "image" : "visibility_off"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.extraLarge
                }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    horizontalAlignment: Text.AlignHCenter
                    // Says which of the two reasons applies, because one is fixed by waiting
                    // and the other by changing a setting.
                    text: {
                        if (!GlobalConfig.clipboard.imagePreviews)
                            return qsTr("Image previews are off");
                        if (!root.canPreview)
                            return qsTr("Larger than the %1 MB preview limit").arg(GlobalConfig.clipboard.maxPreviewSizeMb);
                        return image.status === Image.Error ? qsTr("Could not decode this image") : qsTr("Decoding…");
                    }
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    width: root.width - Tokens.padding.large * 4
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    // Text preview.
    VerticalFadeFlickable {
        id: textScroll

        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        anchors.bottomMargin: meta.height + Tokens.padding.large

        visible: !root.isImage
        contentHeight: fullText.implicitHeight
        contentWidth: width

        StyledText {
            id: fullText

            width: parent.width

            font: Tokens.font.mono.small
            color: Colours.palette.m3onSurface
            wrapMode: Text.Wrap
            // Long history entries are frequently a whole file. Scrolling the panel is
            // fine; laying out a megabyte of text on every arrow keypress is not.
            elide: Text.ElideRight
            maximumLineCount: 400
        }

        StyledScrollBar.vertical: StyledScrollBar {
            flickable: textScroll
        }
    }

    // Metadata strip. Which entry this is and how big, so the preview is legible even
    // when the content itself is not (an image, or whitespace).
    Item {
        id: meta

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        implicitHeight: metaText.implicitHeight + Tokens.padding.medium * 2

        StyledRect {
            anchors.fill: parent
            color: Colours.tPalette.m3surfaceContainerHigh
            opacity: 0.6
        }

        StyledText {
            id: metaText

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.large

            text: {
                if (!root.entry)
                    return "";
                if (root.isImage)
                    return `${root.entry.type.toUpperCase()} · ${root.entry.width} × ${root.entry.height} · ${root.entry.sizeText}`;

                const t = fullText.text;
                const lines = (t.match(/\n/g)?.length ?? 0) + 1;
                return qsTr("Text · %1 lines · %2 characters").arg(lines).arg(t.length);
            }
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            elide: Text.ElideRight
        }
    }
}
