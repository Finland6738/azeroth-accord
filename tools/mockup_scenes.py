"""Every case of the interface as a design preview (see tools/make_mockups.py), part 1: the Accord tab, the Roster, the member
card, professions and recipes, in the new look. One function per image, registered with @scene(file name, caption, lang, theme).
A scene returns the HTML that goes inside the 1200x720 stage. All interface texts come from the addon's locale tables; the
characters, guild and items are invented."""
from mockup_lib import *  # noqa: F401,F403
import mockup_lib as lib

SCENES = []


def scene(name, caption, lang="enUS", theme="nebula"):
    def deco(fn):
        SCENES.append((name, caption, fn, lang, theme))
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
    return [(T("COL_NAME"), 126), (T("COL_LEVEL"), 44), (T("COL_CLASS"), 84), (T("COL_RANK"), 104), (T("COL_ZONE"), 124), (T("COL_LAST_ONLINE"), 96),
            (T("COL_PROF1"), 156), (T("COL_PROF2"), 156), (T("COL_LIKES"), 52), (T("COL_ADDON"), 64)]


def roster_row(m, i=0, prefix=""):
    n, lv, c, rk, z, on, h, p1, p2, likes, ver = m
    return [prefix + badge(c) + name(n, c), str(lv), f'<span class="cn" style="color:{color_of(c)}">{esc(class_name(c))}</span>', esc(ranks()[rk]), esc(zone_of(z)),
            last_online(on, h), prof(p1, i % 3 == 2), prof(p2, i % 3 == 2), str(likes) if likes else "", f'<span class="green">{esc(ver)}</span>' if ver else ""]


def roster_toolbar(online=False, mains=False, grouped=False, count=None, shown=None, compact=False):
    """The Roster's toolbar: three chips, three lists (Select), the column chooser, and the count at the right."""
    total = len(MEMBERS)
    count = T("ROSTER_COUNT", shown or total, total)
    menus = "" if compact else (select(T("COL_CLASS")) + select(T("COL_RANK")) + select(T("FILTER_PROFESSION")) + btn(T("COLUMNS"), small=True, extra='style="height:28px;border-radius:8px;font-size:13px"'))
    return tools(chk(T("FILTER_ONLINE"), online), chk(T("FILTER_MAINS"), mains), chk(T("FILTER_GROUPED"), grouped), menus,
                 right="" if compact else f'<span class="muted small">{esc(count)}</span>')


def roster_body(rows, **kw):
    cols = roster_cols()
    return (f'<div class="rel">{roster_toolbar(**kw.pop("toolbar", {}))}'
            f'<div style="position:relative">{table(cols, rows, **kw)}{scrollbar(4, 110)}</div></div>')


@scene("accord-tab-roster", "The Accord tab in the guild window: a fifth tab under the game's four, the tabs of the views along the top, and the Roster")
def s_accord_tab():
    rows = [roster_row(m, i) for i, m in enumerate(MEMBERS)]
    return full("roster", roster_body(rows, sort=0, sel=(3,)), peers=9, ago=1, search_text="")


@scene("roster-table", "Roster: sortable columns, filters, class squares, professions, likes and who runs the addon")
def s_roster_sorted():
    ms = sorted(MEMBERS, key=lambda m: -m[1])
    rows = [roster_row(m, i) for i, m in enumerate(ms)]
    return full("roster", roster_body(rows, sort=1, desc=True, hover=(5,)), peers=9, ago=1)


@scene("roster-aurora", "The Roster in the light theme Aurora (the third of the Appearance card is Accord)", theme="aurora")
def s_roster_aurora():
    rows = [roster_row(m, i) for i, m in enumerate(MEMBERS)]
    return full("roster", roster_body(rows, sort=0, sel=(3,), toolbar={"online": True}), peers=9, ago=1, search_text="")


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


