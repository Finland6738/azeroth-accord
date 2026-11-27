"""HTML building blocks for tools/make_mockups.py: the design previews of the Azeroth Accord interface in the new look (M6.16).

Pure string helpers: no browser, no file access except reading the locale tables. The look is the one of the widget kit and of
UI/Theme.lua (docs/specs/ui-style.md): the tokens below are the three themes of the addon (Nebula, Aurora, Accord), `css()`
turns them into docs/specs/mockups/html/accord.css (written by `python -X utf8 tools/make_mockups.py --spec`), and the pieces
(`btn`, `chip`, `table`, `card`...) draw what the kit draws under Material 3 (docs/specs/ui-style.md §9): the four kinds of button,
filter chips, segmented buttons, a DataTable with capitals in its header, cards, switches. Every text of the interface is read from AzerothAccord/Locale/enUS.lua (or itIT.lua), so a preview never disagrees
with the addon; only the invented data (guild, characters, items) is written in the scenes.

Adapted from Finland Dragon Credit Points (tools/mockup_lib.py), same owner, GPL-3.0 (ADR 0021): the style sheet and the
components follow FDCP's, so the two addons look the same; the tokens are Accord's (UI/Theme.lua). Each preview draws what the
addon can build in game, not what a browser can do: no backdrop blur, glow only where an additive texture can put it.

Original art only: the class squares, guild emblem, tab icons and item pictures are drawn with CSS and inline SVG; the pictures
are the addon's own logo and the NEBULA logos of assets/. The fonts are the ones the addon ships (Outfit, JetBrains Mono,
Orbitron: SIL OFL 1.1, AzerothAccord/Media/Fonts/); nothing is loaded from the network. No Blizzard art.
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALE_DIR = os.path.join(ROOT, "AzerothAccord", "Locale")
_LINE = re.compile(r'^L\["([A-Z0-9_]+)"\] = "((?:[^"\\]|\\.)*)"\s*$', re.M)
_cache = {}


def _load(lang):
    if lang not in _cache:
        with open(os.path.join(LOCALE_DIR, lang + ".lua"), encoding="utf-8") as f:
            _cache[lang] = {k: v.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\") for k, v in _LINE.findall(f.read())}
    return _cache[lang]


LANG = ["enUS"]


def set_lang(lang):
    LANG[0] = lang


def T(key, *args, lang=None):
    """The interface text of `key` in the current language, formatted like Lua's string.format (the same % codes)."""
    text = _load(lang or LANG[0])[key]
    return text % args if args else text


def esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


# ---- the three themes: the tokens of AzerothAccord/UI/Theme.lua (ui-style.md §4) -----------------------------------------------
THEME_ORDER = ["nebula", "aurora", "accord"]
THEMES = {
    "nebula": {
        "bg": "#0B0612", "surface-1": "#110A1A", "surface-2": "#170F22", "surface-3": "#1E142C", "raised": "#2A1D3B",
        "border-subtle": "rgba(243,238,247,.08)", "border": "rgba(243,238,247,.14)", "border-strong": "rgba(243,238,247,.26)",
        "text-1": "#F3EEF7", "text-2": "#C3B8D1", "text-3": "#9A8FAB", "on-accent": "#1A0710",
        "accent": "#FC7E46", "accent-hover": "#FDA877", "accent-text": "#FC8C46", "accent-2": "#EE4662",
        "neon": "#C45BC4", "neon-core": "#9A2A9A", "ok": "#46C28F", "warn": "#F2B33D", "err": "#FF6369",
        "grad": "#FC8C46, #EE4662 38%, #9A2A9A 72%, #702AA8", "glow": "rgba(154,42,154,.55)", "glow-accent": "rgba(252,126,70,.35)",
        "highlight": "rgba(255,255,255,.06)", "scrim": "rgba(5,2,10,.72)",
        "secondary-container": "#3B2A52", "on-secondary-container": "#EBDDF8", "inverse-surface": "#E9E2F0",
        "inverse-on-surface": "#251B30", "on-error": "#3D0509",
    },
    "aurora": {
        "bg": "#F5F8FA", "surface-1": "#FFFFFF", "surface-2": "#EAF0F4", "surface-3": "#E1E9EF", "raised": "#FFFFFF",
        "border-subtle": "rgba(11,27,43,.07)", "border": "rgba(11,27,43,.13)", "border-strong": "rgba(11,27,43,.24)",
        "text-1": "#0B1B2B", "text-2": "#3C4E60", "text-3": "#526476", "on-accent": "#FFFFFF",
        "accent": "#0054B6", "accent-hover": "#003F8A", "accent-text": "#0054B6", "accent-2": "#00766C",
        "neon": "#008F84", "neon-core": "#009A9A", "ok": "#1B7A50", "warn": "#8F5B00", "err": "#C0262D",
        "grad": "#0054B6, #007EA8 35%, #00A89A 65%, #70C446", "glow": "rgba(0,168,154,.25)", "glow-accent": "rgba(0,84,182,.18)",
        "highlight": "rgba(255,255,255,.6)", "scrim": "rgba(11,27,43,.45)",
        "secondary-container": "#C8DAF0", "on-secondary-container": "#0A2A4F", "inverse-surface": "#24303D",
        "inverse-on-surface": "#EEF3F7", "on-error": "#FFFFFF",
    },
    "accord": {
        "bg": "#04171A", "surface-1": "#0A2327", "surface-2": "#102E31", "surface-3": "#16393B", "raised": "#1D4546",
        "border-subtle": "rgba(232,243,236,.08)", "border": "rgba(232,243,236,.14)", "border-strong": "rgba(232,243,236,.26)",
        "text-1": "#E8F3EC", "text-2": "#BFD6CB", "text-3": "#8FB0A3", "on-accent": "#261C00",
        "accent": "#D9B54E", "accent-hover": "#E8CB72", "accent-text": "#D9B54E", "accent-2": "#4FBF8E",
        "neon": "#7DE8B5", "neon-core": "#3FB07F", "ok": "#5CCB8D", "warn": "#F2B33D", "err": "#FF6B5E",
        "grad": "#D9B54E, #9FE3A8 33%, #4FBF8E 66%, #1F7A64", "glow": "rgba(63,176,127,.45)", "glow-accent": "rgba(217,181,78,.35)",
        "highlight": "rgba(255,255,255,.06)", "scrim": "rgba(1,10,12,.72)",
        "secondary-container": "#3D4426", "on-secondary-container": "#F1E7BE", "inverse-surface": "#DDEBE3",
        "inverse-on-surface": "#10292A", "on-error": "#3D0702",
    },
}
THEME_NAME = {"nebula": "Nebula", "aurora": "Aurora", "accord": "Accord"}
# the part of the stage behind the window (the game world: an original dark drawing; a light one for the light theme, as in FDCP)
STAGE = {
    "nebula": ("#05030A", "radial-gradient(circle at 25% 15%, #1A1030, #05030A 70%)"),
    "aurora": ("#C9D3DB", "radial-gradient(circle at 30% 20%, #DCE6EE, #B9C6D1)"),
    "accord": ("#020C0E", "radial-gradient(circle at 25% 15%, #0B3036, #020C0E 70%)"),
}

