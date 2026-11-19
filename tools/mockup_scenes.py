"""Every case of the interface as a design preview (see tools/make_mockups.py), part 1: the Accord tab, the Roster, the member
card, professions and recipes. One function per image, registered with @scene(file name, caption). A scene returns the HTML
that goes inside the 1200x720 stage. All interface texts come from the addon's locale tables; the characters, guild and
items are invented."""
from mockup_lib import *  # noqa: F401,F403
import mockup_lib as lib

SCENES = []


def scene(name, caption, lang="enUS"):
    def deco(fn):
        SCENES.append((name, caption, fn, lang))
        return fn
    return deco


# ---- invented guild --------------------------------------------------------------------------------------------------------
RANKS = ["Guild Master", "Officer", "Veteran", "Member", "Initiate"]
RANKS_IT = ["Maestro di gilda", "Ufficiale", "Veterano", "Membro", "Recluta"]
ZONES = ["Stormwind City", "Ironforge", "Darnassus", "Silithus", "Tanaris", "Winterspring", "Burning Steppes", "E. Plaguelands", "Un'Goro Crater", "Orgrimmar"]
# name, level, class, rank, zone, online?, last-online hours, prof1, prof2, likes, addon version
MEMBERS = [
    ("Aldric", 60, "WARRIOR", 0, 0, True, 0, ("Blacksmithing", 300, 300), ("Mining", 290, 300), 14, "1.0.0"),
    ("Brynn", 60, "MAGE", 1, 1, True, 0, ("Alchemy", 285, 300), ("Herbalism", 300, 300), 11, "1.0.0"),
    ("Cora", 58, "PRIEST", 1, 2, True, 0, ("Tailoring", 260, 300), ("Enchanting", 225, 300), 9, "1.0.0"),
    ("Dunstan", 60, "PALADIN", 2, 0, True, 0, ("Blacksmithing", 245, 300), ("Mining", 250, 300), 7, "1.0.0"),
    ("Elowen", 55, "DRUID", 3, 2, False, 3, ("Herbalism", 300, 300), ("Alchemy", 190, 300), 6, "1.0.0"),
    ("Fenwick", 60, "ROGUE", 2, 3, True, 0, ("Engineering", 300, 300), ("Mining", 300, 300), 8, "1.0.0"),
    ("Garrick", 47, "HUNTER", 3, 4, False, 20, ("Skinning", 210, 300), ("Leatherworking", 205, 300), 3, ""),
    ("Hollis", 60, "SHAMAN", 2, 5, True, 0, ("Leatherworking", 290, 300), ("Skinning", 300, 300), 5, "1.0.0"),
    ("Isolde", 52, "WARLOCK", 3, 1, False, 52, ("Tailoring", 180, 300), ("Enchanting", 150, 300), 4, ""),
    ("Joren", 60, "WARRIOR", 3, 6, True, 0, ("Mining", 275, 300), ("Blacksmithing", 100, 300), 2, "1.0.0"),
    ("Kestrel", 44, "HUNTER", 4, 4, False, 96, ("Skinning", 140, 300), ("Herbalism", 120, 300), 1, ""),
    ("Lyra", 60, "MAGE", 3, 7, True, 0, ("Tailoring", 300, 300), ("Enchanting", 300, 300), 10, "1.0.0"),
    ("Maren", 38, "PRIEST", 4, 0, False, 5, ("Herbalism", 90, 300), ("Alchemy", 85, 300), 0, "1.0.0"),
    ("Nyx", 60, "ROGUE", 3, 8, False, 8, ("Engineering", 255, 300), ("Mining", 255, 300), 4, "1.0.0"),
    ("Orrin", 59, "PALADIN", 3, 9, True, 0, ("Blacksmithing", 230, 300), ("Mining", 230, 300), 3, "1.0.0"),
    ("Perrin", 33, "DRUID", 4, 2, False, 150, ("Herbalism", 75, 300), ("Skinning", 60, 300), 0, ""),
    ("Quill", 60, "WARLOCK", 2, 1, True, 0, ("Enchanting", 280, 300), ("Tailoring", 270, 300), 6, "1.0.0"),
    ("Rowan", 51, "SHAMAN", 3, 5, False, 27, ("Leatherworking", 190, 300), ("Skinning", 200, 300), 2, ""),
    ("Sable", 60, "ROGUE", 3, 3, False, 30, ("Alchemy", 300, 300), ("Herbalism", 275, 300), 5, "1.0.0"),
    ("Tamsin", 29, "MAGE", 4, 0, False, 240, ("Tailoring", 60, 300), ("", 0, 0), 0, ""),
    ("Ulric", 60, "WARRIOR", 2, 6, True, 0, ("Mining", 300, 300), ("Engineering", 240, 300), 5, "1.0.0"),
    ("Vesper", 56, "PRIEST", 3, 2, False, 70, ("Alchemy", 215, 300), ("Herbalism", 230, 300), 3, "1.0.0"),
    ("Wren", 60, "HUNTER", 3, 7, True, 0, ("Leatherworking", 255, 300), ("Skinning", 270, 300), 4, "1.0.0"),
    ("Yorick", 48, "WARLOCK", 4, 1, False, 11, ("Enchanting", 120, 300), ("Tailoring", 130, 300), 1, ""),
    ("Zephyr", 60, "DRUID", 3, 2, True, 0, ("Herbalism", 300, 300), ("Alchemy", 240, 300), 4, "1.0.0"),
    ("Ansel", 54, "PALADIN", 3, 0, False, 6, ("Mining", 215, 300), ("Blacksmithing", 200, 300), 2, "1.0.0"),
    ("Bram", 60, "WARRIOR", 3, 6, False, 14, ("Mining", 260, 300), ("Engineering", 190, 300), 3, ""),
    ("Cedric", 41, "MAGE", 4, 4, False, 180, ("Tailoring", 100, 300), ("", 0, 0), 0, ""),
]