def _box(title, inner, count=None):
    """One box of the member card: a title with its count, then the lines."""
    cnt = f'<span class="muted small" style="margin-left:auto">{count}</span>' if count is not None else ""
    return (f'<div class="card sm" style="margin-bottom:8px;padding:10px 14px"><div style="display:flex;align-items:center;margin-bottom:6px"><h2 style="margin:0">{esc(title)}</h2>{cnt}</div>'
            f'<div class="small" style="line-height:1.55;color:var(--text-2)">{inner}</div></div>')


def member_card(clipped=True):
    """The member card as the Roster shows it beside the table (Card.WIDTH 290), for Brynn."""
    link = lambda t: f'<span class="gold">{esc(t)}</span>'  # noqa: E731
    head = (f'<div class="card sm" style="margin-bottom:8px;padding:12px 14px"><div style="display:flex;align-items:center;gap:12px">{badge("MAGE", True)}'
            f'<div><div style="font:600 16px/1.1 var(--body);" class="cn"><span style="color:{color_of("MAGE")}">Brynn</span></div>'
            f'<div class="muted small" style="margin-top:3px">{esc(T("CARD_LEVEL", 60))} · {esc(class_name("MAGE"))}</div></div></div>'
            f'<div style="display:flex;gap:6px;margin-top:10px;flex-wrap:wrap">{pill(T("CARD_ONLINE"), "ok")}{pill(T("CARD_MAIN"), "accent")}{pill("1.0.0")}</div></div>')
    details = _box(T("CARD_DETAILS"), f'{esc(T("CARD_ZONE", zone_of(1)))}<br>{esc(T("CARD_RANK", ranks()[1]))}<br>{esc(T("CARD_NOTE", "Alchemy orders: mail me first"))}<br>{esc(T("CARD_ADDON_VERSION", "1.0.0"))}')
    profs = _box(T("CARD_PROFESSIONS"), f'<span style="color:var(--text-1)">{esc(loc_prof("Alchemy"))} 285/300</span> <span class="muted">- {esc(T("CARD_SRC_NATIVE"))}</span><br>'
                 f'<span style="color:var(--text-1)">{esc(loc_prof("Herbalism"))} 300/300</span> <span class="muted">- {esc(T("CARD_SRC_SHARED_AGE", T("AGO_HOURS", 2)))}</span>', 2)
    acct = _box(T("CARD_ACCOUNT"), f'{badge("MAGE")}{name("Brynn", "MAGE")} <span class="muted">({esc(T("CARD_MAIN"))}, 60)</span><br>{badge("WARLOCK")}{name("Brynhild", "WARLOCK")} <span class="muted">(60)</span><br>'
                f'{badge("DRUID")}{name("Bryn", "DRUID")} <span class="muted">(28)</span>', 3)
    contacts = _box(T("CARD_CONTACTS"), f'{esc(T("CARD_BATTLETAG", "Brynn#2417"))}<br>{esc(T("CARD_DISCORD_NATIVE", "brynn_arcane"))}<br>{link(T("CARD_ADD_FRIEND"))}')
    likes = _box(T("CARD_LIKES"), f'{esc(T("CARD_LIKES_TOTAL", 11))}<br>{link(T("CARD_LIKE"))}')
    social = _box(T("SOC_SECTION"), f'{esc(T("SOC_INDEX", 68))}<br>{esc(T("SOC_EFFECTIVE", 6.4, 38))}')
    return head + details + profs + acct + contacts + likes + social


def _card_scene(theme_scene=None):
    ms = [roster_row(m, i) for i, m in enumerate(MEMBERS)]
    table_html = (f'<div style="position:absolute;left:0;top:0;bottom:0;width:704px;overflow:hidden">{roster_toolbar(compact=True)}'
                  f'<div style="position:relative">{table(roster_cols()[:7], [r[:7] for r in ms], sel=(1,))}</div></div>')
    card = f'<div style="position:absolute;right:0;top:0;bottom:0;width:290px;overflow:hidden">{member_card()}</div>'
    return full("roster", f'<div class="rel">{table_html}{card}</div>', peers=9)


