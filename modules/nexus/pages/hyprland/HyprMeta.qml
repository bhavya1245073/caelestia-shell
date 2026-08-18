pragma Singleton

import QtQuick

// Display metadata for Hyprland's option categories.
//
// Hyprland's section names are terse and inconsistent ("misc", "dwindle",
// "input-capture", "input:touchpad"), so this maps them to something readable.
// Anything unlisted still gets a sensible auto-generated label and a generic icon -
// the point is that a new Hyprland section shows up in the UI without a code
// change, just without a bespoke icon.
QtObject {
    id: root

    readonly property var icons: ({
            "general": "tune",
            "decoration": "auto_awesome",
            "decoration:blur": "blur_on",
            "decoration:shadow": "flip_to_back",
            "animations": "animation",
            "input": "keyboard",
            "input:touchpad": "touch_app",
            "input:touchdevice": "touch_app",
            "input:tablet": "draw",
            "input:scroll": "swap_vert",
            "input-capture": "screen_share",
            "gestures": "swipe",
            "group": "workspaces",
            "group:groupbar": "tab",
            "misc": "more_horiz",
            "binds": "keyboard_command_key",
            "xwayland": "layers",
            "opengl": "memory",
            "render": "monitor",
            "cursor": "mouse",
            "ecosystem": "public",
            "experimental": "science",
            "debug": "bug_report",
            "dwindle": "grid_view",
            "master": "view_sidebar",
            "scrolling": "view_carousel",
            "layout": "dashboard",
            "quirks": "build"
        })

    readonly property var labels: ({
            "general": qsTr("General"),
            "decoration": qsTr("Decoration"),
            "decoration:blur": qsTr("Blur"),
            "decoration:shadow": qsTr("Shadow"),
            "animations": qsTr("Animations"),
            "input": qsTr("Input"),
            "input:touchpad": qsTr("Touchpad"),
            "input:touchdevice": qsTr("Touchscreen"),
            "input:tablet": qsTr("Drawing tablet"),
            "input:scroll": qsTr("Scrolling"),
            "input-capture": qsTr("Input capture"),
            "gestures": qsTr("Gestures"),
            "group": qsTr("Groups"),
            "group:groupbar": qsTr("Group bar"),
            "misc": qsTr("Miscellaneous"),
            "binds": qsTr("Keybind behaviour"),
            "xwayland": qsTr("XWayland"),
            "opengl": qsTr("OpenGL"),
            "render": qsTr("Rendering"),
            "cursor": qsTr("Cursor"),
            "ecosystem": qsTr("Ecosystem"),
            "experimental": qsTr("Experimental"),
            "debug": qsTr("Debug"),
            "dwindle": qsTr("Dwindle layout"),
            "master": qsTr("Master layout"),
            "scrolling": qsTr("Scrolling layout"),
            "layout": qsTr("Layout"),
            "quirks": qsTr("Quirks")
        })

    readonly property var descriptions: ({
            "debug": qsTr("Logging and diagnostics. Changing these can flood the log or hang the compositor."),
            "experimental": qsTr("Unfinished features. Expect breakage."),
            "quirks": qsTr("Per-application workarounds."),
            "render": qsTr("Frame scheduling and direct scanout.")
        })

    function forCategory(category: string): string {
        return icons[category] ?? icons[category.split(":")[0]] ?? "settings";
    }

    // "input:touchpad" -> "Touchpad", "input-capture" -> "Input capture".
    function labelFor(category: string): string {
        const known = labels[category];
        if (known)
            return known;

        const leaf = category.split(":").pop().replace(/[-_]/g, " ");
        return leaf.charAt(0).toUpperCase() + leaf.slice(1);
    }

    // Full path as a breadcrumb, so a sub-page titled "Touchpad" still says where it
    // lives.
    function pathFor(category: string): string {
        return category.split(":").map(p => root.labelFor(p)).join(" › ");
    }
}