PROF_IT = {"Blacksmithing": "Forgiatura", "Mining": "Estrazione", "Alchemy": "Alchimia", "Herbalism": "Erboristeria", "Tailoring": "Sartoria",
           "Enchanting": "Incantamento", "Engineering": "Ingegneria", "Skinning": "Scuoiatura", "Leatherworking": "Conceria"}
ZONES_IT = ["Roccavento", "Forgiardente", "Darnassus", "Silithus", "Tanaris", "Orsoinverno", "Steppe Ardenti", "Pestilandia Or.", "Un'Goro", "Orgrimmar"]


def loc_prof(n):
    return PROF_IT.get(n, n) if lib.LANG[0] == "itIT" else n


def zone_of(i):
    return (ZONES_IT if lib.LANG[0] == "itIT" else ZONES)[i]


def ranks():
    return RANKS_IT if lib.LANG[0] == "itIT" else RANKS


def last_online(online, h):
    if online:
        return f'<span class="green">{esc(T("ONLINE"))}</span>'
    if h < 1:
        return f'<span class="muted">{esc(T("LAST_LT_HOUR"))}</span>'
    if h < 24:
        return f'<span class="muted">{esc(T("AGO_HOURS", h))}</span>'
    return f'<span class="muted">{esc(T("AGO_DAYS", h // 24))}</span>'


def prof(p, muted=False):
    if not p[0]:
        return ""
    text = f"{loc_prof(p[0])} {p[1]}/{p[2]}"
    return f'<span class="{"muted" if muted else ""}">{esc(text)}</span>'


def roster_cols():
    return [(T("COL_NAME"), 118), (T("COL_LEVEL"), 36), (T("COL_CLASS"), 78), (T("COL_RANK"), 102), (T("COL_ZONE"), 106), (T("COL_LAST_ONLINE"), 94),
            (T("COL_PROF1"), 134), (T("COL_PROF2"), 134), (T("COL_LIKES"), 40), (T("COL_ADDON"), 48)]


def roster_row(m, i=0, prefix=""):
    n, lv, c, rk, z, on, h, p1, p2, likes, ver = m
    return [prefix + badge(c) + name(n, c), str(lv), f'<span style="color:{color_of(c)}">{esc(class_name(c))}</span>', esc(ranks()[rk]), esc(zone_of(z)),
            last_online(on, h), prof(p1, i % 3 == 2), prof(p2, i % 3 == 2), str(likes) if likes else "", f'<span class="green">{esc(ver)}</span>' if ver else ""]


def roster_toolbar(online=False, mains=False, grouped=False, count=None, shown=None, compact=False):
    total = len(MEMBERS)
    count = T("ROSTER_COUNT", shown or total, total)
    menus = "" if compact else (btn(T("COL_CLASS") + " v", small=True) + btn(T("COL_RANK") + " v", small=True)
                                + btn(T("FILTER_PROFESSION") + " v", small=True) + btn(T("COLUMNS"), small=True))
    return tools(chk(T("FILTER_ONLINE"), online), chk(T("FILTER_MAINS"), mains), chk(T("FILTER_GROUPED"), grouped), menus,
                 right="" if compact else f'<span class="muted small">{esc(count)}</span>')


