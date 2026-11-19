"""HTML building blocks for tools/make_mockups.py (design previews of the Azeroth Accord interface).

Pure string helpers: no browser, no file access except reading the locale tables. The look comes from
docs/specs/mockups/html/accord.css (dark insets, bronze frames, gold headings: the look of the game's guild window, the
look the panel really has, SPEC-04 §5). Every text of the interface is read from AzerothAccord/Locale/enUS.lua (or itIT.lua),
so a preview never disagrees with the addon; only the invented data (guild, characters, items) is written in the scenes.

Original art only: the class badges, guild emblem, tab icons and item pictures are drawn with CSS and inline SVG; no game
screenshot, icon or texture is used, and nothing is loaded from the network.
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


# ---- classes (the game's class colours; the badge is an original monogram) ---------------------------------------------
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
    col, mono = CLASSES[c]
    return f'<span class="cb{" lg" if big else ""}" style="--c:{col}">{mono}</span>'


def name(n, c, cls=""):
    """A character name in its class colour, with the badge."""
    return f'<span class="{cls}" style="color:{color_of(c)}">{esc(n)}</span>'


# ---- small pieces -------------------------------------------------------------------------------------------------------
def btn(text, kind="", small=False, extra=""):
    return f'<span class="btn{" sm" if small else ""} {kind}" {extra}>{esc(text)}</span>'


def chk(text, on=False, off=False):
    return f'<span class="chk{" on" if on else ""}{" off" if off else ""}"><i></i>{esc(text)}</span>'


def search(text="", width=190):
    return f'<span class="search{" typed" if text else ""}" style="width:{width}px">{esc(text)}</span>'


def edit(text, width=180, muted=False):
    return f'<span class="edit{" muted" if muted else ""}" style="width:{width}px">{esc(text)}</span>'


def chip(text, kind=""):
    return f'<span class="chip {kind}">{esc(text)}</span>'


def menu(x, y, items, width=190):
    """items: [(text, on, head)]; absolutely positioned inside the nearest positioned parent."""
    rows = "".join(f'<div class="{"on" if on else ""} {"head" if head else ""}">{esc(t)}</div>' for t, on, head in items)
    return f'<div class="menu" style="left:{x}px;top:{y}px;width:{width}px">{rows}</div>'


def tip(x, y, inner, width=260):
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


def callout(n, x, y):
    return f'<div class="co" style="left:{x}px;top:{y}px">{n}</div>'


def legend(items, left=False):
    style = ' style="left:204px;right:auto;bottom:18px"' if left else ""
    rows = "".join(f"<div><b>{i}</b><span>{esc(t)}</span></div>" for i, t in enumerate(items, 1))
    return f'<div class="legend"{style}>{rows}</div>'


def scrollbar(top=6, height=80):
    return f'<div class="sb" style="--t:{top}px;--h:{height}px"></div>'


# ---- item pictures (original: a tinted rounded square with a lighter shape) ---------------------------------------------
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


# ---- guild emblem and tab icons (original SVG) ---------------------------------------------------------------------------
def emblem(w=26, h=30, bg="#26324d", fg="#e3b43d"):
    return (f'<svg class="emb" viewBox="0 0 26 30" width="{w}" height="{h}"><path d="M2 2h22v15c0 6-6 10-11 12C8 27 2 23 2 17z" fill="{bg}" stroke="#c9a227" stroke-width="1.6"/>'
            f'<path d="M13 7v3m-3 0h6m-5 0v8a3 3 0 0 0 4 0v-8" fill="none" stroke="{fg}" stroke-width="1.6" stroke-linecap="round"/>'
            f'<circle cx="13" cy="20" r="1.8" fill="{fg}"/></svg>')


_TAB_SVG = {
    "chat": '<path d="M5 6h18v12H13l-5 5v-5H5z" fill="none" stroke="#e8d9b0" stroke-width="1.8" stroke-linejoin="round"/>',
    "roster": '<path d="M5 8h18M5 14h18M5 20h12" stroke="#e8d9b0" stroke-width="2" stroke-linecap="round"/>',
    "benefits": '<path d="M14 4l3 7 7 .6-5.3 4.7 1.7 7.2L14 19.8 7.6 23.5l1.7-7.2L4 11.6 11 11z" fill="none" stroke="#e8d9b0" stroke-width="1.6" stroke-linejoin="round"/>',
    "info": '<circle cx="14" cy="14" r="10" fill="none" stroke="#e8d9b0" stroke-width="1.8"/><path d="M14 12v8M14 8v2" stroke="#e8d9b0" stroke-width="2" stroke-linecap="round"/>',
    "accord": '<path d="M7 4h14v13c0 4-4 6-7 8-3-2-7-4-7-8z" fill="#3a2c14" stroke="#ffd100" stroke-width="1.8"/><path d="M14 9v2.5m-2.5 0h5m-4 0v5a2 2 0 0 0 3 0v-5" fill="none" stroke="#ffd100" stroke-width="1.5" stroke-linecap="round"/>',
}


def gtab(kind, on=False, badge=None):
    b = f'<span class="badge">{badge}</span>' if badge else ""
    return f'<div class="gw-tab{" on" if on else ""}"><svg viewBox="0 0 28 28">{_TAB_SVG[kind]}</svg>{b}</div>'


# ---- the window and the panel ------------------------------------------------------------------------------------------------
GUILD = "Lantern Company"
SUB = "Guild"


def guild_window(inner, active="accord", badge=None, pop=False, title=None, sub=None, tabs=True):
    t = "".join(gtab(k, k == active, badge if k == "accord" else None) for k in ("chat", "roster", "benefits", "info", "accord")) if tabs else ""
    return (f'<div class="gw{" pop" if pop else ""}"><div class="gw-title">{emblem()}<b>{esc(title or GUILD)}</b>'
            f'<span class="sub">{esc(SUB if sub is None else sub)}</span><span class="x">x</span></div>'
            f'<div class="gw-tabs">{t}</div><div class="inset">{inner}</div></div>')


VIEWS = [("roster", "VIEW_ROSTER"), ("professions", "VIEW_PROFESSIONS"), ("reputation", "VIEW_REPUTATION"), ("bank", "VIEW_BANK"),
         ("settings", "VIEW_SETTINGS")]


def status_text(peers=7, ago=2):
    return T("STATUS_PEERS", peers) + " · " + T("STATUS_UPDATED", T("AGO_MINUTES", ago))


def panel(view, body, badge=None, search_text=None, popout=True, peers=7, ago=2, searchable=True):
    """The Accord panel: top bar, navigation and the body of a view. `badge` is the count on the Bank entry."""
    nav = ""
    for vid, key in VIEWS:
        label = T(key) + (f" ({badge})" if badge and vid == "bank" else "")
        nav += f'<div class="nav-item{" on" if vid == view else ""}">{esc(label)}</div>'
    s = search(search_text or "") if searchable else ""
    pop = btn(T("POP_OUT"), small=True) if popout else ""
    return (f'<div class="acc"><div class="acc-top">{s}<span class="grow"></span><span class="status">{esc(status_text(peers, ago))}</span>{pop}</div>'
            f'<div class="acc-nav">{nav}</div><div class="acc-body">{body}</div></div>')


def full(view, body, active_tab="accord", badge=None, **kw):
    """A whole scene: the guild window with the Accord tab selected and the panel inside."""
    tab_badge = kw.pop("tab_badge", badge)
    return guild_window(panel(view, body, badge=badge, **kw), badge=tab_badge, active=active_tab)


# ---- tables --------------------------------------------------------------------------------------------------------------------
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