@scene("member-card", "Member card: details, professions and their source, the account's characters, contacts, likes, social index")
def s_member_card():
    return _card_scene()


@scene("member-card-accord", "The member card in the Accord theme (the colours of the addon's logo)", theme="accord")
def s_member_card_accord():
    return _card_scene()


def _recipe_head(title_html, source, count=None, craft=True):
    return (f'<div style="display:flex;align-items:center;gap:8px;height:32px">{btn(T("RV_BACK"), "ghost")}{btn(T("CR_BUTTON"), "") if craft else ""}'
            f'<span style="font:600 16px/1 var(--body);margin-left:8px">{title_html}</span></div>'
            f'<div class="muted small" style="margin:8px 0 0 2px">{source}</div>')


@scene("professions-recipes", "Professions: a guildmate's recipe list with its source and age, a category list, difficulty colours and Request craft")
def s_recipes():
    recipes = [("Elixir of Fortitude", 2, "optimal"), ("Greater Healing Potion", 3, "optimal"), ("Elixir of Agility", 3, "medium"), ("Lesser Invisibility Potion", 2, "medium"),
               ("Oil of Immolation", 3, "easy"), ("Mana Potion", 1, "easy"), ("Transmute: Iron to Gold", 4, "optimal"), ("Philosopher's Stone", 4, "medium"),
               ("Flask of Petrification", 4, "easy"), ("Elixir of Detect Lesser Invisibility", 2, "trivial"), ("Swiftness Potion", 1, "trivial"),
               ("Major Healing Potion", 3, "optimal"), ("Greater Fire Protection Potion", 3, "medium"), ("Elixir of the Mongoose", 4, "optimal"),
               ("Limited Invulnerability Potion", 3, "easy"), ("Nature Protection Potion", 3, "medium"), ("Frost Protection Potion", 3, "medium"), ("Shadow Protection Potion", 3, "easy"),
               ("Elixir of Brute Force", 3, "optimal"), ("Elixir of Giants", 3, "medium"), ("Mageblood Potion", 2, "easy"), ("Free Action Potion", 3, "optimal"), ("Rejuvenation Potion", 2, "trivial")]
    col = {"optimal": "#ff8040", "medium": "#ffff00", "easy": "#40bf40", "trivial": "#808080"}
    rows = ""
    for i, (n, q, d) in enumerate(recipes):
        status = f'<span class="green">{esc(T("RV_YOU_KNOW"))}</span>' if i in (1, 5, 9) else ""
        req = btn(T("CR_REQUEST"), small=True) if i in (0, 1, 6) else ""
        rows += (f'<tr class="{"hover" if i == 1 else ""}"><td style="width:34%">{pic(i + 2, q)}<span style="color:{col[d]}">{esc(n)}</span></td><td></td>'
                 f'<td class="num" style="width:140px">{status}</td><td style="width:116px;text-align:right">{req}</td></tr>')
    head = (f'<table class="tbl"><thead><tr><th style="width:34%">{esc(T("RV_COL_RECIPE"))}</th><th>{esc(T("RV_COL_DETAILS"))}</th><th style="width:140px;text-align:right">{esc(T("RV_COL_STATUS"))}</th><th style="width:116px"></th></tr></thead></table>')
    body = (f'<div class="rel">{_recipe_head("Brynn - " + esc(loc_prof("Alchemy")) + " 285/300", esc(T("RV_SRC_NATIVE_AGE", T("AGO_MINUTES", 4))))}'
            f'<div style="display:flex;align-items:center;gap:8px;height:40px;margin-top:6px">{select(T("RV_CATEGORY") + ": " + T("RV_CAT_ALL"), 220, True)}<span class="grow"></span><span class="muted small">{esc(T("RV_COUNT", 23, 131))}</span></div>'
            f'<div style="position:relative">{head}<table class="tbl" style="margin-top:0"><tbody>{rows}</tbody></table>{scrollbar(4, 150)}</div>'
            f'{tip(470, 190, "<div class=gold style=font-size:14px>Greater Healing Potion</div><div class=small>Requires Alchemy (215)</div><div class=green style=margin-top:4px>Restores 455 to 585 health.</div><div class=muted style=margin-top:6px>Needs: 1 Mountain Silversage, 1 Crystal Vial</div>", 250)}</div>')
    return full("professions", body, search_text="potion", peers=9)


