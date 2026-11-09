import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "modules/bar"
import "modules/bar/workspaces"
import "modules/notifications"
import "modules/widgets/dashboard/wallpapers"
import "modules/notch"
import "modules/widgets/overview"
import "modules/widgets/presets"
import "modules/services"
import "modules/corners"
import "modules/frame"
import "modules/components"
import "modules/desktop"
import "modules/dock"
import "modules/globals"
import "modules/shell"
import "modules/theme"
import "config"
import "modules/shell/osd"
import "modules/tools"

// Ambxst for Omarchy -- the entry point of the `ambxst.bar` plugin.
//
// This is Ambxst's shell.qml as an Omarchy full-bar plugin: it runs inside
// the one omarchy-shell process (no second Quickshell, no Go daemon) and
// builds the same windows -- the unified panel (bar, notch, dock, frame),
// screen corners, overview, presets, tools, settings and OSD. Omarchy is
// the engine: modules/services/BackendService.qml answers Ambxst's backend
// calls with Omarchy commands, and OmarchyTheme keeps Ambxst's colours in
// the Omarchy theme.
//
// The host injects the properties below, as it does for its own bar, and
// reads position/vertical/barSize/barHidden and the summon contract
// (summonBarWidget, hideBarWidget, isBarWidgetOpen, panelWidgetIdAt).
Item {
    id: root

    property string omarchyPath: Quickshell.env("OMARCHY_PATH")
    property var barWidgetRegistry: null
    property var pluginRegistry: null
    property var barConfig: ({})
    property var shell: null
    property var manifest: null

    readonly property string version: manifest && manifest.version ? manifest.version : Config.version

    // ------------------------------------------------------------ host state

    readonly property string position: {
        const p = Config.bar && Config.bar.position ? Config.bar.position : "top";
        return ["top", "bottom", "left", "right"].indexOf(p) >= 0 ? p : "top";
    }
    readonly property bool vertical: position === "left" || position === "right"
    property bool barHidden: false
    // Each screen's bar thickness, for the host and Omarchy's popups.
    property var screenBarSizes: ({})
    readonly property int barSize: {
        const sizes = Object.keys(screenBarSizes).map(k => screenBarSizes[k]);
        return barHidden || sizes.length === 0 ? 0 : Math.max.apply(null, sizes);
    }
    function barSizeFor(screenName) {
        return barHidden ? 0 : (screenBarSizes[screenName] || barSize);
    }
    function setScreenBarSize(screenName, size) {
        if (screenBarSizes[screenName] === size)
            return;
        const next = Object.assign({}, screenBarSizes);
        next[screenName] = size;
        screenBarSizes = next;
    }
    readonly property string fontFamily: Config.theme && Config.theme.font ? Config.theme.font : ""

    // ---------------------------------------------------- bar contract
    //
    // Omarchy routes its panel hotkeys through the active bar: SUPER+CTRL+W
    // (Wi-Fi), +B (Bluetooth), +A (audio), +P (power) and so on arrive here
    // with Omarchy's widget ids. Each opens the Ambxst surface for that job.

    readonly property var widgetTargets: ({
            "omarchy.network": {
                settings: 0
            },
            "omarchy.bluetooth": {
                settings: 1
            },
            "omarchy.audio": {
                settings: 2
            },
            "omarchy.power": {
                run: "powermenu"
            },
            "omarchy.clock": {
                run: "dashboard"
            },
            "omarchy.weather": {
                run: "dashboard"
            },
            "omarchy.media": {
                run: "dashboard"
            },
            "omarchy.monitor": {
                run: "dashboard"
            },
            "omarchy.system-update": {
                settings: 7
            }
        })

    function focusedScreenName() {
        const m = Hyprland.focusedMonitor;
        return m ? m.name : (Quickshell.screens.length ? Quickshell.screens[0].name : "");
    }

    function openTarget(target) {
        if (!target)
            return false;
        if (target.settings !== undefined) {
            GlobalStates.settingsCurrentTab = target.settings;
            if (!GlobalStates.settingsWindowVisible)
                GlobalShortcuts.toggleSettings(focusedScreenName());
            return true;
        }
        if (target.run) {
            GlobalShortcuts.run(target.run);
            return true;
        }
        return false;
    }

    function summonBarWidget(id) {
        if (barHidden)
            return false;
        return openTarget(widgetTargets[String(id || "")]);
    }

    function hideBarWidget(id) {
        const t = widgetTargets[String(id || "")];
        if (!t)
            return false;
        if (t.settings !== undefined && GlobalStates.settingsWindowVisible) {
            GlobalShortcuts.toggleSettings(focusedScreenName());
            return true;
        }
        if (t.run) {
            Visibilities.setActiveModule("");
            return true;
        }
        return false;
    }

    function isBarWidgetOpen(id) {
        const t = widgetTargets[String(id || "")];
        if (!t)
            return false;
        if (t.settings !== undefined)
            return GlobalStates.settingsWindowVisible && GlobalStates.settingsCurrentTab === t.settings;
        return Visibilities.currentActiveModule === t.run;
    }

    // SUPER+CTRL+1..9 count hosted bar widgets; Ambxst's bar hosts none.
    function panelWidgetIdAt(section, index) {
        return "";
    }

    // Omarchy's bar API for hosted widgets (tooltips, popouts); unused by
    // Ambxst's own bar but answered so callers never hit a missing method.
    function requestPopout(owner) {}
    function releasePopout(owner) {}
    function showTooltip(target, text) {}
    function hideTooltip(target) {}

    // ------------------------------------------------------- the shell

    // Ambxst's own fonts, bundled so the look needs no extra packages:
    // Phosphor (its icon font), Roboto Condensed (its UI font) and League
    // Gothic (the big clock). Application fonts: every Ambxst file sees them.
    FontLoader {
        source: Qt.resolvedUrl("assets/fonts/Phosphor-Bold.ttf")
    }
    FontLoader {
        source: Qt.resolvedUrl("assets/fonts/RobotoCondensed.ttf")
    }
    FontLoader {
        source: Qt.resolvedUrl("assets/fonts/RobotoCondensed-Italic.ttf")
    }
    FontLoader {
        source: Qt.resolvedUrl("assets/fonts/LeagueGothic.ttf")
    }

    ContextMenu {
        id: contextMenu
        screen: Quickshell.screens[0]
        Component.onCompleted: Visibilities.setContextMenu(contextMenu)
    }

    // Ambxst's wallpaper manager (one per screen). It only draws when
    // chosen in ~/.config/ambxst/omarchy.json; otherwise Omarchy draws
    // the background and these just drive the dashboard's Wallpapers tab.
    Variants {
        model: Quickshell.screens

        Loader {
            id: wallpaperLoader
            active: true
            required property ShellScreen modelData
            sourceComponent: Wallpaper {
                screen: wallpaperLoader.modelData
            }
        }
    }

    Variants {
        model: Quickshell.screens

        Loader {
            id: desktopLoader
            active: Config.desktop.enabled && SuspendManager.wakeReady
            required property ShellScreen modelData
            sourceComponent: Desktop {
                screen: desktopLoader.modelData
            }
        }
    }

    // The unified panel (bar, notch, dock, frame) and its reservations.
    Variants {
        model: Quickshell.screens

        Item {
            id: screenShellContainer
            required property ShellScreen modelData

            UnifiedShellPanel {
                id: unifiedPanel
                targetScreen: screenShellContainer.modelData
            }

            readonly property int reservedBar: reservations.barEnabled && unifiedPanel.pinned ? (unifiedPanel.barPosition === "left" || unifiedPanel.barPosition === "right" ? unifiedPanel.barTargetWidth : unifiedPanel.barTargetHeight) + unifiedPanel.barOuterMargin : 0
            onReservedBarChanged: root.setScreenBarSize(modelData.name, reservedBar)
            Component.onCompleted: root.setScreenBarSize(modelData.name, reservedBar)

            Loader {
                active: Config.theme.enableCorners && Config.roundness > 0
                sourceComponent: ScreenCorners {
                    screen: screenShellContainer.modelData
                }
            }

            ReservationWindows {
                id: reservations
                screen: screenShellContainer.modelData

                barEnabled: {
                    const list = (Config.bar && Config.bar.screenList !== undefined ? Config.bar.screenList : []);
                    return !root.barHidden && (!list || list.length === 0 || list.indexOf(screen.name) !== -1);
                }
                barPosition: unifiedPanel.barPosition
                barPinned: unifiedPanel.pinned
                barSize: (unifiedPanel.barPosition === "left" || unifiedPanel.barPosition === "right") ? unifiedPanel.barTargetWidth : unifiedPanel.barTargetHeight
                barOuterMargin: unifiedPanel.barOuterMargin

                dockEnabled: {
                    if (!((Config.dock && Config.dock.enabled !== undefined ? Config.dock.enabled : false)) || (Config.dock && Config.dock.theme !== undefined ? Config.dock.theme : "default") === "integrated")
                        return false;
                    const list = (Config.dock && Config.dock.screenList !== undefined ? Config.dock.screenList : []);
                    if (!list || list.length === 0)
                        return true;
                    return list.indexOf(screenShellContainer.modelData.name) !== -1;
                }
                dockPosition: unifiedPanel.dockPosition
                dockPinned: unifiedPanel.dockPinned
                dockHeight: unifiedPanel.dockHeight
                containBar: unifiedPanel.containBar

                frameEnabled: (Config.bar && Config.bar.frameEnabled !== undefined ? Config.bar.frameEnabled : false)
                frameThickness: (Config.bar && Config.bar.frameThickness !== undefined ? Config.bar.frameThickness : 6)

                sidebarEnabled: GlobalStates.assistantVisible && screenShellContainer.modelData.name === GlobalStates.assistantScreenName
                sidebarPinned: GlobalStates.assistantPinned
                sidebarWidth: GlobalStates.assistantWidth
                sidebarPosition: GlobalStates.assistantPosition
            }
        }
    }

    Variants {
        model: {
            const screens = Quickshell.screens;
            const list = (Config.bar && Config.bar.screenList !== undefined ? Config.bar.screenList : []);
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.indexOf(screen.name) !== -1);
        }

        Loader {
            id: overviewLoader
            active: ((Config.overview && Config.overview.enabled !== undefined ? Config.overview.enabled : true)) && SuspendManager.wakeReady && (Visibilities.getForScreen(modelData.name) ? Visibilities.getForScreen(modelData.name).overview : false)
            required property ShellScreen modelData
            sourceComponent: OverviewPopup {
                screen: overviewLoader.modelData
            }
        }
    }

    Variants {
        model: {
            const screens = Quickshell.screens;
            const list = (Config.bar && Config.bar.screenList !== undefined ? Config.bar.screenList : []);
            if (!list || list.length === 0)
                return screens;
            return screens.filter(screen => list.indexOf(screen.name) !== -1);
        }

        Loader {
            id: presetsLoader
            active: SuspendManager.wakeReady && (Visibilities.getForScreen(modelData.name) ? Visibilities.getForScreen(modelData.name).presets : false)
            required property ShellScreen modelData
            sourceComponent: PresetsPopup {
                screen: presetsLoader.modelData
            }
        }
    }

    // The session lock is Omarchy's (omarchy.lock): LockscreenService asks
    // it to lock. Ambxst's look applied to the compositor only on request.
    Loader {
        active: OmarchyBridge.manageHyprland
        sourceComponent: CompositorConfig {}
    }

    Variants {
        model: Quickshell.screens

        Loader {
            id: screenshotLoader
            active: GlobalStates.screenshotToolVisible
            required property ShellScreen modelData
            sourceComponent: ScreenshotTool {
                targetScreen: screenshotLoader.modelData
            }
        }
    }

    Variants {
        model: Quickshell.screens

        Loader {
            id: screenshotOverlayLoader
            active: SuspendManager.wakeReady
            required property ShellScreen modelData
            sourceComponent: ScreenshotOverlay {
                targetScreen: screenshotOverlayLoader.modelData
            }
        }
    }

    Loader {
        id: screenRecordLoader
        active: SuspendManager.wakeReady && GlobalStates.screenRecordToolVisible
        source: "modules/tools/ScreenrecordTool.qml"

        onLoaded: {
            if (GlobalStates.screenRecordToolVisible && item)
                item.open();
        }

        Connections {
            target: GlobalStates
            function onScreenRecordToolVisibleChanged() {
                if (screenRecordLoader.status === Loader.Ready) {
                    if (GlobalStates.screenRecordToolVisible)
                        screenRecordLoader.item.open();
                    else
                        screenRecordLoader.item.close();
                }
            }
        }

        Connections {
            target: screenRecordLoader.item
            ignoreUnknownSignals: true
            function onVisibleChanged() {
                if (!screenRecordLoader.item.visible && GlobalStates.screenRecordToolVisible)
                    GlobalStates.screenRecordToolVisible = false;
            }
        }
    }

    Loader {
        active: SuspendManager.wakeReady && GlobalStates.mirrorWindowVisible
        source: "modules/tools/MirrorWindow.qml"
    }

    Loader {
        active: SuspendManager.wakeReady && GlobalStates.settingsWindowVisible
        source: "modules/widgets/config/SettingsWindow.qml"
    }

    // Ambxst's OSD, once Omarchy's own (omarchy.osd) is switched off, so
    // there is never a second OSD on screen.
    Variants {
        model: Quickshell.screens

        Loader {
            id: osdLoader
            active: SuspendManager.wakeReady && OmarchyBridge.ownsOsd
            required property ShellScreen modelData
            sourceComponent: OSD {
                targetScreen: osdLoader.modelData
            }
        }
    }

    // ------------------------------------------------------ omarchy bar hide
    //
    // `omarchy toggle bar` (SUPER+SHIFT+SPACE) flips its flag and pings the
    // omarchy.bar target; Ambxst's bar follows by unpinning (auto-hide).

    IpcHandler {
        target: "omarchy.bar"
        function syncHidden(): void {
            hiddenProbe.running = true;
        }
    }
    Process {
        id: hiddenProbe
        running: true
        command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
        stdout: SplitParser {
            onRead: line => {
                const hidden = String(line).trim() === "yes";
                if (hidden !== root.barHidden) {
                    root.barHidden = hidden;
                    GlobalStates.barPinToggled();
                }
            }
        }
    }

    // ------------------------------------------------------------- startup

    QtObject {
        Component.onCompleted: {
            Qt.callLater(() => {
                let _ = OmarchyTheme.active; // colours from the Omarchy theme
                _ = GlobalShortcuts.appId; // the `ambxst` IPC target
                _ = WallpaperCommandService;
                _ = PresetCommandService;
                _ = Notifications.silent; // the notification daemon
                PresetsService.initialize();
            });
        }
    }

    Timer {
        interval: 2000
        running: true
        onTriggered: {
            let _ = NightLightClient.active;
            _ = GameModeClient.toggled;
            _ = CaffeineClient.inhibit;
        }
    }
}
