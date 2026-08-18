pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> providerItems: [
        ProviderItem {
            optionKey: "klipy"
            text: "Klipy"
        },
        ProviderItem {
            optionKey: "giphy"
            text: "Giphy"
        },
        ProviderItem {
            optionKey: "tenor"
            text: "Tenor"
        }
    ]

    // Tenor's four levels, mapped onto each provider's own vocabulary in Gifs, so one
    // setting covers all of them.
    readonly property list<MenuItem> filterItems: [
        FilterItem {
            optionKey: "high"
            text: qsTr("Strict")
        },
        FilterItem {
            optionKey: "medium"
            text: qsTr("Moderate")
        },
        FilterItem {
            optionKey: "low"
            text: qsTr("Permissive")
        },
        FilterItem {
            optionKey: "off"
            text: qsTr("Off")
        }
    ]

    title: qsTr("Launcher")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // General
        SectionHeader {
            first: true
            text: qsTr("General")
        }

        ToggleRow {
            first: true
            text: qsTr("Enabled")
            checked: Config.launcher.enabled
            onToggled: GlobalConfig.launcher.enabled = checked
        }

        ToggleRow {
            text: qsTr("Show on hover")
            subtext: qsTr("Reveal when the cursor reaches the screen edge")
            checked: Config.launcher.showOnHover
            onToggled: GlobalConfig.launcher.showOnHover = checked
        }

        TextFieldRow {
            id: prefixRow

            last: true
            label: qsTr("Action prefix")
            subtext: qsTr("Prefix used to run actions in the launcher")
            errorText: qsTr("Prefix must not be alphanumeric")
            value: GlobalConfig.launcher.actionPrefix === ">" ? "" : GlobalConfig.launcher.actionPrefix // TODO: replace with empty only when not loaded once loaded state is exposed
            placeholderText: ">"
            maximumLength: 1
            smallField: true
            validate: /^[^a-zA-Z0-9\s]$/
            onEditingFinished: value => {
                if (!field.valid)
                    return;
                /// TODO: replace with GlobalConfig.launcher.resetOption("actionPrefix") on empty commit when reset is fixed
                GlobalConfig.launcher.actionPrefix = value || ">";
                if (GlobalConfig.launcher.actionPrefix === ">")
                    clear();
            }
        }

        // Display
        SectionHeader {
            text: qsTr("Display")
        }

        StepperRow {
            first: true
            label: qsTr("Max items shown")
            value: Config.launcher.maxShown
            from: 1
            to: 20
            stepSize: 1
            onMoved: v => GlobalConfig.launcher.maxShown = v
        }

        StepperRow {
            label: qsTr("Max wallpapers")
            value: Config.launcher.maxWallpapers
            from: 1
            to: 30
            stepSize: 1
            onMoved: v => GlobalConfig.launcher.maxWallpapers = v
        }

        StepperRow {
            last: true
            label: qsTr("Drag threshold")
            subtext: qsTr("Pixels dragged before the launcher opens")
            value: Config.launcher.dragThreshold
            from: 0
            to: 200
            stepSize: 5
            onMoved: v => GlobalConfig.launcher.dragThreshold = v
        }

        // Behaviour
        SectionHeader {
            text: qsTr("Behaviour")
        }

        ToggleRow {
            first: true
            text: qsTr("Vim keybinds")
            subtext: qsTr("Navigate results with Ctrl+hjkl")
            checked: GlobalConfig.launcher.vimKeybinds
            onToggled: GlobalConfig.launcher.vimKeybinds = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Enable dangerous actions")
            subtext: qsTr("Allow actions that shut down or log out")
            checked: GlobalConfig.launcher.enableDangerousActions
            onToggled: GlobalConfig.launcher.enableDangerousActions = checked
        }

        // Fuzzy search
        SectionHeader {
            text: qsTr("Fuzzy search")
        }

        ToggleRow {
            first: true
            text: qsTr("Apps")
            checked: GlobalConfig.launcher.useFuzzy.apps
            onToggled: GlobalConfig.launcher.useFuzzy.apps = checked
        }

        ToggleRow {
            text: qsTr("Actions")
            checked: GlobalConfig.launcher.useFuzzy.actions
            onToggled: GlobalConfig.launcher.useFuzzy.actions = checked
        }

        ToggleRow {
            text: qsTr("Schemes")
            checked: GlobalConfig.launcher.useFuzzy.schemes
            onToggled: GlobalConfig.launcher.useFuzzy.schemes = checked
        }

        ToggleRow {
            text: qsTr("Variants")
            checked: GlobalConfig.launcher.useFuzzy.variants
            onToggled: GlobalConfig.launcher.useFuzzy.variants = checked
        }

        ToggleRow {
            last: true
            text: qsTr("Wallpapers")
            checked: GlobalConfig.launcher.useFuzzy.wallpapers
            onToggled: GlobalConfig.launcher.useFuzzy.wallpapers = checked
        }

        // GIFs
        SectionHeader {
            text: qsTr("GIF picker")
        }

        ToggleRow {
            first: true
            text: qsTr("Enabled")
            subtext: qsTr("Search GIFs with %1gif and copy one to the clipboard").arg(GlobalConfig.launcher.actionPrefix)
            checked: GlobalConfig.gifs.enabled
            onToggled: GlobalConfig.gifs.enabled = checked
        }

        SelectRow {
            label: qsTr("Provider")
            subtext: Gifs.provider.note
            menuItems: root.providerItems
            active: root.providerItems.find(i => (i as ProviderItem).optionKey === Gifs.providerName) ?? root.providerItems[0]
            onSelected: item => Gifs.setProvider((item as ProviderItem).optionKey)
        }

        TextFieldRow {
            label: qsTr("%1 API key").arg(Gifs.providerLabel)
            // No provider hands out a working shared key any more, so this is a required
            // step rather than a tweak - and saying so beats a silently empty result list.
            subtext: Gifs.needsKey ? qsTr("Required \u2014 GIF search will not work without one") : qsTr("Key saved for %1").arg(Gifs.providerLabel)
            value: `${GlobalConfig.gifs.apiKeys[Gifs.providerName] ?? ""}`
            placeholderText: qsTr("Paste your key")
            onEditingFinished: v => Gifs.setKey(v)
        }

        RowButton {
            icon: "open_in_new"
            text: qsTr("Get a %1 key").arg(Gifs.providerLabel)
            subtext: Gifs.provider.keyUrl
            onClicked: Gifs.openKeyPage()
        }

        SelectRow {
            label: qsTr("Content filter")
            subtext: qsTr("How aggressively the provider filters results")
            menuItems: root.filterItems
            active: root.filterItems.find(i => (i as FilterItem).optionKey === GlobalConfig.gifs.contentFilter) ?? root.filterItems[1]
            onSelected: item => GlobalConfig.gifs.contentFilter = (item as FilterItem).optionKey
        }

        StepperRow {
            label: qsTr("Results per search")
            value: GlobalConfig.gifs.limit
            from: 5
            to: 50
            stepSize: 5
            onMoved: v => GlobalConfig.gifs.limit = v
        }

        StepperRow {
            label: qsTr("Search delay")
            subtext: qsTr("Milliseconds of idle typing before searching")
            value: GlobalConfig.gifs.searchDebounce
            from: 0
            to: 2000
            stepSize: 50
            onMoved: v => GlobalConfig.gifs.searchDebounce = v
        }

        ToggleRow {
            text: qsTr("Copy the file")
            subtext: qsTr("Download and copy the GIF itself, so pasting uploads it. Off copies just the link.")
            checked: GlobalConfig.gifs.copyFile
            onToggled: GlobalConfig.gifs.copyFile = checked
        }

        ToggleRow {
            text: qsTr("Also copy the link")
            subtext: qsTr("Put the URL on the clipboard as text too, for apps that ignore images")
            checked: GlobalConfig.gifs.copyUrlAsText
            disabled: !GlobalConfig.gifs.copyFile
            onToggled: GlobalConfig.gifs.copyUrlAsText = checked
        }

        StepperRow {
            label: qsTr("Cache limit")
            subtext: qsTr("Megabytes of downloaded GIFs to keep")
            value: GlobalConfig.gifs.cacheSizeMb
            from: 10
            to: 2000
            stepSize: 10
            onMoved: v => GlobalConfig.gifs.cacheSizeMb = v
        }

        RowButton {
            last: true
            icon: "heart_minus"
            text: qsTr("Clear saved GIFs")
            subtext: Gifs.favourites.length === 1 ? qsTr("1 saved GIF") : qsTr("%1 saved GIFs").arg(Gifs.favourites.length)
            disabled: Gifs.favourites.length === 0
            onClicked: Gifs.clearFavourites()
        }
    }

    component ProviderItem: MenuItem {
        required property string optionKey

        icon: Gifs.providerName === optionKey ? "check" : ""
    }

    component FilterItem: MenuItem {
        required property string optionKey

        icon: GlobalConfig.gifs.contentFilter === optionKey ? "check" : ""
    }
}