FONT_DISPLAY = "'Orbitron', 'Bahnschrift', 'Segoe UI', sans-serif"
FONT_BODY = "'Outfit', 'Segoe UI', system-ui, sans-serif"
FONT_MONO = "'JetBrains Mono', 'Cascadia Mono', 'Consolas', monospace"
FONTS = "../../../../AzerothAccord/Media/Fonts"   # from docs/specs/mockups/html/accord.css to the addon's own font files


def _tokens(theme):
    t = THEMES[theme]
    lines = [f"  --{k}: {v};" for k, v in t.items() if k != "grad"]
    lines.append(f"  --grad: linear-gradient(120deg, {t['grad']});")
    lines.append(f"  --stage: {STAGE[theme][1]}; --stage-bg: {STAGE[theme][0]};")
    return "\n".join(lines)


def css():
    """docs/specs/mockups/html/accord.css: the three themes as tokens and every piece of the kit drawn with them."""
    faces = "".join(
        f"@font-face {{ font-family: '{fam}'; font-weight: {w}; src: url('{FONTS}/{file}') format('truetype'); }}\n"
        for fam, w, file in [("Outfit", 400, "Outfit-Regular.ttf"), ("Outfit", 500, "Outfit-Medium.ttf"), ("Outfit", 600, "Outfit-SemiBold.ttf"),
                             ("JetBrains Mono", 400, "JetBrainsMono-Regular.ttf"), ("JetBrains Mono", 500, "JetBrainsMono-Medium.ttf"),
                             ("Orbitron", 700, "Orbitron-Bold.ttf")])
    themes = f":root {{\n{_tokens('nebula')}\n  --display: {FONT_DISPLAY}; --body: {FONT_BODY}; --mono: {FONT_MONO};\n}}\n"
    for th in ("aurora", "accord"):
        themes += f":root[data-theme=\"{th}\"] {{\n{_tokens(th)}\n}}\n"
    return HEADER + faces + themes + RULES


HEADER = """/* Azeroth Accord: the style sheet of the design previews. GENERATED by tools/mockup_lib.py (`python -X utf8 tools/make_mockups.py --spec`): do not edit.
   The three themes of the addon (Nebula, Aurora, Accord: AzerothAccord/UI/Theme.lua) as tokens, and the pieces of the widget kit drawn with them,
   after the style sheet of Finland Dragon Credit Points (same owner, GPL-3.0). The fonts are the addon's own (SIL OFL 1.1). Original drawing:
   no game art, nothing is loaded from the network. */
"""

