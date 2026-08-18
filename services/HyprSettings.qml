pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.services

// Owns the Hyprland options set from the Nexus.
//
// Hyprland cannot write its own config file and `hyprctl keyword` only lives until
// the next reload, so the durable copy of every GUI-set option is
// `GlobalConfig.hyprland.overrides` in shell.json. This singleton is the one place
// that pushes that map into the compositor: once on startup, on every edit, and
// again after each `configreloaded` (which wipes runtime keywords).
//
// Everything here is keyed by Hyprland's own flat option names, e.g.
// "general:gaps_in" / "decoration:blur:size" / "general:col.active_border".
Singleton {
    id: root

    // Hyprland's full option table, in its own order. Empty until the first
    // `hyprctl descriptions` round-trip completes.
    readonly property var descriptions: Hypr.extras.optionDescriptions
    readonly property bool ready: descriptions.length > 0

    readonly property var overrides: GlobalConfig.hyprland.overrides
    readonly property int overrideCount: Object.keys(overrides).length

    // name -> descriptor, for O(1) lookups from delegates.
    readonly property var byName: {
        const map = {};
        for (const d of descriptions)
            map[d.name] = d;
        return map;
    }

    // Sections that can hard-lock or visually break the compositor. Hidden unless
    // `hyprland.showAdvanced`, but still applied if already overridden.
    readonly property var advancedCategories: ["debug", "experimental", "quirks", "opengl", "render", "ecosystem", "input-capture"]

    // Edits waiting to be flushed to Hyprland by applyTimer.
    readonly property var pending: ({})

    // Ordered list of categories present in `descriptions`, with counts.
    readonly property var categories: {
        const seen = {};
        const list = [];
        for (const d of descriptions) {
            const c = d.category;
            if (!c)
                continue;
            if (!seen[c]) {
                seen[c] = {
                    name: c,
                    count: 0,
                    overridden: 0,
                    advanced: root.advancedCategories.includes(c.split(":")[0])
                };
                list.push(seen[c]);
            }
            seen[c].count++;
            if (root.overrides.hasOwnProperty(d.name))
                seen[c].overridden++;
        }
        return list;
    }

    // The value in effect for `name`: our override if we set one, else whatever
    // Hyprland currently reports, else the documented default.
    function valueOf(name: string): var {
        if (overrides.hasOwnProperty(name))
            return overrides[name];
        const d = byName[name];
        if (d === undefined)
            return undefined;
        return d.current !== undefined && d.current !== null ? d.current : d.default;
    }

    function isOverridden(name: string): bool {
        return overrides.hasOwnProperty(name);
    }

    // The value Hyprland would use with our override removed. This is the *config
    // file's* value, which we cannot know without a reload, so the documented
    // default is the closest honest answer for a "reset to" label.
    function baseValueOf(name: string): var {
        return byName[name]?.default;
    }

    function set(name: string, value: var): void {
        const d = byName[name];
        if (d === undefined) {
            console.warn(logCat, "Refusing to set unknown Hyprland option", name);
            return;
        }

        // Coerce to the type Hyprland documented, so a spin box handing us a string
        // does not end up quoted as a lua string literal.
        if (d.type === "number")
            value = Number(value);
        else if (d.type === "bool")
            value = !!value;
        else
            value = `${value}`;

        // QVariantMap comes across as a plain JS object; mutating it in place will
        // not trip the property's change detection, so always assign a fresh copy.
        const next = Object.assign({}, overrides);
        next[name] = value;
        GlobalConfig.hyprland.overrides = next;

        applyOne(name, value);
    }

    // Drop an override. There is no "unset keyword" in Hyprland, so the only way
    // back to the config file's value is a full reload - which also wipes every
    // other override, hence the re-apply afterwards (driven by onConfigReloaded).
    function unset(name: string): void {
        if (!overrides.hasOwnProperty(name))
            return;

        const next = Object.assign({}, overrides);
        delete next[name];
        GlobalConfig.hyprland.overrides = next;

        Hypr.extras.reloadConfig();
    }

    function unsetAll(): void {
        GlobalConfig.hyprland.overrides = ({});
        Hypr.extras.reloadConfig();
    }

    function unsetCategory(category: string): void {
        const next = Object.assign({}, overrides);
        let changed = false;
        for (const name of Object.keys(next))
            if (root.byName[name]?.category === category) {
                delete next[name];
                changed = true;
            }
        if (!changed)
            return;

        GlobalConfig.hyprland.overrides = next;
        Hypr.extras.reloadConfig();
    }

    // Coalesce rapid edits (a slider drag is one call per frame) into a single
    // batched hyprctl request. Without this, dragging a gap slider floods the
    // socket and each request triggers a `descriptions` refresh.
    function applyOne(name: string, value: var): void {
        pending[name] = value;
        applyTimer.restart();
    }

    function applyAll(): void {
        if (!GlobalConfig.hyprland.enabled)
            return;

        const all = {};
        for (const name of Object.keys(overrides))
            if (root.byName.hasOwnProperty(name))
                all[name] = overrides[name];

        if (Object.keys(all).length > 0)
            Hypr.extras.applyOptions(all);
    }

    // `descriptions` arrives asynchronously; apply as soon as we know the option
    // names are real (and thus which stale overrides to drop).
    onReadyChanged: if (ready)
        applyAll()

    LoggingCategory {
        id: logCat

        name: "caelestia.hyprsettings"
        defaultLogLevel: LoggingCategory.Info
    }

    Timer {
        id: applyTimer

        interval: 16
        onTriggered: {
            if (!GlobalConfig.hyprland.enabled) {
                for (const k of Object.keys(root.pending))
                    delete root.pending[k];
                return;
            }

            const batch = Object.assign({}, root.pending);
            for (const k of Object.keys(root.pending))
                delete root.pending[k];

            if (Object.keys(batch).length > 0)
                Hypr.extras.applyOptions(batch);
        }
    }

    // A reload resets every runtime keyword back to the config file, so replay.
    // Delayed because Hyprland is still mid-reload when the event fires.
    Timer {
        id: reapplyTimer

        interval: 250
        onTriggered: root.applyAll()
    }

    Connections {
        function onConfigReloaded(): void {
            if (GlobalConfig.hyprland.applyOnReload)
                reapplyTimer.restart();
        }

        target: Hypr
    }

    IpcHandler {
        function get(name: string): string {
            const v = root.valueOf(name);
            return v === undefined ? "" : `${v}`;
        }

        function set(name: string, value: string): string {
            const d = root.byName[name];
            if (d === undefined)
                return `Unknown option: ${name}`;
            root.set(name, d.type === "bool" ? value === "true" || value === "1" : value);
            return `${name} = ${value}`;
        }

        function unset(name: string): string {
            root.unset(name);
            return `Unset ${name}`;
        }

        function reset(): string {
            const n = root.overrideCount;
            root.unsetAll();
            return `Cleared ${n} override(s)`;
        }

        function list(): string {
            return Object.keys(root.overrides).sort().map(k => `${k} = ${root.overrides[k]}`).join("\n");
        }

        target: "hyprsettings"
    }
}
