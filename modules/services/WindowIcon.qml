pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// The icon for a Hyprland window, found in layers -- ported from the
// omarchy-overview plugin (services/WindowIcon.qml + FallbackIcon.qml) so
// Atoll's workspaces, overview and dock draw the same icon it does:
//
//   1. a TUI app (yazi, nvim, btop, lazygit, ...) named in a terminal's title
//   2. the desktop entry for the class, then the initial class
//   3. a web app's name pulled out of its class
//      (chrome-discord.com__app-Default -> discord)
//   4. the initial title, then the title up to " - "
//   5. those names as themed icons (discord, spotify, ...)
//   6. Atoll's own guesses (AppSearch substitutions)
//   7. the default terminal or browser, for terminals and browsers
//
// A step only counts when its icon actually draws; otherwise the next runs.
// Bindings that call iconNameFor() also read DesktopEntries.applications so
// they re-run when the entry index changes.
Singleton {
    id: root

    // ---------------------------------------------------------- fallbacks

    property string defaultBrowserDesktopId: "chromium.desktop"
    property string defaultTerminalDesktopId: "Alacritty.desktop"
    readonly property var fallbackBrowserIds: [defaultBrowserDesktopId, "google-chrome.desktop", "google-chrome-stable.desktop", "brave-browser.desktop", "brave.desktop", "microsoft-edge.desktop", "microsoft-edge-stable.desktop", "opera.desktop", "vivaldi-stable.desktop", "vivaldi.desktop", "helium.desktop", "chromium.desktop", "chromium-browser.desktop"]
    readonly property var fallbackTerminalIds: [defaultTerminalDesktopId, "Alacritty.desktop", "foot.desktop", "footclient.desktop", "com.mitchellh.ghostty.desktop", "kitty.desktop", "org.wezfurlong.wezterm.desktop"]

    function normalizeDesktopId(value) {
        let id = String(value || "").trim().toLowerCase();
        if (id.indexOf("/") >= 0)
            id = id.split("/").pop();
        if (id.slice(-8) === ".desktop")
            id = id.slice(0, -8);
        return id;
    }

    function supportedBrowserDesktopId(value) {
        const id = String(value || "").trim();
        const n = normalizeDesktopId(id);
        if (["google-chrome", "brave", "microsoft-edge", "opera", "vivaldi", "helium", "chromium"].some(p => n.indexOf(p) === 0))
            return id.length > 0 ? id : "chromium.desktop";
        return "chromium.desktop";
    }

    function isBrowserLikeClass(value) {
        const cls = normalizeDesktopId(value);
        if (!cls)
            return false;
        return cls.indexOf("chrom") >= 0 || cls.indexOf("brave") >= 0 || cls.indexOf("vivaldi") >= 0 || cls.indexOf("microsoft-edge") >= 0 || cls.indexOf("opera") >= 0 || cls.indexOf("helium") >= 0 || cls.indexOf("crx_") === 0 || cls.indexOf("webapp") >= 0;
    }

    function isTerminalLikeClass(value) {
        const cls = normalizeDesktopId(value);
        if (!cls)
            return false;
        return cls.indexOf("org.omarchy.") === 0 || ["tui.float", "tui.tile", "kitty", "alacritty", "foot", "footclient", "ghostty", "com.mitchellh.ghostty", "wezterm", "org.wezfurlong.wezterm", "st", "urxvt", "xterm", "rio", "konsole", "gnome-terminal"].indexOf(cls) >= 0;
    }

    function iconForDesktopId(desktopId) {
        const target = normalizeDesktopId(desktopId);
        if (!target)
            return "";
        const entries = DesktopEntries.applications.values || [];
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i];
            if (normalizeDesktopId(entry && entry.id) === target)
                return String((entry && entry.icon) || "").trim();
        }
        const h = DesktopEntries.heuristicLookup(target);
        return String((h && h.icon) || "").trim();
    }

    function firstAvailableIcon(desktopIds) {
        for (let i = 0; i < desktopIds.length; i++) {
            const icon = iconForDesktopId(desktopIds[i]);
            if (icon.length > 0)
                return icon;
        }
        return "";
    }

    function fallbackIconForWindow(w) {
        if (isTerminalLikeClass(w?.class) || isTerminalLikeClass(w?.initialClass)) {
            const t = firstAvailableIcon(fallbackTerminalIds);
            if (t.length > 0)
                return t;
        }
        if (isBrowserLikeClass(w?.class) || isBrowserLikeClass(w?.initialClass))
            return firstAvailableIcon(fallbackBrowserIds);
        return "";
    }

    // ------------------------------------------------------------- lookup

    function extractAppNameFromClass(cls) {
        if (!cls)
            return "";
        let s = String(cls).trim().replace(/^chrome-https?___?/i, "").replace(/^chrome-http?___?/i, "").replace(/^chrome-/, "");
        s = s.replace(/_?_?app-Default$/i, "").replace(/-Default$/i, "");
        if (s.indexOf(".") >= 0) {
            const parts = s.split(".");
            if (parts.length >= 2) {
                const name = parts[parts.length - 2];
                if (["com", "org", "net", "io", "app"].indexOf(name) < 0)
                    return name;
            }
        }
        return s;
    }

    // An icon name or path that will actually draw (not the "missing" one).
    function resolves(icon) {
        const value = `${icon ?? ""}`.trim();
        if (!value || value === "image-missing")
            return false;
        if (value.startsWith("/") || value.startsWith("file://") || value.startsWith("image://"))
            return true;
        return Quickshell.iconPath(value, true).length > 0;
    }

    function hasThemedIcon(name) {
        return Quickshell.iconPath(name, true).length > 0;
    }

    // exact: only an entry whose id or name is the key. Words pulled out of a
    // terminal title ("work", "main") would otherwise land on whatever app
    // the heuristic likes best.
    function lookupEntryIcon(key, entries, exact) {
        if (!key)
            return "";
        if (!exact) {
            const h = DesktopEntries.heuristicLookup(key);
            const icon = String((h && h.icon) || "").trim();
            if (icon.length > 0)
                return icon;
        }
        const normKey = String(key).toLowerCase().replace(/\.desktop$/, "");
        for (let i = 0; i < entries.length; i++) {
            const e = entries[i];
            if (!e)
                continue;
            const eId = String(e.id || "").toLowerCase().replace(/\.desktop$/, "");
            const eName = String(e.name || "").toLowerCase();
            if (eId === normKey || eName === normKey) {
                const eIcon = String(e.icon || "").trim();
                if (eIcon.length > 0)
                    return eIcon;
            }
        }
        return "";
    }

    readonly property var tuiIgnored: ["bash", "zsh", "fish", "sh", "ksh", "csh", "tcsh", "nu", "nushell", "alacritty", "kitty", "foot", "footclient", "ghostty", "com.mitchellh.ghostty", "wezterm", "org.wezfurlong.wezterm", "st", "urxvt", "xterm", "terminal", "tui", "omarchy", "root", "user", "home", "dev", "dotfiles", "tmp", "etc", "usr", "var", "bin", "opt", Quickshell.env("USER") || ""]

    function findTuiAppIcon(title, initialTitle, entries) {
        const candidates = [];
        function addTokens(str) {
            if (!str)
                return;
            const tokens = String(str).trim().split(/[\s:|\-—–/\\()[\]{}]+/);
            for (let i = 0; i < tokens.length; i++) {
                const tok = tokens[i].trim().toLowerCase();
                if (tok.length > 1 && candidates.indexOf(tok) === -1)
                    candidates.push(tok);
            }
        }
        addTokens(initialTitle);
        addTokens(title);
        for (let k = 0; k < candidates.length; k++) {
            const cand = candidates[k];
            if (root.tuiIgnored.indexOf(cand) >= 0)
                continue;
            const icon = lookupEntryIcon(cand, entries, true);
            if (resolves(icon))
                return icon;
            if (hasThemedIcon(cand))
                return cand;
        }
        return "";
    }

    // Icon name (or path) for a window: anything with class, initialClass,
    // title and initialTitle (a `hyprctl clients -j` entry, Atoll's
    // AxctlService clients, or {class: appId} for a dock app).
    function iconNameFor(w) {
        if (!w)
            return "";
        const entries = DesktopEntries.applications.values || [];
        const cls = String(w.class || "").trim();
        const initialClass = String(w.initialClass || "").trim();
        const title = String(w.title || "").trim();
        const initialTitle = String(w.initialTitle || "").trim();
        const usable = value => resolves(value) ? value : "";
        let icon = "";

        if (isTerminalLikeClass(cls) || isTerminalLikeClass(initialClass))
            icon = findTuiAppIcon(title, initialTitle, entries);

        if (!icon)
            icon = usable(lookupEntryIcon(cls, entries));
        if (!icon && initialClass && initialClass !== cls)
            icon = usable(lookupEntryIcon(initialClass, entries));

        const extracted = extractAppNameFromClass(cls);
        if (!icon && extracted && extracted !== cls)
            icon = usable(lookupEntryIcon(extracted, entries));

        if (!icon && initialTitle)
            icon = usable(lookupEntryIcon(initialTitle, entries));
        if (!icon && title) {
            const cleanTitle = title.split(/\s+[-|–—]\s+/)[0].trim();
            if (cleanTitle)
                icon = usable(lookupEntryIcon(cleanTitle, entries));
        }

        if (!icon) {
            const candidates = [extracted, initialTitle, cls, initialClass].filter(n => n && n.length > 0);
            for (let j = 0; j < candidates.length; j++) {
                const cand = candidates[j].toLowerCase();
                if (["google-chrome", "chromium", "brave-browser", "firefox"].indexOf(cand) >= 0)
                    continue;
                if (hasThemedIcon(cand)) {
                    icon = cand;
                    break;
                }
            }
        }

        // Atoll's own substitutions (code-url-handler -> visual-studio-code, ...).
        if (!icon && cls)
            icon = usable(AppSearch.guessIcon(cls));

        if (!icon)
            icon = fallbackIconForWindow(w);

        const raw = `${icon ?? ""}`.trim().replace(/^image:\/\/icon\//, "");
        return raw.split("?")[0].trim();
    }

    // A URL an Image/IconImage can draw for an icon name or path.
    function sourceFor(icon) {
        const value = `${icon ?? ""}`.trim();
        if (value.length === 0)
            return Quickshell.iconPath("application-x-executable", true);
        if (value.startsWith("file://") || value.startsWith("image://") || value.startsWith("qrc:/"))
            return value;
        if (value.startsWith("/"))
            return "file://" + value;
        const themed = Quickshell.iconPath(value, true);
        return themed.length > 0 ? themed : Quickshell.iconPath("application-x-executable", true);
    }

    function iconSourceFor(w) {
        return sourceFor(iconNameFor(w));
    }

    // The window a workspace shows: the focused one when it's there,
    // otherwise the most recently focused (lowest focusHistoryID).
    function representativeWindow(windows) {
        if (!windows || windows.length === 0)
            return null;
        for (let i = 0; i < windows.length; i++)
            if (windows[i] && windows[i].is_focused)
                return windows[i];
        return windows.reduce((best, win) => {
            const b = best && best.focusHistoryID !== undefined ? best.focusHistoryID : Infinity;
            const w = win && win.focusHistoryID !== undefined ? win.focusHistoryID : Infinity;
            return w < b ? win : best;
        }, null);
    }

    // ------------------------------------------------- default apps

    Process {
        command: ["sh", "-lc", "xdg-settings get default-web-browser 2>/dev/null || true"]
        running: true
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.defaultBrowserDesktopId = root.supportedBrowserDesktopId(text)
        }
    }

    Process {
        command: ["sh", "-lc", "xdg-terminal-exec --print-id 2>/dev/null || grep -vE '^($|#)' \"$HOME/.config/xdg-terminals.list\" 2>/dev/null | head -n 1 || true"]
        running: true
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const id = String(text || "").trim();
                if (id.length > 0)
                    root.defaultTerminalDesktopId = id;
            }
        }
    }
}