RULES = """
* { box-sizing: border-box; margin: 0; padding: 0; }
html, body { margin: 0; padding: 0; }
body { background: var(--stage-bg); font: 400 13px/1.4 var(--body); color: var(--text-1); width: 1200px; }
.stage { position: relative; width: 1200px; height: 720px; overflow: hidden; background: var(--stage); }
.dp { height: 34px; display: flex; align-items: center; gap: 14px; padding: 0 16px; background: #000; color: #bbb; font: 12px/1 'Segoe UI', sans-serif; width: 1200px; }
.dp b { color: #fff; letter-spacing: .12em; white-space: nowrap; }
.dp span { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.dp .r { margin-left: auto; color: #888; }
.mono { font-family: var(--mono); }
.muted, .grey { color: var(--text-3); }
.gold, .blue { color: var(--accent-text); }
.green { color: var(--ok); }
.red { color: var(--err); }
.small { font-size: 12px; }
.grow { flex: 1; }
h2 { font: 600 14px/1.2 var(--body); color: var(--text-1); margin-bottom: 4px; }
h3 { font: 600 14px/1.2 var(--body); color: var(--text-1); margin-bottom: 4px; }
p { margin: 0 0 8px; }
.eyebrow { font: 500 11px/1 var(--body); letter-spacing: .22em; text-transform: uppercase; color: var(--accent-text); }
.sep { height: 1px; background: var(--border-subtle); margin: 10px 0; }

/* ---- the guild window in the theme (M6.18: UI/GuildSkin.lua dresses the game's guild window while the Accord tab is open) --------- */
.gw { position: absolute; left: 36px; top: 20px; width: 1070px; height: 680px; background: var(--bg); border: 1px solid var(--border); border-radius: 12px;
  box-shadow: inset 0 1px 0 var(--highlight), 0 24px 60px -20px rgba(0,0,0,.75); }
.gw-title { position: absolute; left: 0; right: 0; top: 0; height: 44px; display: flex; align-items: center; gap: 10px; padding: 0 14px; margin: 0 12px; border-bottom: 1px solid var(--border-subtle); padding-left: 2px; }
.gw-title img { width: 24px; height: 24px; border-radius: 50%; }
.gw-title b { color: var(--text-1); font: 600 16px/1 var(--body); }
.gw-title .sub { color: var(--text-3); font-size: 12px; }
.gw-title .x { margin-left: auto; width: 24px; height: 24px; display: grid; place-items: center; color: var(--text-2); }
.gw-tabs { position: absolute; right: -52px; top: 62px; display: flex; flex-direction: column; gap: 14px; }
.gw-tab { position: relative; width: 44px; height: 44px; border-radius: 12px; background: var(--surface-2); border: 1px solid var(--border); display: grid; place-items: center; }
.gw-tab.on { background: var(--secondary-container); border-color: transparent; }
.gw-tab .badge { position: absolute; top: -4px; right: -4px; min-width: 16px; height: 16px; padding: 0 4px; border-radius: 8px; background: var(--err); color: var(--on-error);
  font: 500 10px/16px var(--body); text-align: center; }
.gw-tab svg { width: 26px; height: 26px; color: var(--text-2); }
.gw-tab img { width: 30px; height: 30px; border-radius: 50%; }
.inset { position: absolute; left: 0; right: 0; top: 44px; bottom: 0; background: var(--bg); border-radius: 0 0 12px 12px; overflow: hidden; }
.pn { position: absolute; inset: 0; background: var(--bg); color: var(--text-1); }
/* the navigation rail (ui-style §9.11, M13.7): 80 wide, 56-point items, the active icon in the accent, no background */
.rail { position: absolute; left: 0; top: 0; bottom: 0; width: 80px; border-right: 1px solid var(--border-subtle); }
.rail .ri { position: absolute; left: 0; width: 80px; height: 56px; display: grid; place-items: center; color: var(--text-2); }
.rail .ri svg { position: relative; width: 24px; height: 24px; }
.rail .ri.on { color: var(--accent-text); }
.rail .ri .n { position: absolute; left: 44px; top: 8px; min-width: 16px; height: 16px; padding: 0 4px; border-radius: 8px; background: var(--err); color: var(--on-error);
  font: 500 10px/16px var(--body); text-align: center; }
.tabbar { position: absolute; left: 96px; right: 16px; top: 4px; height: 48px; display: flex; align-items: stretch; gap: 4px; border-bottom: 1px solid var(--border); }
.tabbar .dest { display: flex; align-items: center; font: 600 18px/1 var(--body); color: var(--text-1); padding-right: 12px; white-space: nowrap; }
.tabbar .tab { position: relative; display: flex; align-items: center; gap: 6px; font: 600 14px/1 var(--body); color: var(--text-2); padding: 0 12px; white-space: nowrap; }
.tabbar .tab.on { color: var(--accent-text); }
.tabbar .tab.on::after { content: ""; position: absolute; left: 14px; right: 14px; bottom: 0; height: 3px; border-radius: 3px 3px 0 0; background: var(--accent); }
.tabbar .tab .n { display: inline-grid; place-items: center; min-width: 16px; height: 16px; padding: 0 4px; border-radius: 8px; font: 500 10px/1 var(--body); background: var(--err); color: var(--on-error); }
.tabbar .right { margin-left: auto; display: flex; align-items: center; gap: 8px; }
.pbody { position: absolute; left: 96px; right: 16px; top: 64px; bottom: 36px; overflow: hidden; }
.pfoot { position: absolute; left: 96px; right: 16px; bottom: 0; height: 32px; display: flex; align-items: center; font: 400 11px/1 var(--mono); color: var(--text-3); }
.rel { position: relative; height: 100%; }

/* ---- the standalone window (/accord, Pop out): title bar, tabs, body; 920 x 600 --------------------------------------------------------- */
.win { position: absolute; left: 140px; top: 50px; width: 920px; height: 600px; background: var(--bg); border: 1px solid var(--border); border-radius: 12px;
  box-shadow: inset 0 1px 0 var(--highlight), 0 24px 60px -20px rgba(0,0,0,.75); overflow: hidden; }
.tbar { position: absolute; left: 0; right: 0; top: 0; height: 52px; display: flex; align-items: center; gap: 12px; padding: 0 16px 0 14px; background: var(--surface-1); border-bottom: 1px solid var(--border-subtle); }
.tbar img { width: 30px; height: 30px; border-radius: 50%; box-shadow: 0 0 12px var(--glow-accent); }
.tbar .ttl { font: 700 15px/1 var(--display); letter-spacing: .14em; text-transform: uppercase; text-shadow: 0 0 12px var(--glow); }
.tbar .sub { font: 12px/1 var(--mono); color: var(--text-3); }
.tbar .grow { flex: 1; }
.xbtn { width: 32px; height: 32px; border-radius: 16px; display: grid; place-items: center; color: var(--text-2); }
.win .inner { position: absolute; left: 0; right: 0; top: 52px; bottom: 0; }
.grip { position: absolute; right: 6px; bottom: 6px; width: 14px; height: 14px; opacity: .8; }

/* ---- buttons, chips, fields: Material 3 (docs/specs/ui-style.md §9.6) ----------------------------------------------------------------- */
.btn { display: inline-flex; align-items: center; justify-content: center; gap: 8px; height: 40px; padding: 0 24px; border-radius: 999px; font: 500 13px/1 var(--body); white-space: nowrap;
  background: var(--secondary-container); border: 1px solid transparent; color: var(--on-secondary-container); }
.btn.filled { background: var(--accent); color: var(--on-accent); box-shadow: 0 0 18px var(--glow-accent); }
:root[data-theme="aurora"] .btn.filled { box-shadow: none; }
.btn.outlined { background: transparent; border-color: var(--border); color: var(--text-2); }
.btn.text { background: transparent; color: var(--accent-text); padding: 0 12px; }
.btn.dense { height: 36px; padding: 0 20px; }
.btn.dense.text { padding: 0 12px; }
.btn.sm { height: 32px; padding: 0 14px; }
.btn.icon { width: 32px; height: 32px; padding: 0; }
.chip { display: inline-flex; align-items: center; justify-content: center; gap: 8px; height: 32px; padding: 0 16px; border-radius: 8px; font: 500 13px/1 var(--body); white-space: nowrap;
  background: transparent; border: 1px solid var(--border); color: var(--text-2); }
.chip.sel { background: var(--secondary-container); border-color: transparent; color: var(--on-secondary-container); padding-left: 8px; }
.chip.sel::before, .seg span.on::before { content: ""; flex: none; width: 10px; height: 5px; margin: -2px 3px 0 4px; border-left: 2px solid currentColor; border-bottom: 2px solid currentColor; transform: rotate(-45deg); }
.chip.lock { opacity: .38; }
.seg { display: inline-flex; height: 32px; border-radius: 16px; border: 1px solid var(--border); overflow: hidden; }
.seg span { display: flex; align-items: center; justify-content: center; gap: 8px; padding: 0 14px; font: 500 13px/1 var(--body); color: var(--text-1); white-space: nowrap; }
.seg span + span { border-left: 1px solid var(--border); }
.seg span.on { background: var(--secondary-container); color: var(--on-secondary-container); }
.dd { display: inline-flex; align-items: center; justify-content: space-between; gap: 10px; height: 32px; padding: 0 10px 0 12px; border-radius: 4px; background: var(--surface-2); border: 1px solid var(--border);
  font: 400 13px/1 var(--body); color: var(--text-3); }
.dd i { width: 7px; height: 7px; border-right: 1.5px solid var(--text-2); border-bottom: 1.5px solid var(--text-2); transform: translateY(-2px) rotate(45deg); }
.dd.val { color: var(--text-1); }
.edit { display: inline-flex; align-items: center; height: 36px; padding: 0 12px; border-radius: 4px; background: var(--surface-2); border: 1px solid var(--border); color: var(--text-1); font: 400 13px/1 var(--body); white-space: nowrap; overflow: hidden; }
.edit.tall { height: 40px; }
.edit.muted { color: var(--text-3); }
.edit.url { font: 400 12px/1 var(--mono); color: var(--text-1); }
.search { display: inline-flex; align-items: center; height: 36px; padding: 0 12px; border-radius: 4px; background: var(--surface-2); border: 1px solid var(--border); color: var(--text-3); font: 400 13px/1 var(--body); }
.search.typed { color: var(--text-1); }
.sw { display: inline-block; flex: none; width: 52px; height: 32px; border-radius: 16px; background: var(--raised); border: 2px solid var(--border-strong); position: relative; }
.sw::after { content: ""; position: absolute; top: 6px; left: 6px; width: 16px; height: 16px; border-radius: 50%; background: var(--border-strong); }
.sw.on { background: var(--accent); border-color: var(--accent); }
.sw.on::after { top: 2px; left: 22px; width: 24px; height: 24px; background: var(--on-accent); }
.pill { display: inline-flex; align-items: center; gap: 6px; height: 16px; padding: 0 8px; border-radius: 8px; font: 500 10px/1 var(--body); white-space: nowrap;
  background: color-mix(in srgb, var(--text-2) 16%, transparent); color: var(--text-2); }
.pill.accent { background: color-mix(in srgb, var(--accent) 16%, transparent); color: var(--accent-text); }
.pill.ok { background: color-mix(in srgb, var(--ok) 16%, transparent); color: var(--ok); }
.pill.warn { background: color-mix(in srgb, var(--warn) 16%, transparent); color: var(--warn); }
.pill.err { background: var(--err); color: var(--on-error); padding: 0 4px; min-width: 16px; justify-content: center; }
.menu { position: absolute; background: var(--surface-2); border-radius: 4px; box-shadow: 0 12px 30px -8px rgba(0,0,0,.6); padding: 4px 0; z-index: 20; }
.menu div { height: 32px; line-height: 32px; padding: 0 12px; font-size: 13px; position: relative; color: var(--text-1); }
.menu div.on { background: var(--secondary-container); color: var(--on-secondary-container); }
.menu div.head { color: var(--text-3); font: 500 11px/32px var(--body); text-transform: uppercase; }
.tip { position: absolute; background: rgba(10, 10, 16, .96); color: #fff; padding: 8px 10px; border-radius: 4px; box-shadow: 0 0 0 1px #5a5a66, 0 8px 22px rgba(0,0,0,.6); z-index: 30; font: 400 13px/1.35 'Segoe UI', Arial, sans-serif; }
.tip .gold { color: #ffd100; } .tip .green { color: #1eff00; } .tip .muted { color: #9d9d9d; }

/* ---- cards: filled, radius 12, no outline ----------------------------------------------------------------------------------------------- */
.card { background: var(--surface-1); border-radius: 12px; padding: 16px; box-shadow: inset 0 1px 0 var(--highlight); }
:root[data-theme="aurora"] .card { box-shadow: 0 0 0 1px var(--border-subtle); }
.card.sm { padding: 10px 14px; }
.dialog { position: absolute; background: var(--surface-3); border-radius: 28px; padding: 24px; box-shadow: 0 24px 60px -20px rgba(0,0,0,.8); }
.bar { height: 4px; border-radius: 2px; background: var(--surface-3); overflow: hidden; }
.bar i { display: block; height: 100%; background: var(--accent); }
.tools { display: flex; align-items: center; gap: 8px; height: 40px; flex-wrap: nowrap; white-space: nowrap; margin-bottom: 4px; }
.tools .grow { flex: 1; }

/* ---- class square and name ------------------------------------------------------------------------------------------------------------- */
.sq { display: inline-block; width: 10px; height: 10px; border-radius: 3px; background: var(--c, #888); margin-right: 9px; vertical-align: -1px; flex: none; box-shadow: 0 0 8px color-mix(in srgb, var(--c, #888) 60%, transparent); }
:root[data-theme="aurora"] .sq { box-shadow: 0 0 0 1px rgba(11,27,43,.25); }
.sq.lg { width: 22px; height: 22px; border-radius: 6px; margin-right: 0; }
:root[data-theme="aurora"] .cn { color: var(--text-1) !important; }
.cn { font-weight: 500; }

/* ---- the DataTable ---------------------------------------------------------------------------------------------------------------------- */
.tbl { width: 100%; border-collapse: separate; border-spacing: 0; table-layout: fixed; }
.tbl th { height: 32px; padding: 0 10px; text-align: left; font: 500 11px/1 var(--body); letter-spacing: .08em; text-transform: uppercase; color: var(--text-3); background: var(--surface-2); white-space: nowrap; overflow: hidden; }
.tbl th:first-child { border-radius: 8px 0 0 8px; } .tbl th:last-child { border-radius: 0 8px 8px 0; }
.tbl th.sorted { color: var(--accent-text); }
.tbl th.sorted::after { content: ""; display: inline-block; margin-left: 6px; border: 3.5px solid transparent; border-top: 5px solid var(--accent-text); border-bottom: 0; vertical-align: 2px; }
.tbl th.sorted.asc::after { border-top: 0; border-bottom: 5px solid var(--accent-text); }
.tbl td { height: 32px; padding: 0 10px; font: 400 13px/1 var(--body); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; border-top: 1px solid var(--border-subtle); color: var(--text-1); }
.tbl tr:first-child td { border-top: 0; }
.tbl tr.sel td { background: var(--secondary-container); color: var(--on-secondary-container); }
.tbl tr.sel td span:not(.cn):not(.sq) { color: var(--on-secondary-container); }
.tbl tr.sel td:first-child { border-radius: 4px 0 0 4px; } .tbl tr.sel td:last-child { border-radius: 0 4px 4px 0; }
.tbl tr.alt td { color: var(--text-2); }
.tbl tr.hover td { background: color-mix(in srgb, var(--text-1) 8%, transparent); }
.tbl td.num { text-align: right; }
.tbl.tall td { height: 36px; }   /* a list whose rows hold a button */
.sb { position: absolute; right: 0; top: 40px; bottom: 0; width: 4px; border-radius: 2px; background: var(--border-subtle); }
.sb::after { content: ""; position: absolute; left: 0; right: 0; top: var(--t, 6px); height: var(--h, 70px); border-radius: 2px; background: var(--border-strong); }

/* ---- bank ------------------------------------------------------------------------------------------------------------------------------- */
.slot { position: relative; width: 34px; height: 34px; border-radius: 6px; background: var(--surface-2); border: 1px solid var(--border-subtle); }
.slot i { position: absolute; inset: 3px; border-radius: 4px; background: linear-gradient(135deg, var(--a, #6a5a3a), var(--b, #2a2216)); box-shadow: inset 0 0 0 1px rgba(255, 255, 255, .12); }
.slot i::after { content: ""; position: absolute; left: 24%; top: 22%; width: 52%; height: 52%; border-radius: var(--r, 20%); background: rgba(255, 255, 255, .22); }
.slot.q2 { border-color: #1eff00; } .slot.q3 { border-color: #0070dd; } .slot.q4 { border-color: #a335ee; }
.slot b { position: absolute; right: 3px; bottom: 1px; font: 600 11px/1 var(--body); color: #fff; text-shadow: 0 0 2px #000, 1px 1px 1px #000; }
.slot.empty { background: var(--surface-1); }
.ico { display: inline-block; position: relative; width: 20px; height: 20px; border-radius: 5px; background: linear-gradient(135deg, var(--a, #6a5a3a), var(--b, #2a2216)); box-shadow: inset 0 0 0 1px rgba(255, 255, 255, .15); vertical-align: -5px; margin-right: 8px; flex: none; }
.ico.q2 { box-shadow: inset 0 0 0 1px #1eff00; } .ico.q3 { box-shadow: inset 0 0 0 1px #0070dd; } .ico.q4 { box-shadow: inset 0 0 0 1px #a335ee; }
.coin { display: inline-block; width: 11px; height: 11px; border-radius: 50%; margin: 0 3px 0 6px; vertical-align: -1px; box-shadow: inset 0 0 0 1px rgba(0, 0, 0, .45); }
.coin.g { background: radial-gradient(circle at 35% 30%, #fff1a0, #f4c430 60%, #9a6f0d); }
.coin.s { background: radial-gradient(circle at 35% 30%, #fff, #c8ccd2 60%, #6c7078); }
.coin.c { background: radial-gradient(circle at 35% 30%, #ffd9b5, #c77f4a 60%, #744022); }

/* ---- annotated pages: callouts and legend ------------------------------------------------------------------------------------------------ */
.co { position: absolute; width: 22px; height: 22px; border-radius: 50%; background: #e0245e; color: #fff; font: 700 12px/22px 'Segoe UI', Arial, sans-serif; text-align: center; box-shadow: 0 0 0 2px #fff, 0 2px 6px rgba(0,0,0,.6); z-index: 50; }
.legend { position: absolute; right: 18px; bottom: 18px; width: 380px; padding: 10px 12px; background: rgba(0,0,0,.88); color: #eee; border-radius: 8px; z-index: 50; font: 12px/1.35 'Segoe UI', Arial, sans-serif; }
.legend div { display: flex; gap: 8px; margin: 3px 0; } .legend b { flex: none; width: 18px; height: 18px; border-radius: 50%; background: #e0245e; color: #fff; text-align: center; line-height: 18px; font-size: 11px; }
.clean .co, .clean .legend { display: none; }
"""


