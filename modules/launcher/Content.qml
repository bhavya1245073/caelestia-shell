pragma ComponentBehavior: Bound

import QtQuick
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.launcher.services

Item {
    id: root

    required property ScreenState screenState
    required property var panels
    required property real maxHeight

    readonly property int padding: Tokens.padding.large
    readonly property int rounding: Tokens.rounding.extraLarge

    implicitWidth: listWrapper.width + padding * 2
    implicitHeight: search.height + listWrapper.height + padding + search.anchors.bottomMargin

    Item {
        id: listWrapper

        implicitWidth: list.width
        implicitHeight: list.height + root.padding

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: search.top
        anchors.bottomMargin: root.padding

        ContentList {
            id: list

            content: root
            screenState: root.screenState
            panels: root.panels
            maxHeight: root.maxHeight - search.implicitHeight - root.padding * 3
            search: search
            padding: root.padding
            rounding: root.rounding
        }
    }

    SearchBar {
        id: search

        objectName: "launcherSearch"

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.padding
        anchors.bottomMargin: CUtils.clamp(root.padding - Config.border.thickness, 0, root.padding)

        topPadding: Math.round((Tokens.padding.medium + Tokens.padding.large) / 2)
        bottomPadding: Math.round((Tokens.padding.medium + Tokens.padding.large) / 2)

        placeholderText: qsTr("Type \"%1\" for commands").arg(GlobalConfig.launcher.actionPrefix)

        onAccepted: {
            // Nothing to pick when no key is configured, so make enter do the only useful
            // thing available: open the provider's key page.
            if (list.showGifs && Gifs.needsKey) {
                Gifs.openKeyPage();
                root.screenState.launcher = false;
                return;
            }

            const currentItem = list.currentList?.currentItem;
            if (currentItem) {
                if (list.showClipboard) {
                    ClipHistory.copy(currentItem.modelData);
                    root.screenState.launcher = false;
                } else if (list.showGifs) {
                    Gifs.copy(currentItem.modelData);
                    root.screenState.launcher = false;
                } else if (list.showWallpapers) {
                    if (Colours.scheme === "dynamic" && currentItem.modelData.path !== Wallpapers.actualCurrent)
                        Wallpapers.previewColourLock = true;
                    Wallpapers.setWallpaper(currentItem.modelData.path);
                    root.screenState.launcher = false;
                } else if (text.startsWith(GlobalConfig.launcher.actionPrefix)) {
                    if (text.startsWith(`${GlobalConfig.launcher.actionPrefix}calc `))
                        currentItem.onClicked();
                    else
                        currentItem.modelData.onClicked(list.currentList);
                } else {
                    Apps.launch(currentItem.modelData);
                    root.screenState.launcher = false;
                }
            }
        }

        Keys.onUpPressed: list.currentList?.decrementCurrentIndex()
        Keys.onDownPressed: list.currentList?.incrementCurrentIndex()

        // The picker rows are horizontal, so left/right is what people actually reach
        // for. Only bound in those modes - elsewhere they belong to the text cursor.
        Keys.onLeftPressed: event => {
            if (list.showGifs || list.showWallpapers)
                list.currentList?.decrementCurrentIndex();
            else
                event.accepted = false;
        }

        Keys.onRightPressed: event => {
            if (list.showGifs || list.showWallpapers)
                list.currentList?.incrementCurrentIndex();
            else
                event.accepted = false;
        }

        Keys.onEscapePressed: root.screenState.launcher = false

        Keys.onPressed: event => {
            // Clipboard entries are deletable in place, which the old fuzzel picker needed
            // a whole second keybind and a separate `-d` mode for. Shift+Delete rather
            // than Delete alone, since Delete belongs to the search field's text cursor.
            if (list.showClipboard) {
                const item = list.currentList?.currentItem;

                if (item && (event.modifiers & Qt.ShiftModifier) && (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace)) {
                    ClipHistory.remove(item.modelData);
                    event.accepted = true;
                    return;
                }

                // Wipe is Ctrl+Shift+Delete: destructive and not undoable, so it takes a
                // deliberate three-key press rather than sitting next to single deletion.
                if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_Delete) {
                    ClipHistory.wipe();
                    event.accepted = true;
                    return;
                }
            }

            // Save/unsave the focused GIF without leaving the keyboard. Ctrl+D because
            // Ctrl+F is a find shortcut everywhere else and Ctrl+S implies writing a file.
            if (list.showGifs && (event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_D) {
                const item = list.currentList?.currentItem;
                if (item)
                    Gifs.toggleFavourite(item.modelData);
                event.accepted = true;
                return;
            }

            if (!GlobalConfig.launcher.vimKeybinds)
                return;

            if (event.modifiers & Qt.ControlModifier) {
                if (event.key === Qt.Key_J || event.key === Qt.Key_N) {
                    list.currentList?.incrementCurrentIndex();
                    event.accepted = true;
                } else if (event.key === Qt.Key_K || event.key === Qt.Key_P) {
                    list.currentList?.decrementCurrentIndex();
                    event.accepted = true;
                }
            } else if (event.key === Qt.Key_Tab) {
                list.currentList?.incrementCurrentIndex();
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                list.currentList?.decrementCurrentIndex();
                event.accepted = true;
            }
        }

        Component.onCompleted: forceActiveFocus()

        Connections {
            function onLauncherChanged(): void {
                if (!root.screenState.launcher) {
                    search.text = "";
                    return;
                }

                // A keybind can ask for a mode to open into. Cleared on use so the next
                // plain open is a normal empty launcher, and only applied on the screen
                // that actually opened.
                if (ShellState.launcherQuery) {
                    search.text = ShellState.launcherQuery;
                    ShellState.launcherQuery = "";
                    search.cursorPosition = search.text.length;
                }
            }

            function onSessionChanged(): void {
                if (!root.screenState.session)
                    search.forceActiveFocus();
            }

            target: root.screenState
        }
    }
}
