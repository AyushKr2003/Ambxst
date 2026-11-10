pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Atoll: where Omarchy keeps things, and the few choices that
// only exist because Atoll runs inside Omarchy's shell. They live in their
// own file (~/.config/atoll/omarchy.json) so Ambxst's own config schema
// stays exactly upstream's.
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + (Quickshell.env("UID") || "1000"))
    readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")) + "/atoll"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/atoll"
    readonly property string dataDir: (Quickshell.env("XDG_DATA_HOME") || (home + "/.local/share")) + "/atoll"
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (home + "/.cache")) + "/atoll"
    readonly property string omarchyStateDir: home + "/.local/state/omarchy"
    readonly property string scriptsDir: decodeURIComponent(Qt.resolvedUrl("../../scripts").toString().replace("file://", ""))
    readonly property string pluginDir: decodeURIComponent(Qt.resolvedUrl("../..").toString().replace("file://", "")).replace(/\/$/, "")

    // Let Atoll push its Hyprland look (gaps, borders, rounding, blur,
    // animations) and keybinds the way it does on its own. Off: Omarchy's
    // looknfeel.lua and bindings.lua stay in charge.
    readonly property bool manageHyprland: adapter.manageHyprland === true
    // "omarchy": colours follow the Omarchy theme (default).
    // "atoll": Atoll's own matugen/preset scheme (upstream Ambxst's way).
    readonly property string colorSource: adapter.colorSource === "atoll" ? "atoll" : "omarchy"
    // Draw Atoll's wallpaper layer. Off by default: Omarchy draws the
    // background (omarchy-theme-bg-set, its background plugin).
    readonly property bool ownWallpaper: adapter.ownWallpaper === true

    // Which of Omarchy's own services are switched off in its shell.json
    // (`omarchy plugin disable ...`, which the installer offers): where
    // Atoll's daemon, OSD or dock take over.
    property var omarchyDisabled: []
    readonly property bool ownsNotifications: omarchyDisabled.indexOf("omarchy.notifications") >= 0
    readonly property bool ownsOsd: omarchyDisabled.indexOf("omarchy.osd") >= 0
    readonly property bool ownsDock: omarchyDisabled.indexOf("omarchy.dock") >= 0

    FileView {
        path: root.home + "/.config/omarchy/shell.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const cfg = JSON.parse(text());
                root.omarchyDisabled = Array.isArray(cfg.disabledPlugins) ? cfg.disabledPlugins.map(String) : [];
            } catch (e) {
                root.omarchyDisabled = [];
            }
        }
    }

    function set(key, value) {
        adapter[key] = value;
        file.writeAdapter();
    }

    FileView {
        id: file
        path: root.configDir + "/omarchy.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                writeAdapter();
        }

        JsonAdapter {
            id: adapter
            property bool manageHyprland: false
            property string colorSource: "omarchy"
            property bool ownWallpaper: false
        }
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.configDir, root.stateDir, root.dataDir, root.cacheDir])
}