# ---- classes (the game's class colours; the square is an original drawing) ------------------------------------------------------------
CLASSES = {
    "WARRIOR": ("#c69b6d", "Wa"), "PALADIN": ("#f48cba", "Pa"), "HUNTER": ("#aad372", "Hu"), "ROGUE": ("#fff468", "Ro"),
    "PRIEST": ("#ffffff", "Pr"), "SHAMAN": ("#0070dd", "Sh"), "MAGE": ("#3fc7eb", "Ma"), "WARLOCK": ("#8788ee", "Wl"),
    "DRUID": ("#ff7c0a", "Dr"),
}
CLASS_NAME = {"WARRIOR": "Warrior", "PALADIN": "Paladin", "HUNTER": "Hunter", "ROGUE": "Rogue", "PRIEST": "Priest",
              "SHAMAN": "Shaman", "MAGE": "Mage", "WARLOCK": "Warlock", "DRUID": "Druid"}
CLASS_NAME_IT = {"WARRIOR": "Guerriero", "PALADIN": "Paladino", "HUNTER": "Cacciatore", "ROGUE": "Ladro", "PRIEST": "Sacerdote",
                 "SHAMAN": "Sciamano", "MAGE": "Mago", "WARLOCK": "Stregone", "DRUID": "Druido"}