def roster_body(rows, **kw):
    cols = roster_cols()
    return (f'<div style="position:relative;height:100%">{roster_toolbar(**kw.pop("toolbar", {}))}'
            f'<div style="padding-right:12px;position:relative">{table(cols, rows, **kw)}</div>{scrollbar(4, 110)}</div>')


@scene("accord-tab-roster", "The Accord tab in the guild window: a fifth tab under the game's four, and the Roster in its panel")
def s_accord_tab():
    rows = [roster_row(m, i) for i, m in enumerate(MEMBERS)]
    return full("roster", roster_body(rows, sort=0, sel=(3,)), peers=9, ago=1, search_text="")


@scene("roster-table", "Roster: sortable columns, filters, class-coloured names, professions, likes and who runs the addon")
def s_roster_sorted():
    ms = sorted(MEMBERS, key=lambda m: -m[1])
    rows = [roster_row(m, i) for i, m in enumerate(ms)]
    return full("roster", roster_body(rows, sort=1, desc=True, hover=(5,)), peers=9, ago=1)


@scene("roster-grouped", "Roster grouped by account: the main leads each player, a click on + shows the alts", )
def s_roster_grouped():
    rows, sel, alt = [], [], []
    plus = '<span class="gold" style="display:inline-block;width:14px">+</span>'
    minus = '<span class="gold" style="display:inline-block;width:14px">-</span>'
    mains = [("Aldric", 0, [("Aldrisa", 42, "PRIEST", 3, 0, False, 30, ("Tailoring", 120, 300), ("", 0, 0), 0, "1.0.0")]),
             ("Brynn", 1, [("Brynhild", 60, "WARLOCK", 3, 1, True, 0, ("Enchanting", 250, 300), ("Tailoring", 240, 300), 4, "1.0.0"),
                           ("Bryn", 28, "DRUID", 4, 2, False, 14, ("Herbalism", 60, 300), ("", 0, 0), 0, "1.0.0")]),
             ("Cora", 2, []), ("Dunstan", 3, [("Dunny", 35, "HUNTER", 4, 4, False, 48, ("Skinning", 80, 300), ("", 0, 0), 0, "1.0.0")]),
             ("Elowen", 4, [])]
    for n, idx, alts in mains:
        m = MEMBERS[[x[0] for x in MEMBERS].index(n)]
        rows.append(roster_row(m, 0, (minus if n == "Brynn" else plus) if alts else '<span style="display:inline-block;width:14px"></span>'))
        if n == "Brynn":
            for a in alts:
                alt.append(len(rows))
                rows.append(roster_row(a, 0, '<span style="display:inline-block;width:26px"></span>'))
    for m in MEMBERS[5:20]:
        rows.append(roster_row(m, 0, '<span style="display:inline-block;width:14px"></span>'))
    return full("roster", roster_body(rows, alt=tuple(alt), sel=(1,), toolbar={"grouped": True, "shown": len(rows)}), peers=9)


