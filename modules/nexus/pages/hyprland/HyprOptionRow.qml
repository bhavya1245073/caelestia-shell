pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// One Hyprland option, rendered as whatever control its type calls for.
//
// `hyprctl descriptions` gives a type, an optional min/max and an optional enum
// map, which is exactly enough to pick a control without a hand-written table per
// option. That matters: there are ~370 options and the set changes every Hyprland
// release, so anything hardcoded would rot immediately.
//
//   bool                        -> switch
//   number + enum map           -> dropdown
//   number + wide min/max       -> slider
//   number otherwise            -> spin box
//   string, colour-ish          -> colour row (swatch + text)
//   string / array              -> text field
Item {
    id: root

    required property string name
    property bool first
    property bool last
    // Hide the description line, for dense curated lists where the label says it all.
    property bool terse
    // Show the option's real name instead of a prettified label. Used in search
    // results, where knowing the exact key is the point.
    property bool showRawName

    readonly property var desc: HyprSettings.byName[name] ?? null
    readonly property bool overridden: HyprSettings.isOverridden(name)
    readonly property var value: HyprSettings.valueOf(name)

    // Animated separately from the anchor so the row can slide open for the reset
    // button; a Behavior cannot be attached to a grouped anchors property.
    property real resetInset: overridden ? resetLoader.width + Tokens.spacing.small : 0

    readonly property string type: desc?.type ?? "unknown"
    readonly property var enumMap: desc?.map ?? ({})
    readonly property bool hasEnum: Object.keys(enumMap).length > 0
    readonly property bool hasRange: desc?.min !== undefined && desc?.min !== null && desc?.max !== undefined && desc?.max !== null
    // Hyprland reports integer bounds for integer options, so a fractional default
    // or bound is the only signal that fractions are accepted at all.
    readonly property bool isFloat: type === "number" && (!Number.isInteger(desc?.default ?? 0) || (hasRange && (!Number.isInteger(desc.min) || !Number.isInteger(desc.max))))
    // A slider only reads well over a range with room to aim at. Below that a spin
    // box is both more precise and less fiddly.
    readonly property bool useSlider: type === "number" && hasRange && !hasEnum && (isFloat || desc.max - desc.min >= 4)

    // "no_gaps_when_only" -> "No gaps when only". Hyprland's own names are
    // snake_case and its descriptions are full sentences, so neither works as a
    // label unmodified.
    readonly property string prettyLabel: {
        const s = (desc?.key ?? name).replace(/^col\./, "").replace(/[_.]/g, " ");
        return s.charAt(0).toUpperCase() + s.slice(1);
    }
    readonly property string label: showRawName ? name : prettyLabel
    readonly property string subtext: terse ? "" : (desc?.description ?? "")

    // Enum maps are name -> number; sort by number so the dropdown reads in the
    // order the wiki documents rather than alphabetically.
    readonly property var enumNames: {
        const names = Object.keys(enumMap);
        names.sort((a, b) => enumMap[a] - enumMap[b]);
        return names;
    }
    readonly property string enumLabel: {
        for (const n of root.enumNames)
            if (enumMap[n] === root.value)
                return n.replace(/_/g, " ");
        return `${root.value}`;
    }

    function set(v: var): void {
        HyprSettings.set(root.name, v);
    }

    Layout.fillWidth: true
    visible: !!desc
    implicitHeight: visible ? (loader.item?.implicitHeight ?? 0) : 0

    Behavior on resetInset {
        Anim {}
    }

    Loader {
        id: loader

        anchors.left: parent.left
        anchors.right: parent.right
        // Leave room for the reset button, which sits outside the row's right edge.
        anchors.rightMargin: root.resetInset

        sourceComponent: {
            if (!root.desc)
                return null;
            if (root.type === "bool")
                return toggleComp;
            if (root.hasEnum)
                return selectComp;
            if (root.useSlider)
                return sliderComp;
            if (root.type === "number")
                return stepperComp;
            // Gradients and plain colours both get the swatch row. HyprExtras reports
            // the type, so this catches decoration:glow:color as readily as
            // general:col.active_border, without a name-matching heuristic.
            if (root.type === "gradient" || root.type === "color")
                return colourComp;
            return textComp;
        }
    }

    // Reset-to-default, only when this option is actually overridden - resetting one
    // we never set is a no-op that costs a full compositor reload.
    Loader {
        id: resetLoader

        anchors.right: parent.right
        anchors.verticalCenter: loader.verticalCenter

        active: root.overridden
        visible: active
        asynchronous: true
        opacity: active ? 1 : 0

        sourceComponent: IconButton {
            icon: "restart_alt"
            font: Tokens.font.icon.small
            type: IconButton.Tonal
            isRound: true
            inactiveColour: Colours.tPalette.m3surfaceContainerHigh
            inactiveOnColour: Colours.palette.m3onSurfaceVariant
            onClicked: HyprSettings.unset(root.name)
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    Component {
        id: toggleComp

        ToggleRow {
            first: root.first
            last: root.last
            text: root.label
            subtext: root.subtext
            checked: !!root.value
            onToggled: root.set(checked)
        }
    }

    Component {
        id: selectComp

        SelectRow {
            first: root.first
            last: root.last
            label: root.label
            subtext: root.subtext
            menuItems: enumVariants.instances
            active: menuItems.find(i => i.text === root.enumLabel) ?? null
            fallbackText: root.enumLabel
            onSelected: item => root.set(root.enumMap[(item as EnumItem).optionKey])

            Variants {
                id: enumVariants

                model: root.enumNames

                EnumItem {}
            }
        }
    }

    Component {
        id: sliderComp

        SliderRow {
            readonly property real range: root.desc.max - root.desc.min

            first: root.first
            last: root.last
            label: root.label
            // A slider with no numeric readout is unusable for anything but volume.
            valueLabel: root.isFloat ? Number(root.value).toFixed(2) : `${Math.round(root.value)}`
            // SliderRow works in 0..1, so map through the option's own range.
            value: range > 0 ? (Number(root.value) - root.desc.min) / range : 0
            onMoved: v => {
                const raw = root.desc.min + v * range;
                root.set(root.isFloat ? Math.round(raw * 100) / 100 : Math.round(raw));
            }
        }
    }

    Component {
        id: stepperComp

        StepperRow {
            first: root.first
            last: root.last
            label: root.label
            subtext: root.subtext
            value: Number(root.value) || 0
            from: root.desc.min ?? -99999
            to: root.desc.max ?? 99999
            stepSize: root.isFloat ? 0.05 : 1
            onMoved: v => root.set(v)
        }
    }

    Component {
        id: colourComp

        HyprColourRow {
            first: root.first
            last: root.last
            label: root.label
            subtext: root.subtext
            value: `${root.value}`
            onEditingFinished: v => {
                if (v !== `${root.value}`)
                    root.set(v);
            }
        }
    }

    Component {
        id: textComp

        TextFieldRow {
            first: root.first
            last: root.last
            label: root.label
            subtext: root.subtext
            value: `${root.value}`
            onEditingFinished: v => {
                if (v !== `${root.value}`)
                    root.set(v);
            }
        }
    }

    component EnumItem: MenuItem {
        required property string modelData

        readonly property string optionKey: modelData

        text: modelData.replace(/_/g, " ")
        icon: root.enumMap[modelData] === root.value ? "check" : ""
    }
}