def class_name(c):
    return (CLASS_NAME_IT if LANG[0] == "itIT" else CLASS_NAME)[c]


def color_of(c):
    return CLASSES[c][0]


def badge(c, big=False):
    """The class square that goes before a name (the Roster's ClassMark)."""
    return f'<span class="sq{" lg" if big else ""}" style="--c:{color_of(c)}"></span>'


def name(n, c, cls=""):
    """A character name in its class colour (on the light theme only the square is coloured, as in the addon)."""
    return f'<span class="cn {cls}" style="color:{color_of(c)}">{esc(n)}</span>'


# ---- small pieces -----------------------------------------------------------------------------------------------------------------------
def btn(text, kind="tonal", small=False, extra="", dense=False):
    """A button: `kind` "filled" (one per view or dialog), "tonal", "outlined" or "text"; 40 high, 36 with `dense` (toolbars
    and lines of a form), 32 with `small` (inside a row of a list)."""
    size = " sm" if small else " dense" if dense else ""
    return f'<span class="btn {kind}{size}" {extra}>{esc(text)}</span>'


def heart(small=True):
    """The tonal icon button of a like."""
    return ('<span class="btn icon"><svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><path d="M12 21s-8-5.2-8-11a4.6 4.6 0 0 1 8-3 4.6 4.6 0 0 1 8 3'
            'c0 5.8-8 11-8 11z"/></svg></span>')