@scene("professions-who-can-craft", "Who can craft: search an item or recipe and see the guildmates who know it, online first")
def s_craft():
    def rowset(title, qn, crafters):
        out = (f'<tr><td style="width:34%">{pic(qn, 3)}<span class="gold">{esc(title)}</span></td><td></td>'
               f'<td class="num muted" style="width:140px">{esc(T("CR_CRAFTERS", len(crafters)))}</td><td style="width:116px"></td></tr>')
        for n, c, on, p, src, who in crafters:
            out += (f'<tr><td style="width:34%;padding-left:30px">{name(n, c)}</td><td class="muted">{esc(p)} · {esc(src)}</td>'
                    f'<td class="num green" style="width:140px">{esc(T("ONLINE")) if on else ""}</td>'
                    f'<td style="width:116px;text-align:right">{btn(T("CR_REQUEST"), small=True) if on else ""}</td></tr>')
        return out
    ago = lambda k, n: T("RV_SRC_SHARED_AGE", T(k, n))  # noqa: E731
    rows = rowset("Greater Healing Potion", 5, [("Brynn", "MAGE", True, "Alchemy 285/300", T("RV_SRC_NATIVE"), 0), ("Sable", "ROGUE", False, "Alchemy 300/300", ago("AGO_HOURS", 6), 0),
                                                ("Vesper", "PRIEST", False, "Alchemy 215/300", ago("AGO_DAYS", 2), 0)])
    rows += rowset("Major Healing Potion", 6, [("Brynn", "MAGE", True, "Alchemy 285/300", T("RV_SRC_NATIVE"), 0), ("Sable", "ROGUE", False, "Alchemy 300/300", ago("AGO_HOURS", 6), 0)])
    rows += rowset("Superior Healing Potion", 3, [("Brynn", "MAGE", True, "Alchemy 285/300", T("RV_SRC_NATIVE"), 0), ("Lyra", "MAGE", True, "Alchemy 240/300", T("RV_SRC_NATIVE"), 0), ("Zephyr", "DRUID", True, "Alchemy 240/300", T("RV_SRC_NATIVE"), 0)])
    rows += rowset("Healing Potion", 7, [("Elowen", "DRUID", False, "Alchemy 190/300", ago("AGO_DAYS", 1), 0), ("Maren", "PRIEST", False, "Alchemy 85/300", ago("AGO_DAYS", 4), 0)])
    head = (f'<table class="tbl"><thead><tr><th style="width:34%">{esc(T("RV_COL_RECIPE"))}</th><th>{esc(T("RV_COL_DETAILS"))}</th><th style="width:140px;text-align:right">{esc(T("RV_COL_STATUS"))}</th><th style="width:116px"></th></tr></thead></table>')
    body = (f'<div class="rel"><div style="display:flex;align-items:center;gap:8px;height:32px">{btn(T("RV_BACK"), "ghost")}{btn(T("CR_BUTTON"), "primary")}<span style="font:600 16px/1 var(--body);margin-left:8px">{esc(T("CR_TITLE"))}</span></div>'
            f'<div class="muted small" style="margin:8px 0 0 2px">{esc(T("CR_COUNT", 3))}</div>'
            f'<div style="display:flex;align-items:center;gap:8px;height:40px;margin-top:6px">{chk(T("CR_ONLINE_ONLY"))}</div>'
            f'<div style="position:relative">{head}<table class="tbl"><tbody>{rows}</tbody></table></div></div>')
    return full("professions", body, search_text="healing potion", peers=9)
