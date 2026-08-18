#pragma once

#include "configobject.hpp"

#include <qvariant.h>

namespace caelestia::config {

// Hyprland options the shell owns.
//
// Hyprland has no way to write back to its own config file, and `hyprctl keyword`
// changes live only until the next `hyprctl reload`. So the durable copy of
// anything set from the Nexus lives here, in shell.json, and the shell replays it
// onto Hyprland on startup and after every config reload. That also makes the
// Nexus page a plain config editor like every other page, instead of a special
// case that has to parse and rewrite lua.
class HyprlandConfig : public ConfigObject {
    Q_OBJECT
    QML_ANONYMOUS

    // Master switch. Turning this off leaves overrides recorded but stops applying
    // them, so the config file's own values win after the next reload.
    CONFIG_PROPERTY(bool, enabled, true)
    // Flat `section:option` -> value, exactly as `hyprctl descriptions` names them
    // (e.g. "general:gaps_in", "decoration:blur:size", "general:col.active_border").
    CONFIG_PROPERTY(QVariantMap, overrides, {})
    // Replay overrides after Hyprland reloads its config. Without this, editing the
    // lua config or any `hyprctl reload` silently reverts everything set here.
    CONFIG_PROPERTY(bool, applyOnReload, true)
    // Show every option Hyprland reports, including the debug/experimental sections
    // that can wedge the compositor. Off by default.
    CONFIG_PROPERTY(bool, showAdvanced, false)

public:
    explicit HyprlandConfig(QObject* parent = nullptr)
        : ConfigObject(parent) {}
};

} // namespace caelestia::config
