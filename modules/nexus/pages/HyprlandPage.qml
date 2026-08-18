pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common
import qs.modules.nexus.pages.hyprland

// Window manager settings, backed by Hyprland's own option table.
//
// The layout is two-tier on purpose. Nobody wants to hunt through 370 options to
// change their gaps, but a settings page that only exposes a curated dozen is the
// thing people end up editing config files around. So: a curated "look and feel"
// section with the options that actually get changed, then every category Hyprland
// reports, complete, generated from `hyprctl descriptions`.
PageBase {
    id: root

    // Curated groups. Only the *names* are listed - labels, controls, ranges and
    // descriptions all come from Hyprland, so these stay correct across releases and
    // silently skip anything a given Hyprland version does not have.
    readonly property list<var> groups: [
        {
            title: qsTr("Gaps and borders"),
            icon: "border_outer",
            options: ["general:gaps_in", "general:gaps_out", "general:border_size", "general:gaps_workspaces", "decoration:rounding", "decoration:rounding_power"]
        },
        {
            title: qsTr("Border colours"),
            icon: "palette",
            options: ["general:col.active_border", "general:col.inactive_border", "group:col.border_active", "group:col.border_inactive"]
        },
        {
            title: qsTr("Blur"),
            icon: "blur_on",
            options: ["decoration:blur:enabled", "decoration:blur:size", "decoration:blur:passes", "decoration:blur:noise", "decoration:blur:contrast", "decoration:blur:brightness", "decoration:blur:vibrancy", "decoration:blur:vibrancy_darkness", "decoration:blur:special", "decoration:blur:popups", "decoration:blur:input_methods"]
        },
        {
            title: qsTr("Shadows"),
            icon: "flip_to_back",
            options: ["decoration:shadow:enabled", "decoration:shadow:range", "decoration:shadow:render_power", "decoration:shadow:sharp", "decoration:shadow:offset", "decoration:shadow:scale", "decoration:shadow:color", "decoration:shadow:color_inactive"]
        },
        {
            title: qsTr("Opacity and dimming"),
            icon: "opacity",
            options: ["decoration:active_opacity", "decoration:inactive_opacity", "decoration:fullscreen_opacity", "decoration:dim_inactive", "decoration:dim_strength", "decoration:dim_special", "decoration:dim_around"]
        },
        {
            title: qsTr("Animations"),
            icon: "animation",
            options: ["animations:enabled", "animations:workspace_wraparound"]
        },
        {
            title: qsTr("Focus and mouse"),
            icon: "mouse",
            options: ["input:follow_mouse", "input:mouse_refocus", "input:focus_on_close", "general:resize_on_border", "general:extend_border_grab_area", "general:hover_icon_on_border", "general:no_focus_fallback", "general:snap:enabled"]
        },
        {
            title: qsTr("Keyboard"),
            icon: "keyboard",
            options: ["input:kb_layout", "input:kb_variant", "input:kb_options", "input:repeat_rate", "input:repeat_delay", "input:numlock_by_default", "input:resolve_binds_by_sym"]
        },
        {
            title: qsTr("Touchpad"),
            icon: "touch_app",
            options: ["input:touchpad:natural_scroll", "input:touchpad:scroll_factor", "input:touchpad:disable_while_typing", "input:touchpad:tap-to-click", "input:touchpad:drag_lock", "input:touchpad:middle_button_emulation", "input:touchpad:clickfinger_behavior"]
        },
        {
            title: qsTr("Gestures"),
            icon: "swipe",
            options: ["gestures:workspace_swipe_distance", "gestures:workspace_swipe_invert", "gestures:workspace_swipe_create_new", "gestures:workspace_swipe_forever"]
        },
        {
            title: qsTr("Tiling"),
            icon: "grid_view",
            options: ["general:layout", "dwindle:preserve_split", "dwindle:force_split", "dwindle:smart_split", "dwindle:smart_resizing", "dwindle:split_width_multiplier", "dwindle:default_split_ratio", "master:new_status", "master:new_on_top", "master:mfact", "master:orientation"]
        },
        {
            title: qsTr("Behaviour"),
            icon: "tune",
            options: ["misc:vrr", "misc:focus_on_activate", "misc:animate_manual_resizes", "misc:animate_mouse_windowdragging", "misc:mouse_move_enables_dpms", "misc:key_press_enables_dpms", "misc:middle_click_paste", "misc:allow_session_lock_restore", "misc:close_special_on_empty", "misc:enable_swallow", "misc:disable_hyprland_logo", "misc:force_default_wallpaper"]
        }
    ]

    // Categories not covered above, so "everything is reachable" holds even when a
    // Hyprland release adds a whole new section.
    readonly property var otherCategories: {
        const covered = {};
        for (const g of root.groups)
            for (const o of g.options)
                covered[HyprSettings.byName[o]?.category ?? ""] = true;

        return HyprSettings.categories.filter(c => !covered[c.name] && (!c.advanced || GlobalConfig.hyprland.showAdvanced));
    }

    // Categories a curated group touches, but only partially - "Blur" shows 11 of
    // decoration:blur's options, "Tiling" shows 6 of dwindle's. Listing them again
    // under "All settings" is how you get to the rest.
    readonly property var partialCategories: {
        const shown = {};
        for (const g of root.groups)
            for (const o of g.options)
                shown[o] = true;

        return HyprSettings.categories.filter(c => {
            if (c.advanced && !GlobalConfig.hyprland.showAdvanced)
                return false;
            for (const d of HyprSettings.descriptions)
                if (d.category === c.name && !shown[d.name])
                    return true;
            return false;
        });
    }

    title: qsTr("Window manager")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Nothing below works until `hyprctl descriptions` has come back.
        Loader {
            Layout.fillWidth: true
            active: !HyprSettings.ready
            visible: active

            sourceComponent: ConnectedRect {
                first: true
                last: true
                implicitHeight: col.implicitHeight + Tokens.padding.extraLarge * 2

                ColumnLayout {
                    id: col

                    anchors.centerIn: parent
                    spacing: Tokens.spacing.extraSmall

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        text: "sync_problem"
                        color: Colours.palette.m3outline
                        fontStyle: Tokens.font.icon.large
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: qsTr("Waiting for Hyprland")
                        color: Colours.palette.m3outline
                        font: Tokens.font.body.large
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: qsTr("Could not read the compositor's option list. Is this session running Hyprland?")
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                        wrapMode: Text.WordWrap
                        Layout.maximumWidth: root.cappedWidth * 0.7
                    }
                }
            }
        }

        // Changed options, surfaced first: it is the only part of this page that is
        // not just a mirror of Hyprland's defaults, and the only thing that survives
        // into shell.json.
        Loader {
            Layout.fillWidth: true
            active: HyprSettings.ready && HyprSettings.overrideCount > 0
            visible: active

            sourceComponent: ColumnLayout {
                spacing: Tokens.spacing.extraSmall / 2

                SectionHeader {
                    first: true
                    text: qsTr("Your changes")
                }

                NavRow {
                    first: true
                    icon: "edit_note"
                    text: qsTr("Changed settings")
                    subtext: qsTr("%1 overriding the Hyprland config file").arg(HyprSettings.overrideCount === 1 ? qsTr("1 setting") : qsTr("%1 settings").arg(HyprSettings.overrideCount))
                    onClicked: {
                        root.nState.selectedHyprCategory = "";
                        root.nState.openSubPage(1);
                    }
                }

                RowButton {
                    last: true
                    icon: "restart_alt"
                    text: qsTr("Reset everything")
                    subtext: qsTr("Discard all changes and reload the Hyprland config")
                    onClicked: HyprSettings.unsetAll()
                }
            }
        }

        // Curated groups.
        Repeater {
            model: HyprSettings.ready ? root.groups : []

            ColumnLayout {
                id: group

                required property var modelData
                required property int index

                // Options this Hyprland build actually has. Filtering here rather than
                // per row keeps first/last rounding correct when something is missing.
                readonly property var present: modelData.options.filter(o => HyprSettings.byName.hasOwnProperty(o))

                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall / 2
                visible: present.length > 0

                SectionHeader {
                    first: group.index === 0 && HyprSettings.overrideCount === 0
                    text: group.modelData.title
                }

                Repeater {
                    model: group.present

                    HyprOptionRow {
                        required property string modelData
                        required property int index

                        name: modelData
                        first: index === 0
                        last: index === group.present.length - 1
                    }
                }
            }
        }

        // Everything else, by category.
        SectionHeader {
            text: qsTr("All settings")
            visible: HyprSettings.ready
        }

        Repeater {
            model: HyprSettings.ready ? root.otherCategories.concat(root.partialCategories) : []

            NavRow {
                required property var modelData
                required property int index

                readonly property int total: root.otherCategories.length + root.partialCategories.length

                icon: HyprMeta.forCategory(modelData.name)
                text: HyprMeta.labelFor(modelData.name)
                subtext: modelData.overridden > 0 ? qsTr("%1 settings · %2 changed").arg(modelData.count).arg(modelData.overridden) : qsTr("%1 settings").arg(modelData.count)
                first: index === 0
                last: index === total - 1
                onClicked: {
                    root.nState.selectedHyprCategory = modelData.name;
                    root.nState.openSubPage(1);
                }
            }
        }

        // How the override machinery behaves. Last because it is the part you set
        // once and forget.
        SectionHeader {
            text: qsTr("Advanced")
            visible: HyprSettings.ready
        }

        ToggleRow {
            first: true
            visible: HyprSettings.ready
            text: qsTr("Apply shell overrides")
            subtext: qsTr("Push the settings on this page to Hyprland. Off means the config file wins.")
            checked: GlobalConfig.hyprland.enabled
            onToggled: {
                GlobalConfig.hyprland.enabled = checked;
                if (checked)
                    HyprSettings.applyAll();
                else
                    Hypr.extras.reloadConfig();
            }
        }

        ToggleRow {
            visible: HyprSettings.ready
            text: qsTr("Reapply after config reload")
            subtext: qsTr("Hyprland discards runtime changes when its config reloads. Keep this on to put them back.")
            checked: GlobalConfig.hyprland.applyOnReload
            onToggled: GlobalConfig.hyprland.applyOnReload = checked
        }

        ToggleRow {
            last: true
            visible: HyprSettings.ready
            text: qsTr("Show advanced sections")
            subtext: qsTr("Reveal debug, render and experimental options. These can break or hang the compositor.")
            checked: GlobalConfig.hyprland.showAdvanced
            onToggled: GlobalConfig.hyprland.showAdvanced = checked
        }
    }
}
