pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

// One GIF tile in the launcher's picker row.
//
// Deliberately shaped like WallpaperItem so the two pickers feel like the same
// thing, but with two differences that matter: only the focused tile animates (nine
// simultaneously decoding GIFs is enough to drop frames on the launcher's open
// animation), and each tile carries a favourite toggle.
Item {
    id: root

    required property var modelData
    required property ScreenState screenState

    readonly property bool isFavourite: Gifs.isFavourite(modelData)

    scale: 0.5
    opacity: 0
    z: PathView.z ?? 0 // qmllint disable missing-property

    Component.onCompleted: {
        scale = Qt.binding(() => PathView.isCurrentItem ? 1 : PathView.onPath ? 0.8 : 0);
        opacity = Qt.binding(() => PathView.onPath ? 1 : 0);
    }

    implicitWidth: image.width + Tokens.padding.medium * 2
    implicitHeight: image.height + label.height + Tokens.spacing.extraSmall + Tokens.padding.large + Tokens.padding.medium

    StateLayer {
        radius: Tokens.rounding.large
        onClicked: {
            Gifs.copy(root.modelData);
            root.screenState.launcher = false;
        }
    }

    Elevation {
        anchors.fill: image
        radius: image.radius
        opacity: root.PathView.isCurrentItem ? 1 : 0
        level: 4

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    StyledClippingRect {
        id: image

        anchors.horizontalCenter: parent.horizontalCenter
        y: Tokens.padding.large
        color: Colours.tPalette.m3surfaceContainer
        radius: Tokens.rounding.large

        implicitWidth: Tokens.sizes.launcher.gifWidth
        implicitHeight: Tokens.sizes.launcher.gifHeight

        MaterialIcon {
            anchors.centerIn: parent
            visible: preview.status !== AnimatedImage.Ready
            text: preview.status === AnimatedImage.Error ? "broken_image" : "gif"
            color: Colours.tPalette.m3outline
            fontStyle: Tokens.font.icon.builders.extraLarge.scale(2).weight(Font.DemiBold).build()
        }

        AnimatedImage {
            id: preview

            anchors.fill: parent
            // The preview is a thumbnail from the provider, so fit rather than crop -
            // GIFs are the content, and cropping a reaction GIF loses the joke.
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: true
            smooth: !root.PathView.view.moving
            source: root.modelData.previewUrl ?? root.modelData.url ?? ""

            // Only the focused tile animates. Off-focus tiles still show their first
            // frame, so the row reads as GIFs rather than placeholders.
            paused: !root.PathView.isCurrentItem

            opacity: status === AnimatedImage.Ready ? 1 : 0

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }

        // Favourite toggle. Overlaid on the tile rather than put in a row below,
        // because the label already competes for that space.
        StyledRect {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Tokens.padding.small

            implicitWidth: starIcon.implicitHeight + Tokens.padding.small * 2
            implicitHeight: implicitWidth
            radius: Tokens.rounding.full
            color: Qt.alpha(Colours.palette.m3surfaceContainer, root.isFavourite ? 0.9 : 0.6)
            opacity: root.PathView.isCurrentItem || root.isFavourite ? 1 : 0

            StateLayer {
                radius: parent.radius
                onClicked: Gifs.toggleFavourite(root.modelData)
            }

            MaterialIcon {
                id: starIcon

                anchors.centerIn: parent
                text: root.isFavourite ? "favorite" : "favorite_border"
                color: root.isFavourite ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                fontStyle: Tokens.font.icon.small
                fill: root.isFavourite ? 1 : 0
                animate: true
            }

            Behavior on opacity {
                Anim {
                    type: Anim.DefaultEffects
                }
            }
        }
    }

    StyledText {
        id: label

        anchors.top: image.bottom
        anchors.topMargin: Tokens.spacing.extraSmall
        anchors.horizontalCenter: parent.horizontalCenter

        width: image.width - Tokens.padding.medium * 2
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        renderType: Text.QtRendering
        text: root.modelData.title ?? qsTr("GIF")
        font: Tokens.font.label.medium
    }

    Behavior on scale {
        Anim {}
    }

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }
}