@scene("member-card", "Member card: details, professions and their source, the account's characters, contacts, likes, social index")
def s_member_card():
    ms = [roster_row(m, i) for i, m in enumerate(MEMBERS)]
    table_html = (f'<div style="position:absolute;left:0;top:0;bottom:0;width:560px;overflow:hidden">{roster_toolbar(compact=True)}'
                  f'<div style="position:relative;overflow:hidden;height:540px">{table(roster_cols()[:7], [r[:7] for r in ms], sel=(1,))}</div></div>')
    card = f'''<div style="position:absolute;right:0;top:0;bottom:0;width:340px;border-left:1px solid var(--line);padding:12px 14px;overflow:hidden;background:rgba(0,0,0,.25)">
      <div style="display:flex;align-items:center;gap:10px">{badge("MAGE", True)}<div><div style="font:700 17px/1.1 var(--font);color:{color_of("MAGE")}">Brynn</div>
      <div class="muted small">{esc(T("CARD_LEVEL", 60))} · Mage · {esc(T("CARD_MAIN"))}</div></div></div>
      <div class="sep"></div><h3>{esc(T("CARD_DETAILS"))}</h3>
      <div class="small">{esc(T("CARD_ZONE", zone_of(1)))} · {esc(T("CARD_ONLINE"))}<br>{esc(T("CARD_RANK", ranks()[1]))}<br>{esc(T("CARD_NOTE", "Alchemy orders: mail me first"))}<br>{esc(T("CARD_ADDON_VERSION", "1.0.0"))}</div>
      <div class="sep"></div><h3>{esc(T("CARD_PROFESSIONS"))}</h3>
      <div class="small"><span class="gold">Alchemy 285/300</span> <span class="muted">- {esc(T("CARD_SRC_NATIVE"))}</span><br><span class="gold">Herbalism 300/300</span> <span class="muted">- {esc(T("CARD_SRC_SHARED_AGE", T("AGO_HOURS", 2)))}</span></div>
      <div class="sep"></div><h3>{esc(T("CARD_ACCOUNT"))}</h3>
      <div class="small">{badge("MAGE")}<span style="color:{color_of("MAGE")}">Brynn</span> <span class="muted">({esc(T("CARD_MAIN"))}, 60)</span><br>
        {badge("WARLOCK")}<span style="color:{color_of("WARLOCK")}">Brynhild</span> <span class="muted">(60)</span><br>
        {badge("DRUID")}<span style="color:{color_of("DRUID")}">Bryn</span> <span class="muted">(28)</span></div>
      <div class="sep"></div><h3>{esc(T("CARD_CONTACTS"))}</h3>
      <div class="small">{esc(T("CARD_BATTLETAG", "Brynn#2417"))}<br>{esc(T("CARD_DISCORD_NATIVE", "brynn_arcane"))}<br><span class="blue">{esc(T("CARD_ADD_FRIEND"))}</span></div>
      <div class="sep"></div><h3>{esc(T("CARD_LIKES"))}</h3>
      <div class="small">{esc(T("CARD_LIKES_TOTAL", 11))}<br><span class="blue">{esc(T("CARD_LIKE"))}</span></div>
      <div class="sep"></div><h3>{esc(T("SOC_SECTION"))}</h3>
      <div class="small">{esc(T("SOC_INDEX", 68))}<br>{esc(T("SOC_EFFECTIVE", 6.4, 38))}</div></div>'''
    return full("roster", f'<div style="position:relative;height:100%">{table_html}{card}</div>', peers=9)


@scene("professions-recipes", "Professions: a guildmate's recipe list with its source and age, search, categories and Request craft")
def s_recipes():
    recipes = [("Elixir of Fortitude", 2, "optimal"), ("Greater Healing Potion", 3, "optimal"), ("Elixir of Agility", 3, "medium"), ("Lesser Invisibility Potion", 2, "medium"),
               ("Oil of Immolation", 3, "easy"), ("Mana Potion", 1, "easy"), ("Transmute: Iron to Gold", 4, "optimal"), ("Philosopher's Stone", 4, "medium"),
               ("Flask of Petrification", 4, "easy"), ("Elixir of Detect Lesser Invisibility", 2, "trivial"), ("Swiftness Potion", 1, "trivial"),
               ("Major Healing Potion", 3, "optimal"), ("Greater Fire Protection Potion", 3, "medium"), ("Elixir of the Mongoose", 4, "optimal"),
               ("Limited Invulnerability Potion", 3, "easy"), ("Nature Protection Potion", 3, "medium"), ("Frost Protection Potion", 3, "medium"), ("Shadow Protection Potion", 3, "easy"),
               ("Elixir of Brute Force", 3, "optimal"), ("Elixir of Giants", 3, "medium"), ("Mageblood Potion", 2, "easy"), ("Free Action Potion", 3, "optimal"), ("Rejuvenation Potion", 2, "trivial"),
               ("Elixir of Superior Defense", 3, "medium"), ("Gift of Arthas", 2, "easy"), ("Elixir of Shadow Power", 3, "optimal")]
    col = {"optimal": "#ff8040", "medium": "#ffff00", "easy": "#40bf40", "trivial": "#808080"}
    rows = ""
    for i, (n, q, d) in enumerate(recipes):
        you = f'<span class="muted small"> - {esc(T("RV_YOU_KNOW"))}</span>' if i in (1, 5, 9) else ""
        req = btn(T("CR_REQUEST"), small=True) if i in (0, 1, 6) else ""
        rows += f'<tr><td style="width:34px">{pic(i + 2, q)}</td><td style="color:{col[d]}">{esc(n)}{you}</td><td style="width:130px;text-align:right">{req}</td></tr>'
    body = f'''<div style="position:relative;height:100%"><div class="pad" style="padding-bottom:4px"><div style="display:flex;align-items:center;gap:10px">{btn(T("RV_BACK"), small=True)}
      <h2 style="margin:0">{esc(T("RV_TITLE", "Brynn", "Alchemy 285/300"))}</h2><span class="grow" style="flex:1"></span>{btn(T("CR_BUTTON"), small=True)}</div>
      <div class="muted small" style="margin-top:4px">{esc(T("RV_SRC_NATIVE_AGE", T("AGO_MINUTES", 4)))} · {esc(T("RV_COUNT", 26, 131))} · {btn(T("RV_CATEGORY") + ": " + T("RV_CAT_ALL"), small=True)}</div></div>
      <div style="padding:0 18px 0 8px;position:relative"><table class="tbl" style="margin-top:6px">{rows}</table></div>{scrollbar(4, 150)}
      {tip(470, 150, '<div class="gold" style="font-size:14px">Greater Healing Potion</div><div class="small">Requires Alchemy (215)</div><div class="green small" style="margin-top:4px">Restores 455 to 585 health.</div><div class="muted small" style="margin-top:6px">Needs: 1 Mountain Silversage, 1 Crystal Vial</div>', 250)}</div>'''
    return full("professions", body, search_text="potion", peers=9)