def chip(text, kind="", small=False, extra=""):
    """A filter chip: `kind` "sel" is the selected one (tonal, with a check). Every chip is 32 high (`small` is kept for
    the callers)."""
    return f'<span class="chip {kind}" {extra}>{esc(text)}</span>'


def chk(text, on=False, off=False):
    """A yes/no filter: a filter chip (selected = tonal with a check); `off` is a choice that cannot be changed."""
    return chip(text, ("sel " if on else "") + ("lock" if off else ""))


def seg(options, on, extra=""):
    return f'<span class="seg" {extra}>' + "".join(f'<span class="{"on" if i == on else ""}">{esc(o)}</span>' for i, o in enumerate(options)) + "</span>"


def select(text, width=128, value=False):
    return f'<span class="dd{" val" if value else ""}" style="width:{width}px"><span>{esc(text)}</span><i></i></span>'


def switch(on=True):
    return f'<span class="sw{" on" if on else ""}"></span>'


def pill(text, tone=""):
    return f'<span class="pill {tone}">{esc(text)}</span>'


def search(text="", width=190):
    return f'<span class="search{" typed" if text else ""}" style="width:{width}px">{esc(text or T("SEARCH_PLACEHOLDER"))}</span>'


def edit(text, width=180, muted=False, extra=""):
    return f'<span class="edit{" muted" if muted else ""}" style="width:{width}px;{extra}">{esc(text)}</span>'


def menu(x, y, items, width=190):
    """items: [(text, on, head)]; absolutely positioned inside the nearest positioned parent."""
    rows = "".join(f'<div class="{"on" if on else ""} {"head" if head else ""}">{esc(t)}</div>' for t, on, head in items)
    return f'<div class="menu" style="left:{x}px;top:{y}px;width:{width}px">{rows}</div>'


def tip(x, y, inner, width=260):
    """The game's own tooltip (GameTooltip: Blizzard's dark frame, not themed)."""
    return f'<div class="tip" style="left:{x}px;top:{y}px;width:{width}px">{inner}</div>'


def coins(copper):
    g, s, c = copper // 10000, copper // 100 % 100, copper % 100
    out = []
    if g:
        out.append(f'{g:,}<span class="coin g"></span>')
    if s:
        out.append(f'{s}<span class="coin s"></span>')
    if c or not out:
        out.append(f'{c}<span class="coin c"></span>')
    return " ".join(out)


def card(inner, style="", cls=""):
    return f'<div class="card {cls}" style="{style}">{inner}</div>'


def callout(n, x, y):
    return f'<div class="co" style="left:{x}px;top:{y}px">{n}</div>'


def legend(items, left=False):
    style = ' style="left:18px;right:auto;bottom:18px"' if left else ""
    rows = "".join(f"<div><b>{i}</b><span>{esc(t)}</span></div>" for i, t in enumerate(items, 1))
    return f'<div class="legend"{style}>{rows}</div>'


def scrollbar(top=6, height=80):
    return f'<div class="sb" style="--t:{top}px;--h:{height}px"></div>'


# ---- item pictures (original: a tinted rounded square with a lighter shape) ---------------------------------------------------------------
_PALETTES = [("#8a6a3a", "#2e2312"), ("#6a8a4a", "#1c2a12"), ("#4a6a9a", "#121c2e"), ("#9a4a4a", "#2e1212"), ("#7a5a9a", "#201230"),
             ("#9a8a3a", "#2e2a12"), ("#4a9a8a", "#12302a"), ("#8a8a8a", "#222222")]


