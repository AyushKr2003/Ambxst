.pragma library

// Ambxst on Omarchy: turns an Omarchy theme (colors.toml) into the colour
// roles Ambxst reads from ~/.cache/ambxst/colors.json (the file matugen
// writes upstream), so every Ambxst surface is drawn in the Omarchy theme.
//
// Base roles come straight from the theme (background, foreground, accent,
// the six hues and their bright variants); the Material-style tonal roles
// (containers, "over" colours, surface steps, fixed tones) are mixed from
// them, light or dark as the theme's `mode` says.

function parseToml(text) {
    var out = {};
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var m = lines[i].match(/^\s*([A-Za-z0-9_.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s#]+))/);
        if (m)
            out[m[1]] = (m[2] !== undefined ? m[2] : m[3] !== undefined ? m[3] : m[4]).trim();
    }
    return out;
}

function rgb(hex) {
    var h = String(hex || "").replace("#", "").trim();
    if (h.length === 3)
        h = h[0] + h[0] + h[1] + h[1] + h[2] + h[2];
    if (h.length === 8)
        h = h.substring(0, 6);
    var n = parseInt(h, 16);
    if (h.length !== 6 || isNaN(n))
        return null;
    return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 };
}

function hex(c) {
    function p(v) {
        var s = Math.max(0, Math.min(255, Math.round(v))).toString(16);
        return s.length === 1 ? "0" + s : s;
    }
    return "#" + p(c.r) + p(c.g) + p(c.b);
}

function mix(a, b, t) {
    var x = rgb(a), y = rgb(b);
    if (!x)
        return b;
    if (!y)
        return a;
    return hex({ r: x.r + (y.r - x.r) * t, g: x.g + (y.g - x.g) * t, b: x.b + (y.b - x.b) * t });
}

function luminance(c) {
    var x = rgb(c);
    if (!x)
        return 0;
    function ch(v) {
        v /= 255;
        return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    }
    return 0.2126 * ch(x.r) + 0.7152 * ch(x.g) + 0.0722 * ch(x.b);
}

// Text drawn on a colour: a deep tone of it on light colours, a pale tone
// on dark ones (M3's "on" roles).
function over(c) {
    return luminance(c) > 0.35 ? mix(c, "#000000", 0.78) : mix(c, "#ffffff", 0.88);
}

function build(theme) {
    var t = theme || {};
    function pick() {
        for (var i = 0; i < arguments.length; i++) {
            var v = t[arguments[i]];
            if (v && rgb(v))
                return hex(rgb(v));
        }
        return null;
    }

    var bg = pick("background", "color0") || "#1a1b26";
    var fg = pick("foreground", "color15", "color7") || "#c0caf5";
    var dark = t.mode ? t.mode !== "light" : luminance(bg) < 0.4;
    var accent = pick("accent", "color4", "blue") || fg;

    var hues = {
        red: pick("red", "color1") || "#e06c75",
        green: pick("green", "color2") || "#98c379",
        yellow: pick("yellow", "color3") || "#e5c07b",
        blue: pick("blue", "color4") || accent,
        magenta: pick("magenta", "color5") || "#c678dd",
        cyan: pick("cyan", "color6") || "#56b6c2",
        white: pick("bright_foreground", "light_foreground", "color7") || fg
    };
    var bright = {
        red: pick("bright_red", "color9") || hues.red,
        green: pick("bright_green", "color10") || hues.green,
        yellow: pick("bright_yellow", "color11") || hues.yellow,
        blue: pick("bright_blue", "color12") || hues.blue,
        magenta: pick("bright_magenta", "color13") || hues.magenta,
        cyan: pick("bright_cyan", "color14") || hues.cyan
    };

    function container(c) {
        return mix(c, bg, dark ? 0.68 : 0.72);
    }
    function overContainer(c) {
        return dark ? mix(c, "#ffffff", 0.62) : mix(c, "#000000", 0.62);
    }

    // Secondary follows the accent toward the text colour; tertiary is the
    // hue furthest from the accent among magenta and cyan.
    var secondary = mix(accent, pick("muted") || fg, 0.45);
    var tertiary = Math.abs(luminance(bright.magenta) - luminance(accent)) > Math.abs(luminance(bright.cyan) - luminance(accent)) ? bright.magenta : bright.cyan;

    var toward = dark ? "#ffffff" : "#000000";
    var away = dark ? "#000000" : "#ffffff";

    var c = {
        sourceColor: accent,
        background: bg,
        overBackground: fg,

        surface: bg,
        surfaceDim: pick(dark ? "darker_background" : "dark_background") || mix(bg, away, 0.25),
        surfaceBright: mix(bg, fg, 0.2),
        surfaceContainerLowest: pick(dark ? "darker_background" : "lighter_background") || mix(bg, away, 0.35),
        surfaceContainerLow: pick(dark ? "dark_background" : "lighter_background") || mix(bg, fg, 0.03),
        surfaceContainer: mix(bg, fg, 0.06),
        surfaceContainerHigh: pick(dark ? "lighter_background" : "dark_background") || mix(bg, fg, 0.1),
        surfaceContainerHighest: mix(bg, fg, 0.15),
        surfaceVariant: mix(bg, fg, 0.18),
        surfaceTint: accent,
        overSurface: fg,
        overSurfaceVariant: mix(fg, bg, 0.22),
        outline: mix(fg, bg, 0.5),
        outlineVariant: mix(fg, bg, 0.75),
        inverseSurface: fg,
        inverseOnSurface: bg,
        inversePrimary: mix(accent, away, 0.4),
        scrim: "#000000",
        shadow: "#000000",

        error: hues.red,
        errorContainer: container(hues.red),
        overError: over(hues.red),
        overErrorContainer: overContainer(hues.red)
    };

    var roles = { primary: accent, secondary: secondary, tertiary: tertiary };
    for (var name in roles) {
        var v = roles[name];
        var Cap = name.charAt(0).toUpperCase() + name.substring(1);
        c[name] = v;
        c[name + "Container"] = container(v);
        c["over" + Cap] = over(v);
        c["over" + Cap + "Container"] = overContainer(v);
        c[name + "Fixed"] = mix(v, "#ffffff", 0.62);
        c[name + "FixedDim"] = mix(v, "#ffffff", 0.32);
        c["over" + Cap + "Fixed"] = mix(v, "#000000", 0.8);
        c["over" + Cap + "FixedVariant"] = mix(v, "#000000", 0.55);
    }

    for (var hue in hues) {
        var h = hues[hue];
        var HCap = hue.charAt(0).toUpperCase() + hue.substring(1);
        c[hue] = h;
        c[hue + "Source"] = h;
        c[hue + "Value"] = h;
        c[hue + "Container"] = container(h);
        c["over" + HCap] = over(h);
        c["over" + HCap + "Container"] = overContainer(h);
        if (bright[hue])
            c["light" + HCap] = bright[hue];
    }
    // Keep Ambxst's readable-on-everything tones for white in light themes.
    if (!dark)
        c.white = mix(fg, toward, 0.1);

    return c;
}
