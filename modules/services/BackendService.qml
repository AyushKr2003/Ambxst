pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

// Ambxst on Omarchy: the backend, in process.
//
// Upstream Ambxst talks JSON-RPC to its Go daemon (`ambxst`) over a Unix
// socket. Inside Omarchy's shell there is no such daemon; Omarchy is the
// engine. This singleton keeps upstream's API -- call(method, params, cb),
// notify(), addSubscription(services, cb), setSubscriptionActive(),
// removeSubscription() -- so every Ambxst consumer runs unchanged, and
// answers each method with, in order of preference:
//
//   1. an Omarchy command or state file (omarchy-toggle-idle, the
//      nightlight/screen-recording commands, Omarchy's clipboard history,
//      omarchy-hyprland-workspace-layout-*, omarchy-system-lock, ...)
//   2. a Quickshell service (UPower power profiles, Hyprland)
//   3. a base Omarchy package (nmcli, grim, imagemagick, tesseract, zbar,
//      wl-clipboard, hyprsunset), through a small script in ../../scripts
//      when it needs more than one call.
//
// Methods with nothing behind them on Omarchy answer an error, the way the
// daemon answers an unknown method; consumers already handle that.
Singleton {
    id: root

    // Upstream exposes these; with no socket the backend is always "up".
    property bool connected: true
    property bool socketAvailable: true

    readonly property string scripts: OmarchyBridge.scriptsDir
    readonly property string home: OmarchyBridge.home

    // =================================================================
    // RPC surface
    // =================================================================

    function call(method, params, callback) {
        const reply = (result, error) => {
            if (typeof callback !== "function")
                return;
            Qt.callLater(() => callback(result, error));
        };
        const handler = root.handlers[method];
        if (!handler) {
            reply(null, "not available on Omarchy: " + method);
            return;
        }
        try {
            handler(params || {}, reply);
        } catch (e) {
            console.warn("BackendService:", method, "failed:", e);
            reply(null, String(e));
        }
    }

    function notify(method, params) {
        root.call(method, params, undefined);
    }

    // =================================================================
    // Subscriptions
    // =================================================================

    property var subscriptions: ({})
    property int nextSubId: 1
    // Bumped on every change, so the per-service watchers below re-check
    // whether anyone is listening.
    property int subscriptionRevision: 0

    function addSubscription(services, callback) {
        const key = root.nextSubId++;
        root.subscriptions[key] = {
            services: services || [],
            callback: callback,
            active: true
        };
        root.subscriptionRevision++;
        return key;
    }

    function setSubscriptionActive(key, active) {
        const sub = root.subscriptions[key];
        if (!sub)
            return;
        sub.active = active === true;
        root.subscriptionRevision++;
    }

    function removeSubscription(key) {
        delete root.subscriptions[key];
        root.subscriptionRevision++;
    }

    function wants(group) {
        void root.subscriptionRevision;
        for (const key in root.subscriptions) {
            const sub = root.subscriptions[key];
            if (sub.active && sub.services.indexOf(group) >= 0)
                return true;
        }
        return false;
    }

    function publish(service, data) {
        const group = String(service).split(".")[0];
        for (const key in root.subscriptions) {
            const sub = root.subscriptions[key];
            if (!sub || !sub.active || sub.services.indexOf(group) < 0)
                continue;
            try {
                sub.callback(service, data);
            } catch (e) {
                console.warn("BackendService: subscriber for", service, "failed:", e);
            }
        }
    }

    // =================================================================
    // Process helpers
    // =================================================================

    Component {
        id: processComponent
        Process {
            id: proc
            property var done: null
            property int exitCode: -1
            property bool exitedFlag: false
            property bool outDone: false
            property bool errDone: false

            function finish() {
                if (!exitedFlag || !outDone || !errDone)
                    return;
                const cb = done;
                done = null;
                if (cb)
                    cb(exitCode, out.text, err.text);
                proc.destroy();
            }

            stdout: StdioCollector {
                id: out
                onStreamFinished: {
                    proc.outDone = true;
                    proc.finish();
                }
            }
            stderr: StdioCollector {
                id: err
                onStreamFinished: {
                    proc.errDone = true;
                    proc.finish();
                }
            }
            onExited: code => {
                proc.exitCode = code;
                proc.exitedFlag = true;
                proc.finish();
            }
        }
    }

    // Runs argv (never through a shell unless argv says so), then
    // done(exitCode, stdout, stderr).
    function run(argv, done) {
        const p = processComponent.createObject(root, {
            command: argv,
            done: done || null
        });
        p.running = true;
    }

    // Runs a bash snippet with its arguments passed positionally ($1, $2...):
    // values are never spliced into the script text.
    function sh(script, args, done) {
        root.run(["bash", "-c", script, "ambxst"].concat(args || []), done);
    }

    function runJson(argv, reply) {
        root.run(argv, (code, stdout, stderr) => {
            try {
                reply(JSON.parse(stdout), null);
            } catch (e) {
                reply(null, (stderr || stdout || ("exit " + code)).trim());
            }
        });
    }

    function script(name) {
        return root.scripts + "/" + name;
    }

    // =================================================================
    // Method table
    // =================================================================

    readonly property var handlers: ({
            // ---- compositor -------------------------------------------
            "compositor.state": (p, reply) => reply({}, null),
            "compositor.dispatch": (p, reply) => root.compositorDispatch(p.args || [], reply),
            "compositor.eval": (p, reply) => {
                if (!OmarchyBridge.manageHyprland) {
                    reply({
                        skipped: true
                    }, null);
                    return;
                }
                root.run(["hyprctl", "eval", String(p.expression || "")], code => reply({
                            exit_code: code
                        }, null));
            },

            // ---- caffeine: Omarchy's stay-awake ------------------------
            "caffeine.get": (p, reply) => reply({
                    inhibit: root.stayAwake
                }, null),
            "caffeine.set": (p, reply) => {
                root.run(["bash", "-c", "omarchy-toggle-idle \"$1\" >/dev/null 2>&1", "ambxst", p.inhibit ? "stay-awake" : "allow-idle"], () => {
                    root.probeStayAwake();
                    reply({
                        inhibit: p.inhibit === true
                    }, null);
                });
            },
            "caffeine.restore": (p, reply) => reply({}, null),

            // ---- game mode ---------------------------------------------
            "gamemode.get": (p, reply) => reply({
                    enabled: root.gameMode
                }, null),
            "gamemode.toggle": (p, reply) => {
                root.setGameMode(!root.gameMode);
                reply({
                    enabled: root.gameMode
                }, null);
            },
            "gamemode.set": (p, reply) => {
                root.setGameMode(p.enabled === true);
                reply({
                    enabled: root.gameMode
                }, null);
            },

            // ---- night light: Omarchy's hyprsunset toggle ---------------
            "nightlight.get": (p, reply) => root.probeNightLight(state => reply(state, null)),
            "nightlight.toggle": (p, reply) => root.run(["bash", "-c", "omarchy-toggle-nightlight >/dev/null 2>&1"], () => root.probeNightLight(state => reply(state, null))),
            "nightlight.set": (p, reply) => root.setNightLight(p, reply),

            // ---- power profiles: power-profiles-daemon via UPower -------
            "powerprofile.current": (p, reply) => reply(root.powerState(), null),
            "powerprofile.available": (p, reply) => reply(root.powerState(), null),
            "powerprofile.set": (p, reply) => {
                const map = {
                    "power-saver": PowerProfile.PowerSaver,
                    "balanced": PowerProfile.Balanced,
                    "performance": PowerProfile.Performance
                };
                if (map[p.profile] === undefined) {
                    reply(null, "unknown profile " + p.profile);
                    return;
                }
                PowerProfiles.profile = map[p.profile];
                reply(root.powerState(), null);
            },

            // ---- screen recording: omarchy-capture-screenrecording -----
            "recorder.status": (p, reply) => reply(root.recorderState(), null),
            "recorder.dir": (p, reply) => root.sh('[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs; echo "${OMARCHY_SCREENRECORD_DIR:-${XDG_VIDEOS_DIR:-$HOME/Videos}}"', [], (c, out) => reply({
                            dir: out.trim()
                        }, null)),
            "recorder.start": (p, reply) => root.startRecording(p, reply),
            "recorder.stop": (p, reply) => {
                Quickshell.execDetached(["omarchy-capture-screenrecording", "--stop-recording"]);
                reply({}, null);
            },

            // ---- screenshots: grim + imagemagick ------------------------
            "screenshot.dir": (p, reply) => reply({
                    dir: root.screenshotDir
                }, null),
            "screenshot.frame": (p, reply) => root.captureFrame(String(p.output || ""), reply),
            "screenshot.release": (p, reply) => root.run(["rm", "-rf", root.framesDir], () => reply({}, null)),
            "screenshot.capture": (p, reply) => root.capture(p, reply),
            "ocr.text": (p, reply) => root.recognise("text", p, reply),
            "ocr.barcode": (p, reply) => root.recognise("barcode", p, reply),

            // ---- network: NetworkManager --------------------------------
            "network.status": (p, reply) => root.runJson([root.script("net.sh"), "status"], reply),
            "network.networks": (p, reply) => root.runJson([root.script("net.sh"), "networks"], reply),
            "network.enable": (p, reply) => root.runJson([root.script("net.sh"), "enable", p.enabled === false ? "off" : "on"], reply),
            "network.connect": (p, reply) => root.runJson([root.script("net.sh"), "connect", String(p.ssid || ""), String(p.password || "")], (result, error) => {
                if (result && !result.ok && !result.need_password)
                    reply(null, result.error || "connection failed");
                else
                    reply(result, error);
            }),
            "network.disconnect": (p, reply) => root.runJson([root.script("net.sh"), "disconnect", String(p.ssid || "")], reply),

            // ---- weather: open-meteo ------------------------------------
            "weather.get": (p, reply) => root.runJson([root.script("weather.sh"), String(p.location || "")], (result, error) => {
                if (result && result.error)
                    reply(null, result.error);
                else
                    reply(result, error);
            }),

            // ---- system monitor ------------------------------------------
            "systemmonitor.configure": (p, reply) => {
                root.sysmonInterval = Math.max(100, p.interval_ms || 2000);
                root.sysmonDisks = (p.disks && p.disks.length) ? p.disks : ["/"];
                root.restartSysmon();
                reply({}, null);
            },

            // ---- persisted state -------------------------------------------
            "config.statesGet": (p, reply) => reply(root.readJson(statesFile, {}), null),
            "config.statesSet": (p, reply) => {
                const merged = Object.assign(root.readJson(statesFile, {}), p.data || {});
                statesFile.setText(JSON.stringify(merged, null, 2));
                reply({}, null);
            },
            "config.stateSet": (p, reply) => {
                const merged = root.readJson(statesFile, {});
                merged[p.key] = p.value;
                statesFile.setText(JSON.stringify(merged, null, 2));
                reply({}, null);
            },

            // ---- API keys for the assistant (0600 file) ----------------------
            "keystore.list": (p, reply) => {
                const keys = root.readJson(keystoreFile, {});
                reply(Object.keys(keys).map(provider => Object.assign({
                            provider: provider
                        }, keys[provider])), null);
            },
            "keystore.set": (p, reply) => {
                const keys = root.readJson(keystoreFile, {});
                keys[p.provider] = {
                    api_key: p.api_key || "",
                    endpoint: p.endpoint || "",
                    custom_curl: p.custom_curl || ""
                };
                root.writeKeystore(keys, reply);
            },
            "keystore.delete": (p, reply) => {
                const keys = root.readJson(keystoreFile, {});
                delete keys[p.provider];
                root.writeKeystore(keys, reply);
            },

            // ---- notifications -----------------------------------------------
            "notify.cacheImage": (p, reply) => root.cacheImage(String(p.url || ""), reply),

            // ---- clipboard: Omarchy's clipboard history ----------------------
            "clipboard.list": (p, reply) => reply(root.clipboardItems(), null),
            "clipboard.getContent": (p, reply) => {
                const e = root.clipEntry(p.id);
                reply(e ? {
                    content: e.type === "image" ? e.path : e.text
                } : null, e ? null : "no such item");
            },
            "clipboard.copy": (p, reply) => root.clipCopy(p.id, reply),
            "clipboard.delete": (p, reply) => root.clipDelete(p.id, reply),
            "clipboard.clear": (p, reply) => root.clipClear(reply),
            "clipboard.togglePin": (p, reply) => root.clipMeta(p.id, (meta, key) => {
                if (meta.pins[key])
                    delete meta.pins[key];
                else
                    meta.pins[key] = true;
            }, reply),
            "clipboard.setAlias": (p, reply) => root.clipMeta(p.id, (meta, key) => {
                if (p.alias)
                    meta.aliases[key] = String(p.alias);
                else
                    delete meta.aliases[key];
            }, reply),
            "clipboard.reorder": (p, reply) => root.clipReorder(p.id, p.new_index, reply),
            "clipboard.swap": (p, reply) => root.clipSwap(p.id1, p.id2, reply),
            "clipboard.dataUrl": (p, reply) => {
                const e = root.clipEntry(p.id);
                reply(e && e.type === "image" ? {
                    data_url: "file://" + e.path
                } : null, e ? null : "no such item");
            },
            "clipboard.imagePath": (p, reply) => {
                const e = root.clipEntry(p.id);
                reply(e && e.type === "image" ? {
                    path: e.path
                } : null, e ? null : "no such item");
            },
            // wl-copy leaves a child holding the clipboard (and any pipe it
            // was given), so these launch detached and answer at once.
            "clipboard.copyText": (p, reply) => {
                Quickshell.execDetached(["wl-copy", "--", String(p.text || "")]);
                reply({
                    ok: true
                }, null);
            },
            "clipboard.copyFile": (p, reply) => {
                Quickshell.execDetached(["bash", "-c", 'wl-copy --type "$2" < "$1"', "ambxst", String(p.path || ""), String(p.mime || "application/octet-stream")]);
                reply({
                    ok: true
                }, null);
            },
            "clipboard.emojiType": (p, reply) => {
                Quickshell.execDetached(["omarchy-clipboard-paste-text", String(p.emoji || "")]);
                reply({
                    ok: true
                }, null);
            },
            "clipboard.liveMimes": (p, reply) => root.run(["wl-paste", "--list-types"], (code, out) => reply({
                        mimes: out.split("\n").filter(s => s !== "")
                    }, null)),
            "clipboard.liveContent": (p, reply) => root.sh('wl-paste --no-newline --type "$1" | base64 -w0', [String(p.mime || "text/plain")], (code, out) => reply({
                        mime: p.mime,
                        content_base64: out.trim()
                    }, null)),
            "clipboard.setTmpMode": (p, reply) => reply({}, null),

            // ---- link previews (clipboard) -----------------------------------
            "linkpreview.fetch": (p, reply) => root.linkPreview(String(p.url || ""), p.timeout || 5, reply),

            // ---- sleep hooks: Omarchy's idle/sleep owns these ---------------
            "sleep.setCommands": (p, reply) => reply({}, null)
        })

    // =================================================================
    // Compositor helpers
    // =================================================================

    readonly property var omarchyLayouts: ["dwindle", "scrolling", "floating"]

    function compositorDispatch(args, reply) {
        const ok = stdout => reply({
                exit_code: 0,
                stdout: stdout
            }, null);
        if (args[0] === "system" && args[1] === "get-compositor") {
            ok("hyprland");
        } else if (args[0] === "layout" && args[1] === "list") {
            root.run(["omarchy-hyprland-workspace-layout-current"], (code, out) => {
                const active = out.trim() || "dwindle";
                ok(JSON.stringify({
                    compositor: "hyprland",
                    active: active,
                    items: root.omarchyLayouts.map(name => ({
                                name: name,
                                current: name === active
                            }))
                }));
            });
        } else if (args[0] === "layout" && args[1] === "set") {
            // Omarchy cycles a workspace's layout (and saves it) with its
            // own toggle; step it until it lands on the one asked for.
            root.sh('for _ in 1 2 3; do [[ $(omarchy-hyprland-workspace-layout-current) == "$1" ]] && exit 0; omarchy-hyprland-workspace-layout-toggle >/dev/null 2>&1; done', [String(args[2] || "")], code => reply({
                        exit_code: code
                    }, null));
        } else if (args[0] === "system" && args[1] === "execute") {
            AxctlService.dispatch(args.slice(2).join(" "));
            ok("");
        } else {
            reply({
                exit_code: 1,
                error: "unsupported"
            }, null);
        }
    }

    // =================================================================
    // Caffeine (stay awake)
    // =================================================================

    property bool stayAwake: false
    function probeStayAwake() {
        root.run(["test", "-f", OmarchyBridge.omarchyStateDir + "/indicators/stay-awake"], code => {
            const next = code === 0;
            if (next !== root.stayAwake) {
                root.stayAwake = next;
                root.publish("caffeine.state", {
                    inhibit: next
                });
            }
        });
    }
    FileView {
        path: OmarchyBridge.omarchyStateDir + "/indicators"
        watchChanges: true
        printErrors: false
        onFileChanged: root.probeStayAwake()
    }

    // =================================================================
    // Game mode
    // =================================================================

    property bool gameMode: false
    function setGameMode(on) {
        if (on === root.gameMode)
            return;
        root.gameMode = on;
        Quickshell.execDetached(on ? ["touch", OmarchyBridge.stateDir + "/gamemode"] : ["rm", "-f", OmarchyBridge.stateDir + "/gamemode"]);
        // With Ambxst managing Hyprland, CompositorConfig applies (and
        // undoes) the overrides itself when it sees the state change.
        if (!OmarchyBridge.manageHyprland) {
            if (on)
                Quickshell.execDetached(["hyprctl", "eval", "hl.config({ animations = { enabled = false }, decoration = { shadow = { enabled = false }, blur = { enabled = false }, rounding = 0 }, general = { gaps_in = 0, gaps_out = 0 } })"]);
            else
                Quickshell.execDetached(["hyprctl", "reload"]);
        }
        root.publish("gamemode.state", {
            enabled: on
        });
    }

    // =================================================================
    // Night light
    // =================================================================

    property bool nightActive: false
    property int nightTemp: 4000
    function probeNightLight(done) {
        root.run(["omarchy-toggle-nightlight", "--status"], (code, out) => {
            try {
                const s = JSON.parse(out);
                root.nightActive = s.enabled === true;
                if (s.enabled && s.temperature)
                    root.nightTemp = s.temperature;
            } catch (e) {}
            const state = {
                active: root.nightActive,
                temp: root.nightTemp
            };
            root.publish("nightlight.state", state);
            if (done)
                done(state);
        });
    }
    function setNightLight(p, reply) {
        if (p.temp !== undefined && p.temp > 0) {
            root.nightTemp = p.temp;
            if (root.nightActive) {
                root.run(["hyprctl", "hyprsunset", "temperature", String(p.temp)], () => root.probeNightLight(s => reply(s, null)));
                return;
            }
            const state = {
                active: root.nightActive,
                temp: root.nightTemp
            };
            root.publish("nightlight.state", state);
            reply(state, null);
            return;
        }
        if (p.enabled !== undefined && (p.enabled === true) !== root.nightActive) {
            root.run(["bash", "-c", "omarchy-toggle-nightlight >/dev/null 2>&1"], () => root.probeNightLight(s => reply(s, null)));
            return;
        }
        root.probeNightLight(s => reply(s, null));
    }

    // =================================================================
    // Power profiles
    // =================================================================

    function profileName(value) {
        if (value === PowerProfile.PowerSaver)
            return "power-saver";
        if (value === PowerProfile.Performance)
            return "performance";
        return "balanced";
    }
    function powerState() {
        return {
            available: true,
            backend: "power-profiles-daemon",
            profile: root.profileName(PowerProfiles.profile),
            profiles: PowerProfiles.hasPerformanceProfile ? ["power-saver", "balanced", "performance"] : ["power-saver", "balanced"]
        };
    }
    Connections {
        target: PowerProfiles
        function onProfileChanged() {
            root.publish("powerprofile.state", root.powerState());
        }
    }

    // =================================================================
    // Screen recording
    // =================================================================

    // omarchy-capture-screenrecording writes this marker for as long as a
    // recording runs (its content is the file being written).
    readonly property string recordMarker: OmarchyBridge.runtimeDir + "/omarchy-screenrecord-filename"
    property bool recording: false
    property string recordingPath: ""
    property double recordingSince: 0

    function recorderState() {
        return {
            recording: root.recording,
            path: root.recordingPath,
            elapsedMs: root.recording ? Date.now() - root.recordingSince : 0,
            // Omarchy announces the saved file itself.
            lastPath: ""
        };
    }
    function setRecording(on, path) {
        if (on === root.recording && path === root.recordingPath)
            return;
        if (on && !root.recording)
            root.recordingSince = Date.now();
        root.recording = on;
        root.recordingPath = path || "";
        root.publish("recorder.state", root.recorderState());
    }
    FileView {
        id: recordMarkerFile
        path: root.recordMarker
        watchChanges: true
        printErrors: false
        onLoaded: root.setRecording(true, text().trim())
        onLoadFailed: root.setRecording(false, "")
        onFileChanged: reload()
    }
    // A FileView can't see a file appear, so after a start look for the
    // marker until it shows up (or the start gave up).
    Timer {
        id: markerWait
        interval: 500
        repeat: true
        property int ticks: 0
        onTriggered: {
            if (root.recording || ++ticks > 240) {
                stop();
                return;
            }
            recordMarkerFile.reload();
        }
    }
    function startRecording(p, reply) {
        const args = ["omarchy-capture-screenrecording"];
        if (p.mode === "screen")
            args.push("--fullscreen");
        if (p.audioOut)
            args.push("--with-desktop-audio");
        if (p.audioIn)
            args.push("--with-microphone-audio");
        const env = p.mode === "portal" || p.mode === "window" ? ["env", "OMARCHY_SCREENRECORD_USE_PORTAL=true"] : [];
        Quickshell.execDetached(env.concat(args));
        markerWait.ticks = 0;
        markerWait.start();
        reply({
            path: ""
        }, null);
    }

    // =================================================================
    // Screenshots, OCR, QR
    // =================================================================

    readonly property string framesDir: OmarchyBridge.runtimeDir + "/ambxst-frames"
    property string screenshotDir: home + "/Pictures/Screenshots"
    Process {
        running: true
        command: ["bash", "-c", '[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs; echo "${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots}"']
        stdout: StdioCollector {
            onStreamFinished: if (text.trim())
                root.screenshotDir = text.trim()
        }
    }

    function framePath(output) {
        return root.framesDir + "/" + output.replace(/[^A-Za-z0-9_.-]/g, "_") + ".png";
    }

    function captureFrame(output, reply) {
        const path = root.framePath(output);
        root.sh('mkdir -p "$(dirname "$2")" && grim -o "$1" "$2"', [output, path], (code, out, err) => reply(code === 0 ? {
                path: path
            } : null, code === 0 ? null : (err.trim() || "grim failed")));
    }

    function monitorAt(x, y, name) {
        const mons = AxctlService.monitors.values || [];
        if (name) {
            const m = mons.find(mon => mon.name === name);
            if (m)
                return m;
        }
        return mons.find(m => x >= m.x && y >= m.y && x < m.x + m.width / m.scale && y < m.y + m.height / m.scale) || AxctlService.focusedMonitor;
    }

    // Crops a region (logical, global) out of the frozen frame of its
    // output, so the shot is what was on screen when the tool opened --
    // not the selection overlay. Falls back to a live grim of the region.
    function cropRegion(p, dest, done) {
        const mon = root.monitorAt(p.x, p.y, p.output);
        const scale = mon ? mon.scale : 1;
        const px = Math.round((p.x - (mon ? mon.x : 0)) * scale);
        const py = Math.round((p.y - (mon ? mon.y : 0)) * scale);
        const pw = Math.max(1, Math.round(p.width * scale));
        const ph = Math.max(1, Math.round(p.height * scale));
        const frame = mon ? root.framePath(mon.name) : "";
        root.sh('mkdir -p "$(dirname "$2")"; ' + 'if [[ -f $1 ]]; then magick "$1" -crop "$3" +repage "$2"; else grim -g "$4" "$2"; fi', [frame, dest, pw + "x" + ph + "+" + px + "+" + py, p.x + "," + p.y + " " + p.width + "x" + p.height], done);
    }

    function timestamp() {
        return Qt.formatDateTime(new Date(), "yyyy-MM-dd-hh-mm-ss");
    }

    function capture(p, reply) {
        const dest = p.outPath || (root.screenshotDir + "/" + (p.filename || ("Screenshot_" + root.timestamp() + ".png")));
        const finish = (code, out, err) => {
            if (code !== 0) {
                reply(null, err.trim() || "capture failed");
                return;
            }
            if (p.clipboard)
                Quickshell.execDetached(["bash", "-c", 'wl-copy --type image/png < "$1"', "ambxst", dest]);
            reply({
                path: dest
            }, null);
        };
        if (p.mode === "region") {
            root.cropRegion(p, dest, finish);
            return;
        }
        let name = p.output || "";
        if (!name && AxctlService.focusedMonitor)
            name = AxctlService.focusedMonitor.name;
        root.sh('mkdir -p "$(dirname "$3")"; if [[ -f $1 ]]; then cp "$1" "$3"; else grim -o "$2" "$3"; fi', [root.framePath(name), name, dest], finish);
    }

    function recognise(kind, p, reply) {
        const tmp = root.framesDir + "/recognise-" + Date.now() + ".png";
        root.cropRegion(p, tmp, code => {
            if (code !== 0) {
                reply(null, "capture failed");
                return;
            }
            const script = kind === "barcode" ? 'out=$(zbarimg -q --raw "$1" 2>/dev/null); rm -f "$1"; [[ -n $out ]] && printf %s "$out" | wl-copy >/dev/null 2>&1; printf %s "$out"' : 'out=$(tesseract "$1" - -l "$2" 2>/dev/null); rm -f "$1"; [[ -n ${out//[[:space:]]/} ]] && printf %s "$out" | wl-copy >/dev/null 2>&1; printf %s "$out"';
            root.sh(script, [tmp, p.langs || "eng"], (c, out) => reply(kind === "barcode" ? {
                    content: out.trim()
                } : {
                    text: out.trim()
                }, null));
        });
    }

    // =================================================================
    // System monitor (only while someone listens: the Metrics tab)
    // =================================================================

    property int sysmonInterval: 2000
    property var sysmonDisks: ["/"]
    readonly property bool sysmonWanted: root.wants("systemmonitor")

    function restartSysmon() {
        sysmon.running = false;
        if (root.sysmonWanted)
            Qt.callLater(() => sysmon.running = root.sysmonWanted);
    }
    onSysmonWantedChanged: root.restartSysmon()

    Process {
        id: sysmon
        command: [root.script("sysmon.sh"), String(root.sysmonInterval), root.sysmonDisks.join(",")]
        stdout: SplitParser {
            onRead: line => {
                const kind = line.substring(0, 2);
                try {
                    const data = JSON.parse(line.substring(2));
                    root.publish(kind === "S " ? "systemmonitor.static" : "systemmonitor", data);
                } catch (e) {}
            }
        }
    }

    // =================================================================
    // Network state stream (NetworkManager's own monitor)
    // =================================================================

    readonly property bool networkWanted: root.wants("network")
    Process {
        running: root.networkWanted
        command: [root.script("net.sh"), "monitor"]
        stdout: SplitParser {
            onRead: networkDebounce.restart()
        }
    }
    Timer {
        id: networkDebounce
        interval: 400
        onTriggered: root.runJson([root.script("net.sh"), "status"], (state, error) => {
            if (state)
                root.publish("network.state", state);
        })
    }

    // =================================================================
    // Sleep: logind's PrepareForSleep, for SuspendManager
    // =================================================================

    Process {
        running: true
        command: ["gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"]
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("PrepareForSleep") < 0)
                    return;
                if (line.indexOf("(true,)") >= 0)
                    SuspendManager.onPrepareForSleep();
                else if (line.indexOf("(false,)") >= 0)
                    SuspendManager.onWakingUp();
            }
        }
    }

    // =================================================================
    // Files: persisted state, keystore
    // =================================================================

    function readJson(view, fallback) {
        try {
            const t = view.text();
            const v = t ? JSON.parse(t) : null;
            return v && typeof v === "object" ? v : fallback;
        } catch (e) {
            return fallback;
        }
    }

    FileView {
        id: statesFile
        path: OmarchyBridge.stateDir + "/states.json"
        blockLoading: true
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: keystoreFile
        path: OmarchyBridge.dataDir + "/keystore.json"
        blockLoading: true
        atomicWrites: true
        printErrors: false
    }
    function writeKeystore(keys, reply) {
        keystoreFile.setText(JSON.stringify(keys, null, 2));
        root.run(["chmod", "600", keystoreFile.path], () => reply({}, null));
    }

    // =================================================================
    // Notification images
    // =================================================================

    function cacheImage(url, reply) {
        if (!url) {
            reply(null, "no url");
            return;
        }
        const dir = OmarchyBridge.cacheDir + "/notification-images";
        root.sh('src=$1; dir=$2; mkdir -p "$dir"; ' + 'name=$(printf %s "$src" | sha1sum | cut -c1-16); ext=${src##*.}; [[ $ext =~ ^[A-Za-z0-9]{1,5}$ ]] || ext=png; ' + 'dest="$dir/$name.$ext"; [[ -s $dest ]] && { echo "$dest"; exit 0; }; ' + 'case $src in http://*|https://*) curl -fsL --max-time 10 -o "$dest" "$src" ;; ' + 'file://*) src=${src#file://}; cp -- "$src" "$dest" ;; image://*) exit 1 ;; *) cp -- "$src" "$dest" ;; esac && echo "$dest"', [url, dir], (code, out) => {
            const path = out.trim();
            reply(code === 0 && path ? {
                path: path
            } : null, code === 0 ? null : "cache failed");
        });
    }

    // =================================================================
    // Link previews
    // =================================================================

    function linkPreview(url, timeout, reply) {
        if (!/^https?:\/\//.test(url)) {
            reply({
                error: "not a web link",
                url: url,
                request_url: url
            }, null);
            return;
        }
        root.run(["curl", "-fsL", "--max-time", String(timeout), "--max-filesize", "2000000", "-A", "Mozilla/5.0 (Ambxst link preview)", url], (code, html) => {
            if (code !== 0 || !html) {
                reply({
                    error: "fetch failed",
                    url: url,
                    request_url: url
                }, null);
                return;
            }
            const head = html.substring(0, 300000);
            const meta = key => {
                const re = new RegExp('<meta[^>]+(?:property|name)=["\']' + key + '["\'][^>]*content=["\']([^"\']*)["\']', "i");
                const re2 = new RegExp('<meta[^>]+content=["\']([^"\']*)["\'][^>]*(?:property|name)=["\']' + key + '["\']', "i");
                const m = head.match(re) || head.match(re2);
                return m ? root.decodeEntities(m[1]) : "";
            };
            const titleTag = head.match(/<title[^>]*>([^<]*)<\/title>/i);
            const icon = head.match(/<link[^>]+rel=["'][^"']*icon[^"']*["'][^>]*href=["']([^"']+)["']/i);
            const absolute = href => {
                if (!href)
                    return "";
                if (/^https?:\/\//.test(href))
                    return href;
                const origin = url.match(/^https?:\/\/[^\/]+/)[0];
                return href.startsWith("//") ? url.split(":")[0] + ":" + href : origin + (href.startsWith("/") ? "" : "/") + href;
            };
            const yt = url.match(/(?:youtube\.com\/watch\?v=|youtu\.be\/)([A-Za-z0-9_-]{6,})/);
            reply({
                title: meta("og:title") || (titleTag ? root.decodeEntities(titleTag[1].trim()) : ""),
                description: meta("og:description") || meta("description"),
                image: absolute(meta("og:image")),
                url: meta("og:url") || url,
                request_url: url,
                site_name: meta("og:site_name"),
                type: meta("og:type"),
                favicon: absolute(icon ? icon[1] : "/favicon.ico"),
                video_id: yt ? yt[1] : ""
            }, null);
        });
    }

    function decodeEntities(s) {
        return String(s).replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;|&#x27;/g, "'");
    }

    // =================================================================
    // Clipboard: Omarchy's history + Ambxst's pins, aliases and order
    // =================================================================

    // Omarchy's clipboard plugin records the clipboard here; Ambxst reads
    // it and never runs a second watcher.
    property var clipHistory: []
    property var clipMetaData: ({
            pins: {},
            aliases: {},
            order: []
        })

    FileView {
        id: clipHistoryFile
        path: OmarchyBridge.omarchyStateDir + "/clipboard-history.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const parsed = JSON.parse(text() || "[]");
                root.clipHistory = Array.isArray(parsed) ? parsed.filter(e => e && (e.type === "image" ? e.path : (typeof e === "string" || e.text))).map(e => typeof e === "string" ? {
                            type: "text",
                            text: e
                        } : e) : [];
            } catch (e) {
                root.clipHistory = [];
            }
            root.publish("clipboard.refresh", {});
        }
    }

    FileView {
        id: clipMetaFile
        path: OmarchyBridge.dataDir + "/clipboard-meta.json"
        blockLoading: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            const m = root.readJson(clipMetaFile, {});
            root.clipMetaData = {
                pins: m.pins || {},
                aliases: m.aliases || {},
                order: Array.isArray(m.order) ? m.order : []
            };
        }
    }

    function clipKey(e) {
        return e.type === "image" ? "image:" + e.path : "text:" + e.text;
    }

    // FNV-1a: a stable numeric id per entry.
    function clipId(key) {
        let h = 0x811c9dc5;
        for (let i = 0; i < key.length; i++) {
            h ^= key.charCodeAt(i);
            h = Math.imul(h, 0x01000193) >>> 0;
        }
        return h & 0x7fffffff;
    }

    function clipOrderedKeys() {
        const keys = root.clipHistory.map(root.clipKey);
        const known = root.clipMetaData.order.filter(k => keys.indexOf(k) >= 0);
        const fresh = keys.filter(k => known.indexOf(k) < 0);
        const all = fresh.concat(known);
        const pins = root.clipMetaData.pins;
        return all.filter(k => pins[k]).concat(all.filter(k => !pins[k]));
    }

    function clipItems() {
        const byKey = {};
        root.clipHistory.forEach(e => byKey[root.clipKey(e)] = e);
        return root.clipOrderedKeys().map((key, index) => {
            const e = byKey[key];
            const isImage = e.type === "image";
            const text = isImage ? e.path : String(e.text || "");
            const isUriList = !isImage && /^file:\/\//m.test(text) && text.split(/\r?\n/).every(l => l === "" || l.startsWith("file://"));
            return {
                id: root.clipId(key),
                preview: text,
                mime_type: isImage ? (e.mime || "image/png") : (isUriList ? "text/uri-list" : "text/plain"),
                is_image: isImage ? 1 : 0,
                content_hash: String(root.clipId(key)),
                size: isImage ? 0 : text.length,
                created_at: e.capturedAt ? Date.parse(e.capturedAt) / 1000 || 0 : 0,
                pinned: root.clipMetaData.pins[key] ? 1 : 0,
                alias: root.clipMetaData.aliases[key] || "",
                display_index: index
            };
        });
    }

    function clipFind(id) {
        const target = Number(id);
        for (let i = 0; i < root.clipHistory.length; i++) {
            const key = root.clipKey(root.clipHistory[i]);
            if (root.clipId(key) === target)
                return {
                    entry: root.clipHistory[i],
                    index: i,
                    key: key
                };
        }
        return null;
    }

    function clipEntry(id) {
        const f = root.clipFind(id);
        return f ? f.entry : null;
    }

    function saveClipMeta() {
        clipMetaFile.setText(JSON.stringify(root.clipMetaData, null, 2));
        root.publish("clipboard.refresh", {});
    }

    function clipMeta(id, mutate, reply) {
        const f = root.clipFind(id);
        if (!f) {
            reply(null, "no such item");
            return;
        }
        const meta = root.clipMetaData;
        mutate(meta, f.key);
        root.clipMetaData = meta;
        root.saveClipMeta();
        reply({}, null);
    }

    function clipReorder(id, newIndex, reply) {
        const f = root.clipFind(id);
        if (!f) {
            reply(null, "no such item");
            return;
        }
        const keys = root.clipOrderedKeys().filter(k => k !== f.key);
        keys.splice(Math.max(0, Math.min(keys.length, Number(newIndex) || 0)), 0, f.key);
        root.clipMetaData.order = keys;
        root.saveClipMeta();
        reply({}, null);
    }

    function clipSwap(id1, id2, reply) {
        const a = root.clipFind(id1), b = root.clipFind(id2);
        if (!a || !b) {
            reply(null, "no such item");
            return;
        }
        const keys = root.clipOrderedKeys();
        const i = keys.indexOf(a.key), j = keys.indexOf(b.key);
        keys[i] = b.key;
        keys[j] = a.key;
        root.clipMetaData.order = keys;
        root.saveClipMeta();
        reply({}, null);
    }

    function clipCopy(id, reply) {
        const f = root.clipFind(id);
        if (!f) {
            reply(null, "no such item");
            return;
        }
        const argv = f.entry.type === "image" ? ["omarchy-clipboard-paste-file", "--copy-only", f.entry.mime || "image/png", f.entry.path] : ["omarchy-clipboard-paste-text", "--copy-only", "--history-index", String(f.index)];
        // Detached: the copy leaves wl-copy running with the clipboard.
        Quickshell.execDetached(argv);
        reply({}, null);
    }

    // Delete and clear rewrite the history the way Omarchy's own clipboard
    // panel does; its plugin reloads the file.
    function writeHistory(next) {
        clipHistoryFile.setText(JSON.stringify(next, null, 2) + "\n");
    }

    function clipDelete(id, reply) {
        const f = root.clipFind(id);
        if (!f) {
            reply(null, "no such item");
            return;
        }
        const next = root.clipHistory.slice();
        next.splice(f.index, 1);
        delete root.clipMetaData.pins[f.key];
        delete root.clipMetaData.aliases[f.key];
        root.clipMetaData.order = root.clipMetaData.order.filter(k => k !== f.key);
        root.writeHistory(next);
        root.saveClipMeta();
        reply({}, null);
    }

    function clipClear(reply) {
        // Pinned entries survive a clear, as in Ambxst.
        const pins = root.clipMetaData.pins;
        const kept = root.clipHistory.filter(e => pins[root.clipKey(e)]);
        root.clipMetaData.order = root.clipMetaData.order.filter(k => pins[k]);
        root.writeHistory(kept);
        root.saveClipMeta();
        reply({}, null);
    }

    Component.onCompleted: {
        root.probeStayAwake();
        root.probeNightLight();
        if (!OmarchyBridge.manageHyprland)
            root.run(["test", "-f", OmarchyBridge.stateDir + "/gamemode"], code => {
                if (code === 0)
                    root.gameMode = true;
            });
    }
}
