pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "../services"
import "OmarchyPalette.js" as Palette

// Atoll: keeps Atoll's colour file in the Omarchy theme.
//
// Atoll draws every surface from ~/.cache/atoll/colors.json (Colors.qml
// watches it). While the colour source is "omarchy" (the default) this
// writes that file from the current Omarchy theme's colors.toml, and again
// whenever `omarchy theme set` pushes a new theme into the shell -- Omarchy's
// own palette singleton changing is the signal, so nothing polls.
Singleton {
    id: root

    readonly property bool active: OmarchyBridge.colorSource === "omarchy"
    readonly property string themePath: OmarchyBridge.omarchyStateDir + "/current/theme/colors.toml"
    readonly property string outputPath: OmarchyBridge.cacheDir + "/colors.json"
    property string lastWritten: ""
    // The parsed theme, for anything that wants a raw Omarchy colour.
    property var theme: ({})

    function regenerate() {
        if (!root.active)
            return;
        root.theme = Palette.parseToml(themeFile.text());
        const json = JSON.stringify(Palette.build(root.theme), null, 2) + "\n";
        if (json === root.lastWritten)
            return;
        root.lastWritten = json;
        ensureDir.running = true;
    }

    onActiveChanged: if (active)
        themeFile.reload()

    FileView {
        id: themeFile
        path: root.themePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.regenerate()
    }

    // `current/theme` is a symlink Omarchy repoints on a theme switch, which
    // a file watch on the old target never sees; the shell's palette does.
    Connections {
        target: Commons.Color
        function onAccentChanged() {
            reloadTimer.restart();
        }
        function onBackgroundChanged() {
            reloadTimer.restart();
        }
        function onForegroundChanged() {
            reloadTimer.restart();
        }
    }

    Timer {
        id: reloadTimer
        interval: 150
        onTriggered: themeFile.reload()
    }

    Process {
        id: ensureDir
        command: ["mkdir", "-p", OmarchyBridge.cacheDir]
        onExited: output.setText(root.lastWritten)
    }

    FileView {
        id: output
        path: root.outputPath
        atomicWrites: true
        printErrors: false
    }
}