def pic(seed, q=1):
    """A small item picture (a list row): a tinted square, original art."""
    a, b = _PALETTES[seed % len(_PALETTES)]
    return f'<span class="ico {"q" + str(q) if q > 1 else ""}" style="--a:{a};--b:{b}"></span>'


def slot(seed=None, count=0, q=1):
    if seed is None:
        return '<div class="slot empty"></div>'
    a, b = _PALETTES[seed % len(_PALETTES)]
    r = ["20%", "50%", "8%"][seed % 3]
    cls = f"q{q}" if q > 1 else ""
    num = f"<b>{count}</b>" if count > 1 else ""
    return f'<div class="slot {cls}" style="--a:{a};--b:{b};--r:{r}"><i></i>{num}</div>'


# ---- guild emblem and tab icons (original SVG) --------------------------------------------------------------------------------------------
def emblem(w=26, h=30, bg="#26324d", fg="#e3b43d"):
    return (f'<svg class="emb" viewBox="0 0 26 30" width="{w}" height="{h}"><path d="M2 2h22v15c0 6-6 10-11 12C8 27 2 23 2 17z" fill="{bg}" stroke="#c9a227" stroke-width="1.6"/>'
            f'<path d="M13 7v3m-3 0h6m-5 0v8a3 3 0 0 0 4 0v-8" fill="none" stroke="{fg}" stroke-width="1.6" stroke-linecap="round"/>'
            f'<circle cx="13" cy="20" r="1.8" fill="{fg}"/></svg>')


_TAB_SVG = {
    "chat": '<path d="M5 6h18v12H13l-5 5v-5H5z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
    "roster": '<path d="M5 8h18M5 14h18M5 20h12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
    "benefits": '<path d="M14 4l3 7 7 .6-5.3 4.7 1.7 7.2L14 19.8 7.6 23.5l1.7-7.2L4 11.6 11 11z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>',
    "info": '<circle cx="14" cy="14" r="10" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M14 12v8M14 8v2" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>',
}
ASSETS = "{ASSETS}"   # replaced by the folder of assets/ (an absolute file URL, or a relative path in the pages of html/)


def logo(size=30, cls=""):
    return f'<img class="{cls}" src="{ASSETS}/logo-source.webp" alt="" width="{size}" height="{size}" style="border-radius:50%">'


def gtab(kind, on=False, badge=None):
    b = f'<span class="badge">{badge}</span>' if badge else ""
    inner = logo(30) if kind == "accord" else f'<svg viewBox="0 0 28 28">{_TAB_SVG[kind]}</svg>'
    return f'<div class="gw-tab{" on" if on else ""}">{inner}{b}</div>'


# ---- the window and the panel -------------------------------------------------------------------------------------------------------------
GUILD = "Lantern Company"
SUB = "Guild"


def guild_window(inner, active="accord", badge=None, title=None, sub=None):
    """The game's guild window while the Accord tab is open, dressed in the theme (UI/GuildSkin.lua): a themed frame, the guild's
    name, the cross and the five side tabs as tiles; `inner` fills the content area. (`sub` is kept for the callers, unused.)"""
    t = "".join(gtab(k, k == active, badge if k == "accord" else None) for k in ("chat", "roster", "benefits", "info", "accord"))
    return (f'<div class="gw"><div class="gw-title">{logo(24)}<b>{esc(title or GUILD)}</b><span class="x">{_X}</span></div>'
            f'<div class="gw-tabs">{t}</div><div class="inset">{inner}</div></div>')


# The destinations of the rail and their pages (UI/Shell.lua, ui-style §9.11) with the switches as they ship (econ off).
# Generic line icons of our own (the addon draws Material Symbols; these previews keep original art, ADR 0019).
DESTS = [("home", "NAV_HOME"), ("guild", "NAV_GUILD"), ("raid", "NAV_RAID"), ("groups", "NAV_GROUPS"), ("professions", "NAV_PROFESSIONS"),
         ("economy", "NAV_ECONOMY"), ("community", "NAV_COMMUNITY"), ("officers", "NAV_OFFICERS"), ("settings", "NAV_SETTINGS")]
DEST_PAGES = {
    "home": [("actions", "VIEW_ACTIONS"), ("notices", "NOTICE_PAGE")],
    "guild": [("roster", "VIEW_ROSTER"), ("reputation", "VIEW_REPUTATION"), ("mentors", "REP_MODE_MENTORS"), ("addons", "VIEW_ADDONS")],
    "raid": [("season", "VIEW_SEASON"), ("events", "VIEW_EVENTS"), ("raid", "VIEW_RAID"), ("availability", "VIEW_AVAILABILITY")],
    "groups": [("groups", "GRP_PAGE_LIST"), ("form", "GRP_PAGE_FORM"), ("mine", "GRP_PAGE_MINE"), ("rallies", "EVENTS_PAGE_RALLIES")],
    "professions": [("professions", "PAGE_RECIPES")],
    "economy": [("bank", "VIEW_BANK")],
    "community": [("handbook", "VIEW_HANDBOOK")],
    "officers": [("inactive", "OFF_PAGE_INACTIVE"), ("queue", "OFF_PAGE_QUEUE"), ("timeline", "OFF_PAGE_TIMELINE"), ("trials", "OFF_PAGE_TRIALS")],
    "settings": [("settings", "SET_PAGE_GENERAL"), ("share", "SHARE_TAB"), ("info", "ABOUT_TAB")],
}
_RAIL_SVG = {
    "home": '<path d="M4 11l8-7 8 7v9h-5v-6H9v6H4z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
    "guild": '<circle cx="9" cy="8" r="3" fill="none" stroke="currentColor" stroke-width="1.8"/><circle cx="17" cy="9" r="2.4" fill="none" stroke="currentColor" stroke-width="1.6"/>'
             '<path d="M3 19c0-3.3 2.7-5 6-5s6 1.7 6 5M15 14.5c3 0 6 1.3 6 4.5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
    "raid": '<path d="M5 4l10 10M4 5l1-1M19 4L9 14M20 5l-1-1M7 15l-3 3 2 2 3-3M17 15l3 3-2 2-3-3" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
    "groups": '<circle cx="10" cy="8" r="3.2" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M3 20c0-3.6 3-5.5 7-5.5s7 1.9 7 5.5M19 7v6M16 10h6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
    "professions": '<path d="M14 6l4 4-9 9-4-4zM14 6l2-2 4 4-2 2" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
    "economy": '<path d="M3 9l9-5 9 5zM5 10v8M10 10v8M14 10v8M19 10v8M3 20h18" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round" stroke-linecap="round"/>',
    "community": '<path d="M12 3l2.6 5.6 6 .6-4.5 4 1.3 6L12 16.2 6.6 19.2l1.3-6-4.5-4 6-.6z" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"/>',
    "officers": '<path d="M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"/>',
    "settings": '<circle cx="12" cy="12" r="3" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M5.6 18.4l2.1-2.1M16.3 7.7l2.1-2.1" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>',
}


