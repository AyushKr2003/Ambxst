pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Ambxst on Omarchy: the compositor model.
//
// Upstream Ambxst reads windows, workspaces and monitors from its Go daemon
// (axctl). Omarchy runs Hyprland, so this keeps the same public surface --
// focusedMonitor/focusedWorkspace/focusedClient, clients/monitors/workspaces
// `.values`, rawEvent, dispatch(), monitorFor() -- and fills it from
// Hyprland itself: its event socket (Quickshell.Hyprland) says when to
// re-read, and one `hyprctl -j` round reads the state.
//
// Dispatches are sent as Hyprland Lua dispatchers (hl.dsp.*), which is what
// Omarchy's Lua config and its own scripts use.
Singleton {
    id: root

    property var focusedMonitor: null
    property var focusedWorkspace: null
    property var focusedClient: null

    property bool overviewOpen: false
    readonly property bool nativeOverviewSupported: false
    property string compositorName: "hyprland"

    property QtObject clients: QtObject {
        property var values: []
    }
    property QtObject monitors: QtObject {
        property var values: []
    }
    property QtObject workspaces: QtObject {
        property var values: []
    }

    signal rawEvent(var event)

    function workspaceName(value) {
        const name = String(value ?? "");
        if (name.startsWith("special:"))
            return name;
        const separator = name.lastIndexOf(":");
        return separator >= 0 ? name.slice(separator + 1) : name;
    }

    function workspaceRef(value) {
        const identity = String(value ?? "");
        const name = root.workspaceName(identity);
        const numericId = Number(name);
        return {
            id: Number.isFinite(numericId) ? numericId : (parseInt(name) || 0),
            name: name,
            identity: identity
        };
    }

    function monitorFor(screen) {
        if (!screen)
            return null;
        const screenName = screen.name || screen;
        const values = root.monitors.values || [];
        for (let i = 0; i < values.length; i++) {
            if (values[i].name === screenName)
                return values[i];
        }
        return null;
    }

    // ------------------------------------------------------------ dispatch

    function luaString(value) {
        return JSON.stringify(String(value ?? ""));
    }

    function windowSelector(text) {
        const m = String(text || "").match(/address:([^\s,]+)/);
        return m ? "address:" + m[1] : "";
    }

    function clientByAddress(address) {
        const values = root.clients.values || [];
        for (let i = 0; i < values.length; i++) {
            if (values[i].address === address)
                return values[i];
        }
        return null;
    }

    function lua(expression) {
        Hyprland.dispatch(expression);
        root.scheduleRefresh();
    }

    // Accepts Ambxst's legacy dispatcher strings ("workspace 3",
    // "focuswindow address:0x..", "movetoworkspacesilent 2, address:0x..").
    function dispatch(command) {
        if (!command)
            return;
        const text = String(command).trim();
        const spaceIdx = text.indexOf(" ");
        const action = spaceIdx !== -1 ? text.substring(0, spaceIdx).trim() : text;
        const rawArgs = spaceIdx !== -1 ? text.substring(spaceIdx + 1).trim() : "";
        const win = root.windowSelector(rawArgs);
        const winArg = win ? ", window = " + root.luaString(win) : "";

        switch (action) {
        case "workspace":
            root.lua("hl.dsp.focus({ workspace = " + root.luaString(rawArgs) + " })");
            return;
        case "focuswindow":
            if (win)
                root.lua("hl.dsp.focus({ window = " + root.luaString(win) + " })");
            return;
        case "closewindow":
            if (win)
                root.lua("hl.dsp.window.close({ window = " + root.luaString(win) + " })");
            return;
        case "killactive":
            root.lua("hl.dsp.window.close()");
            return;
        case "focusmonitor":
            root.lua("hl.dsp.focus({ monitor = " + root.luaString(rawArgs) + " })");
            return;
        case "movetoworkspace":
        case "movetoworkspacesilent":
            {
                const ws = rawArgs.split(",")[0].trim();
                const follow = action === "movetoworkspace" ? "true" : "false";
                root.lua("hl.dsp.window.move({ workspace = " + root.luaString(ws) + ", follow = " + follow + winArg + " })");
                return;
            }
        case "movewindowpixel":
            {
                // "exact X% Y%, address:..": a position on the window's monitor.
                const m = rawArgs.match(/exact\s+(-?[\d.]+)(%?)\s+(-?[\d.]+)(%?)/);
                if (!m)
                    return;
                const client = root.clientByAddress(win.replace("address:", ""));
                const mon = client ? root.monitorFor(client.monitor) : root.focusedMonitor;
                const scale = mon && mon.scale ? mon.scale : 1;
                const lw = mon ? mon.width / scale : 0;
                const lh = mon ? mon.height / scale : 0;
                const x = Math.round((mon ? mon.x : 0) + (m[2] === "%" ? Number(m[1]) / 100 * lw : Number(m[1])));
                const y = Math.round((mon ? mon.y : 0) + (m[4] === "%" ? Number(m[3]) / 100 * lh : Number(m[3])));
                root.lua("hl.dsp.window.move({ x = " + x + ", y = " + y + winArg + " })");
                return;
            }
        case "togglespecialworkspace":
            root.lua("hl.dsp.workspace.toggle_special(" + root.luaString(rawArgs || "scratchpad") + ")");
            return;
        case "togglefloating":
            root.lua("hl.dsp.window.float({ action = \"toggle\"" + winArg + " })");
            return;
        case "fullscreen":
            {
                const mode = rawArgs.trim().startsWith("1") ? "maximized" : "fullscreen";
                root.lua("hl.dsp.window.fullscreen({ mode = \"" + mode + "\" })");
                return;
            }
        case "exec":
            Quickshell.execDetached(["bash", "-c", rawArgs]);
            return;
        case "overview":
            // Hyprland has no native overview: Ambxst draws its own.
            return;
        default:
            // Already a Lua dispatcher (or something Hyprland understands as is).
            root.lua(text);
        }
    }

    // ------------------------------------------------------------ state

    function applyHyprland(data) {
        if (!data)
            return;
        const monitorsRaw = Array.isArray(data.monitors) ? data.monitors : [];
        const workspacesRaw = Array.isArray(data.workspaces) ? data.workspaces : [];
        const clientsRaw = Array.isArray(data.clients) ? data.clients : [];
        const activeAddress = data.active && data.active.address ? data.active.address : "";

        const monitorNameById = {};
        const activeWsByMonitor = {};
        for (const m of monitorsRaw) {
            monitorNameById[m.id] = m.name;
            if (m.activeWorkspace)
                activeWsByMonitor[m.name] = m.activeWorkspace.id;
        }
        const ref = ws => ws ? {
            id: ws.id,
            name: root.workspaceName(ws.name || String(ws.id)),
            identity: String(ws.id)
        } : {
            id: 0,
            name: "",
            identity: ""
        };

        const mappedWorkspaces = workspacesRaw.map(ws => ({
                    id: ws.id,
                    name: root.workspaceName(ws.name || String(ws.id)),
                    identity: String(ws.id),
                    monitor: ws.monitor || monitorNameById[ws.monitorID] || "",
                    active: activeWsByMonitor[ws.monitor] === ws.id,
                    layout: String(ws.tiledLayout || ""),
                    windows: ws.windows || 0,
                    hasfullscreen: ws.hasfullscreen === true,
                    lastwindow: ws.lastwindow || "",
                    lastwindowtitle: ws.lastwindowtitle || ""
                })).sort((a, b) => a.id - b.id);

        const mappedClients = clientsRaw.filter(c => c.mapped !== false).map(c => ({
                    address: c.address,
                    class: c.class || "",
                    initialClass: c.initialClass || "",
                    title: c.title || "",
                    initialTitle: c.initialTitle || "",
                    workspace: {
                        id: c.workspace ? c.workspace.id : 0,
                        name: root.workspaceName(c.workspace ? c.workspace.name : ""),
                        identity: String(c.workspace ? c.workspace.id : "")
                    },
                    monitor: monitorNameById[c.monitor] || "",
                    floating: c.floating === true,
                    fullscreen: (c.fullscreen || 0) > 0,
                    hidden: c.hidden === true,
                    pinned: c.pinned === true,
                    mapped: true,
                    at: c.at || [0, 0],
                    size: c.size || [0, 0],
                    xwayland: c.xwayland === true,
                    pid: c.pid || 0,
                    grouped: c.grouped || [],
                    is_focused: c.address === activeAddress,
                    focusHistoryID: c.focusHistoryID !== undefined ? c.focusHistoryID : 999999
                }));

        const mappedMonitors = monitorsRaw.map(m => {
            const active = ref(m.activeWorkspace);
            const special = m.specialWorkspace && m.specialWorkspace.id ? ref(m.specialWorkspace) : null;
            return {
                id: m.name,
                name: m.name,
                description: m.description || "",
                focused: m.focused === true,
                width: m.width,
                height: m.height,
                refreshRate: m.refreshRate,
                scale: m.scale || 1,
                x: m.x || 0,
                y: m.y || 0,
                transform: m.transform || 0,
                reserved: m.reserved || [0, 0, 0, 0],
                overviewOpen: false,
                activeWorkspace: active,
                visibleWorkspace: special || active,
                specialWorkspace: special
            };
        });

        root.workspaces.values = mappedWorkspaces;
        root.clients.values = mappedClients;
        root.monitors.values = mappedMonitors;

        const fMon = mappedMonitors.find(m => m.focused) || null;
        if (JSON.stringify(fMon) !== JSON.stringify(root.focusedMonitor))
            root.focusedMonitor = fMon;
        const fWs = fMon ? (mappedWorkspaces.find(ws => ws.id === fMon.activeWorkspace.id) || null) : null;
        if (JSON.stringify(fWs) !== JSON.stringify(root.focusedWorkspace))
            root.focusedWorkspace = fWs;
        const fClient = mappedClients.find(c => c.is_focused) || null;
        if (JSON.stringify(fClient) !== JSON.stringify(root.focusedClient))
            root.focusedClient = fClient;

        root.rawEvent({
            service: "compositor",
            method: "state",
            data: data
        });
    }

    property Process stateProcess: Process {
        command: ["bash", "-c", "printf '{\"clients\":%s,\"workspaces\":%s,\"monitors\":%s,\"active\":%s}' " + "\"$(hyprctl -j clients)\" \"$(hyprctl -j workspaces)\" \"$(hyprctl -j monitors)\" \"$(hyprctl -j activewindow)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyHyprland(JSON.parse(text));
                } catch (e) {
                    console.warn("AxctlService: could not read Hyprland state:", e);
                }
                if (root.refreshPending) {
                    root.refreshPending = false;
                    refreshTimer.restart();
                }
            }
        }
    }

    property bool refreshPending: false
    function scheduleRefresh() {
        refreshTimer.restart();
    }
    function refresh() {
        if (root.stateProcess.running) {
            root.refreshPending = true;
            return;
        }
        root.stateProcess.running = true;
    }

    property Timer refreshTimer: Timer {
        id: refreshTimer
        interval: 40
        onTriggered: root.refresh()
    }

    // Events that change nothing Ambxst draws.
    readonly property var ignoredEvents: ["submap", "screencast", "bell", "minimized", "ignoregrouplock", "lockgroups", "configreloaded", "custom"]

    property Connections hyprConnections: Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (root.ignoredEvents.indexOf(event.name) >= 0)
                return;
            root.scheduleRefresh();
        }
    }

    Component.onCompleted: root.refresh()
}
