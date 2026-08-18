import QtQuick
import Quickshell
import Caelestia.Config
import qs.services

Scope {
    Component.onCompleted: {
        // Force certain singletons to load on shell init instead of lazily

        IdleInhibitor;
        GameMode;
        // Replays GlobalConfig.hyprland.overrides onto the compositor. Must be eager:
        // nothing references it until the Nexus page is opened, and by then the
        // session has been running with unapplied settings.
        HyprSettings;
        Notifs;
        Players;
        Brightness;
        Weather.reload();

        if (GlobalConfig.utilities.vpn.enabled)
            VPN;
    }
}