@scene("professions-who-can-craft", "Who can craft: search an item or recipe and see the guildmates who know it, online first")
def s_craft():
    def rowset(title, qn, crafters):
        out = f'<tr><td colspan="5" style="height:24px;background:rgba(230,190,64,.08)">{pic(qn, 3)}<b class="gold">{esc(title)}</b> <span class="muted small">{esc(T("CR_CRAFTERS", len(crafters)))}</span></td></tr>'
        for n, c, on, p, src, who in crafters:
            out += (f'<tr><td style="width:24px"></td><td style="width:150px">{badge(c)}{name(n, c)}</td><td style="width:140px">{esc(p)}</td>'
                    f'<td class="muted small" style="width:200px">{esc(src)}</td><td style="text-align:right">'
                    f'{"" if not on else btn(T("CR_REQUEST"), small=True)}{"" if on else chip("offline", "grey")}</td></tr>')
        return out
    rows = rowset("Greater Healing Potion", 5, [("Brynn", "MAGE", True, "Alchemy 285/300", T("RV_SRC_NATIVE"), 0), ("Sable", "ROGUE", False, "Alchemy 300/300", T("RV_SRC_SHARED_AGE", T("AGO_HOURS", 6)), 0),
                                                ("Vesper", "PRIEST", False, "Alchemy 215/300", T("RV_SRC_SHARED_AGE", T("AGO_DAYS", 2)), 0)])
    rows += rowset("Major Healing Potion", 6, [("Brynn", "MAGE", True, "Alchemy 285/300", T("RV_SRC_NATIVE"), 0), ("Sable", "ROGUE", False, "Alchemy 300/300", T("RV_SRC_SHARED_AGE", T("AGO_HOURS", 6)), 0)])
    rows += rowset("Superior Healing Potion", 3, [("Brynn", "MAGE", True, "Alchemy 285/300", T("RV_SRC_NATIVE"), 0), ("Lyra", "MAGE", True, "Alchemy 240/300", T("RV_SRC_NATIVE"), 0), ("Zephyr", "DRUID", True, "Alchemy 240/300", T("RV_SRC_NATIVE"), 0)])
    rows += rowset("Healing Potion", 7, [("Elowen", "DRUID", False, "Alchemy 190/300", T("RV_SRC_SHARED_AGE", T("AGO_DAYS", 1)), 0), ("Maren", "PRIEST", False, "Alchemy 85/300", T("RV_SRC_SHARED_AGE", T("AGO_DAYS", 4)), 0)])
    body = f'''<div class="pad" style="padding-bottom:4px"><h2>{esc(T("CR_TITLE"))}</h2><div class="muted small">{esc(T("CR_COUNT", 3))} · {chk(T("CR_ONLINE_ONLY"))}</div></div>
      <div style="padding:0 18px 0 8px;position:relative"><table class="tbl" style="margin-top:6px"><colgroup><col style="width:28px"><col style="width:150px"><col style="width:150px"><col style="width:230px"><col></colgroup>{rows}</table></div>'''
    return full("professions", body, search_text="healing potion", peers=9)