def dest_of(view):
    """The destination and the page of `view` ("bank", or "settings:info" for a page of a view with pages)."""
    page = view.split(":")[-1]
    for d, pages in DEST_PAGES.items():
        for pid, _ in pages:
            if pid == page:
                return d, pid
    return "guild", page


def rail(view, badges=None, officer=False):
    """The navigation rail: one icon per destination, Settings at the bottom, the active one in the accent."""
    active, _ = dest_of(view)
    out, y = "", 8
    for d, _ in DESTS:
        if d == "officers" and not officer:
            continue
        n = (badges or {}).get(d)
        badge = f'<span class="n">{n}</span>' if n else ""
        top = "bottom:8px" if d == "settings" else f"top:{y}px"
        out += f'<div class="ri{" on" if d == active else ""}" style="{top}"><svg viewBox="0 0 24 24">{_RAIL_SVG[d]}</svg>{badge}</div>'
        if d != "settings":
            y += 56
    return f'<div class="rail">{out}</div>'


def status_text(peers=7, ago=2):
    return T("STATUS_PEERS", peers) + " · " + T("STATUS_UPDATED", T("AGO_MINUTES", ago))


def tabbar(view, badge=None, search_text=None, searchable=True, popout=True, popin=False, width=150):
    """The row at the top of the content (ui-style §9.11): the destination's name, then the tabs of its pages (Widgets.Tabs: an
    indicator under the active one; none when the destination has one page), the search box on the right while the page
    has a search, and Pop out in the guild window."""
    dest, page = dest_of(view)
    tabs = f'<div class="dest">{esc(T(dict(DESTS)[dest]))}</div>'
    pages = DEST_PAGES[dest]
    if len(pages) > 1:
        for pid, key in pages:
            tabs += f'<div class="tab{" on" if pid == page else ""}">{esc(T(key))}</div>'
    right = ""
    if searchable:
        right += search(search_text or "", width)
    if popout:
        right += btn(T("POP_OUT"), "outlined", dense=True)
    return f'<div class="tabbar">{tabs}<div class="right">{right}</div></div>'


def panel(view, body, badge=None, search_text=None, popout=True, peers=7, ago=2, searchable=True):
    """The Accord panel inside the guild window: the rail at the left, the row on top, the body, the sync state in the
    footer. A bank count (`badge`) is on the Economy icon."""
    badges = {"economy": badge} if badge else None
    return (f'<div class="pn">{rail(view, badges, officer=bool(badge))}{tabbar(view, badge, search_text, searchable, popout)}<div class="pbody">{body}</div>'
            f'<div class="pfoot">{esc(status_text(peers, ago))}</div></div>')


def full(view, body, active_tab="accord", badge=None, **kw):
    """A whole scene: the guild window with the Accord tab selected and the panel inside."""
    tab_badge = kw.pop("tab_badge", badge)
    return guild_window(panel(view, body, badge=badge, **kw), badge=tab_badge, active=active_tab)


def standalone(view, body, badge=None, peers=7, ago=2, search_text=None, searchable=True, popin=True):
    """The standalone window (/accord, Pop out): title bar with the logo, the name and the sync state, Pop in and close."""
    top = (f'<div class="tbar">{logo(30)}<span class="ttl">{esc(T("WINDOW_TITLE"))}</span><span class="sub">{esc(status_text(peers, ago))}</span><span class="grow"></span>'
           f'{btn(T("POP_IN"), "text", dense=True) if popin else ""}<span class="xbtn">{_X}</span></div>')
    grip = '<svg class="grip" viewBox="0 0 14 14"><path d="M13 3L3 13M13 8L8 13" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" fill="none" style="color:var(--text-3)"/></svg>'
    badges = {"economy": badge} if badge else None
    return (f'<div class="win">{top}<div class="inner"><div class="pn">{rail(view, badges)}{tabbar(view, badge, search_text, searchable, popout=False, width=200)}'
            f'<div class="pbody" style="bottom:16px">{body}</div></div></div>{grip}</div>')


_X = '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M18 6 6 18M6 6l12 12"/></svg>'


# ---- tables -------------------------------------------------------------------------------------------------------------------------------
def table(cols, rows, sort=None, desc=False, sel=(), alt=(), hover=()):
    """cols: [(label, width)]; rows: [[cell html, ...]]; sort: the index of the sorted column."""
    head = "".join(f'<th class="{"sorted" if i == sort else ""}{" asc" if (i == sort and not desc) else ""}" style="width:{w}px">{esc(l)}</th>' for i, (l, w) in enumerate(cols))
    body = ""
    for r, cells in enumerate(rows):
        cls = ("sel " if r in sel else "") + ("alt " if r in alt else "") + ("hover " if r in hover else "")
        body += f'<tr class="{cls}">' + "".join(f"<td>{c}</td>" for c in cells) + "</tr>"
    return f'<table class="tbl"><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table>'


def tools(*items, right=""):
    return f'<div class="tools">{"".join(items)}<span class="grow"></span>{right}</div>'
