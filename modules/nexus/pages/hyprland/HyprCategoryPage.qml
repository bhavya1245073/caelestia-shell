pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// Every option in one Hyprland category, or - when `nState.selectedHyprCategory` is
// empty - every option currently overridden, across all categories.
//
// Wholly generated from `hyprctl descriptions`. Nothing here knows what any
// individual option means, which is the only way a settings page keeps up with a
// compositor that adds options every release.
PageBase {
    id: root

    readonly property string category: nState.selectedHyprCategory
    readonly property bool overridesOnly: !category

    property string filter

    readonly property var options: {
        const out = [];
        const f = root.filter.trim().toLowerCase();

        for (const d of HyprSettings.descriptions) {
            if (root.overridesOnly) {
                if (!HyprSettings.isOverridden(d.name))
                    continue;
            } else if (d.category !== root.category) {
                continue;
            }

            // Match the option's key, its full name and its description, so both
            // "gaps" and "monitor edges" find general:gaps_out.
            if (f && !d.name.toLowerCase().includes(f) && !d.description.toLowerCase().includes(f))
                continue;

            out.push(d.name);
        }
        return out;
    }

    readonly property int overriddenHere: options.filter(o => HyprSettings.isOverridden(o)).length

    // Unfiltered count, for the search placeholder.
    readonly property int optionsTotal: {
        let n = 0;
        for (const d of HyprSettings.descriptions)
            if (root.overridesOnly ? HyprSettings.isOverridden(d.name) : d.category === root.category)
                n++;
        return n;
    }

    isSubPage: true
    title: overridesOnly ? qsTr("Changed settings") : HyprMeta.pathFor(category)

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Category blurb, only for the sections that warrant a warning.
        Loader {
            Layout.fillWidth: true
            Layout.bottomMargin: active ? Tokens.spacing.small : 0
            active: !root.overridesOnly && !!HyprMeta.descriptions[root.category]
            visible: active

            sourceComponent: RowLayout {
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    Layout.leftMargin: Tokens.padding.small
                    Layout.alignment: Qt.AlignTop
                    text: "info"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: HyprMeta.descriptions[root.category] ?? ""
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                    wrapMode: Text.WordWrap
                }
            }
        }

        // Only worth a search box once the list is long enough to scroll past.
        Loader {
            Layout.fillWidth: true
            Layout.bottomMargin: active ? Tokens.spacing.small : 0
            active: root.optionsTotal > 12
            visible: active

            sourceComponent: StyledTextField {
                placeholderText: qsTr("Search %1 settings").arg(root.optionsTotal)
                text: root.filter
                onTextEdited: root.filter = text

                MaterialIcon {
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.padding.large
                    anchors.verticalCenter: parent.verticalCenter
                    text: "search"
                    color: Colours.palette.m3onSurfaceVariant
                    fontStyle: Tokens.font.icon.small
                }
            }
        }

        Repeater {
            model: root.options

            HyprOptionRow {
                required property string modelData
                required property int index

                name: modelData
                first: index === 0
                last: index === root.options.length - 1
                // In a flat category the section name is already the page title, so the
                // short key reads better. In the overrides view options come from
                // everywhere, so the full name is the only unambiguous label.
                showRawName: root.overridesOnly
            }
        }

        // Empty state, for a search with no hits or an overrides page you just cleared.
        Loader {
            Layout.fillWidth: true
            active: root.options.length === 0
            visible: active

            sourceComponent: ConnectedRect {
                first: true
                last: true
                implicitHeight: emptyCol.implicitHeight + Tokens.padding.extraLarge * 2

                ColumnLayout {
                    id: emptyCol

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.filter ? "search_off" : "check_circle"
                        color: Colours.palette.m3outline
                        fontStyle: Tokens.font.icon.large
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.filter ? qsTr("No matching settings") : qsTr("Nothing changed")
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.large
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.filter ? qsTr("Try a different search") : qsTr("Every setting here matches the Hyprland config")
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        // Bulk reset for this category, only once there is something to reset.
        Loader {
            Layout.fillWidth: true
            Layout.topMargin: active ? Tokens.spacing.largeIncreased : 0
            active: root.overriddenHere > 0
            visible: active

            sourceComponent: RowButton {
                first: true
                last: true
                icon: "restart_alt"
                text: root.overridesOnly ? qsTr("Reset all") : qsTr("Reset this section")
                subtext: root.overriddenHere === 1 ? qsTr("Restore 1 setting from the config file") : qsTr("Restore %1 settings from the config file").arg(root.overriddenHere)
                onClicked: {
                    if (root.overridesOnly)
                        HyprSettings.unsetAll();
                    else
                        HyprSettings.unsetCategory(root.category);
                }
            }
        }
    }
}
