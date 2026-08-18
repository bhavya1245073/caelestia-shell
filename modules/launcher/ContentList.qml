pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property var content
    required property ScreenState screenState
    required property var panels
    required property real maxHeight
    required property SearchBar search
    required property int padding
    required property int rounding

    readonly property bool showWallpapers: search.text.startsWith(`${GlobalConfig.launcher.actionPrefix}wallpaper `)
    // `>gif` with no trailing space still counts: the empty query shows favourites,
    // so there is something worth showing before you type anything.
    readonly property bool showGifs: GlobalConfig.gifs.enabled && new RegExp(`^\\${GlobalConfig.launcher.actionPrefix}gif( |$)`).test(search.text)
    readonly property var currentList: showGifs ? gifList.item : showWallpapers ? wallpaperList.item : appList.item // Can be either ListView or PathView, so can't type properly
    property string animState: showGifs ? "gifs" : showWallpapers ? "wallpapers" : "apps"

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom

    clip: true
    state: animState

    states: [
        State {
            name: "apps"

            PropertyChanges {
                root.implicitWidth: root.Tokens.sizes.launcher.itemWidth
                root.implicitHeight: Math.min(root.maxHeight, appList.implicitHeight > 0 ? appList.implicitHeight : empty.implicitHeight)
                appList.active: true
            }

            AnchorChanges {
                anchors.left: root.parent.left
                anchors.right: root.parent.right
            }
        },
        State {
            name: "wallpapers"

            PropertyChanges {
                root.implicitWidth: Math.max(root.Tokens.sizes.launcher.itemWidth * 1.2, wallpaperList.implicitWidth)
                root.implicitHeight: root.Tokens.sizes.launcher.wallpaperHeight
                wallpaperList.active: true
            }
        },
        State {
            name: "gifs"

            PropertyChanges {
                root.implicitWidth: Math.max(root.Tokens.sizes.launcher.itemWidth * 1.2, gifList.implicitWidth)
                // Room for the tile plus its title line, matching how the wallpaper row
                // sizes itself.
                root.implicitHeight: root.Tokens.sizes.launcher.gifHeight + root.Tokens.padding.large * 2
                gifList.active: true
            }
        }
    ]

    Behavior on animState {
        SequentialAnimation {
            Anim {
                target: root
                property: "opacity"
                from: 1
                to: 0
                type: Anim.DefaultEffects
            }
            PropertyAction {}
            Anim {
                target: root
                property: "opacity"
                from: 0
                to: 1
                type: Anim.DefaultEffects
            }
        }
    }

    Loader {
        id: appList

        active: false

        anchors.fill: parent

        sourceComponent: AppList {
            objectName: "launcherAppList"

            search: root.search
            screenState: root.screenState
        }
    }

    Loader {
        id: wallpaperList

        asynchronous: true
        active: false

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        sourceComponent: WallpaperList {
            objectName: "launcherWallpaperList"

            search: root.search
            screenState: root.screenState
            panels: root.panels
            content: root.content
        }
    }

    Loader {
        id: gifList

        asynchronous: true
        active: false

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter

        sourceComponent: GifList {
            objectName: "launcherGifList"

            search: root.search
            screenState: root.screenState
            panels: root.panels
            content: root.content
        }
    }

    Row {
        id: empty

        // GIF searches are asynchronous, so "no results" must not show while one is in
        // flight - otherwise every search flashes an error on its way to succeeding.
        readonly property bool isEmpty: root.state === "gifs" ? (!Gifs.loading && root.currentList?.count === 0) : root.currentList?.count === 0

        opacity: isEmpty ? 1 : 0
        scale: isEmpty ? 1 : 0.5

        spacing: Tokens.spacing.medium
        padding: Tokens.padding.large

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        MaterialIcon {
            text: {
                if (root.state === "gifs")
                    return Gifs.needsKey ? "key" : Gifs.error ? "error" : "gif_box";
                return root.state === "wallpapers" ? "wallpaper_slideshow" : "manage_search";
            }
            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.extraLarge

            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                text: {
                    if (root.state === "gifs") {
                        if (Gifs.needsKey)
                            return qsTr("GIF search needs an API key");
                        return Gifs.showingFavourites ? qsTr("No saved GIFs") : qsTr("No GIFs found");
                    }
                    return root.state === "wallpapers" ? qsTr("No wallpapers found") : qsTr("No results");
                }
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
            }

            StyledText {
                text: {
                    if (root.state === "gifs") {
                        // The one case where the fix is a single action, so say what it is and
                        // what pressing enter will do.
                        if (Gifs.needsKey)
                            return qsTr("Press enter to get a free %1 key, then paste it in settings").arg(Gifs.providerLabel);
                        // The service's error text is the useful thing when there is one - it
                        // distinguishes a rejected key from a rate limit from no matches.
                        if (Gifs.error && !Gifs.showingFavourites)
                            return Gifs.error;
                        return Gifs.showingFavourites ? qsTr("Type to search, then press the heart to save one") : qsTr("Try searching for something else");
                    }
                    if (root.state === "wallpapers" && Wallpapers.list.length === 0)
                        return qsTr("Try putting some wallpapers in %1").arg(Paths.shortenHome(Paths.wallsdir));
                    return qsTr("Try searching for something else");
                }
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Behavior on scale {
            Anim {}
        }
    }

    // Search in flight. Without this the row is just blank between keystroke and
    // results, which reads as broken rather than busy.
    Loader {
        anchors.centerIn: parent

        active: opacity > 0
        opacity: root.state === "gifs" && Gifs.loading && root.currentList?.count === 0 ? 1 : 0
        asynchronous: true

        sourceComponent: Row {
            spacing: Tokens.spacing.medium

            LoadingIndicator {
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: Math.round(Tokens.font.icon.extraLarge.pointSize * 1.3)
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Searching GIFs")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Behavior on implicitWidth {
        enabled: root.screenState.launcher

        Anim {}
    }

    Behavior on implicitHeight {
        enabled: root.screenState.launcher

        Anim {}
    }
}
