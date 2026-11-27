"""Every case of the interface as a design preview, part 2: Reputation (likes, social index, group map, someone new), the guild
bank, Settings, Info and diagnostics, the standalone window and the Italian interface, in the new look. Registered after the scenes
of part 1 (tools/mockup_scenes.py). The data is invented; every text is read from the addon's locale tables."""
import math

from mockup_lib import *  # noqa: F401,F403
import mockup_lib as lib
from mockup_scenes import (scene, MEMBERS, ranks, roster_cols, roster_row, roster_toolbar, zone_of, loc_prof, PROF_IT)  # noqa: F401


def mode_bar(labels, on, extra=""):
    """The "Show" menu of a view's modes (Widgets.ModeMenu, M13.7: no third row of navigation): its label and the mode chosen."""
    return tools(f'<span style="font:500 13px/1 var(--body);color:var(--text-2)">{esc(T("NAV_SHOW"))}</span>', select(labels[on], 200, value=True), right=extra)


# =====================================================================================================================
# Reputation
# =====================================================================================================================
def rep_modes(on, officer=True):
    labels = [T("REP_MODE_LIKES"), T("REP_MODE_SOCIAL")] + ([T("REP_MODE_GROUPS")] if officer else []) + [T("REP_MODE_NEW")]
    return mode_bar(labels, on)


def likes_rows(people, kinds, limit=22):
    rows = ""
    for i, m in enumerate(people[:limit]):
        n, c = m[0], m[2]
        kind = kinds.get(n, ("btn", None, None))
        if kind[0] == "btn":
            act = heart()
        elif kind[0] == "confirm":
            act = btn(T("REP_CONFIRM"), small=True, extra='style="width:100px"')
        else:
            act = f'<span class="{kind[2]}">{esc(T(kind[1]))}</span>'
        chars = f'<span class="muted small">{esc(T("REP_CHARS", 3))}</span>' if n in ("Brynn", "Aldric", "Dunstan") else ""
        rows += (f'<tr><td style="width:46px" class="muted">{i + 1}</td><td style="width:170px">{badge(c)}{name(n, c)}</td>'
                 f'<td style="width:110px">{chars}</td><td style="width:80px;color:var(--accent-text)" class="mono">{m[9]}</td><td>{act}</td></tr>')
    return rows


LIKE_STATES = {"Aldric": ("state", "REP_LIKED", "green"), "Cora": ("state", "REP_PENDING", "grey"), "Lyra": ("confirm", None, None), "Fenwick": ("state", "REP_YOU", "grey")}


def likes_body(limit=22, scroll=True):
    people = sorted([m for m in MEMBERS if m[9] > 0], key=lambda m: -m[9])
    head = (f'<table class="tbl"><thead><tr><th style="width:46px"></th><th style="width:170px" class="sorted">{esc(T("REP_COL_NAME"))}</th><th style="width:110px"></th>'
            f'<th style="width:80px" class="sorted">{esc(T("REP_COL_LIKES"))}</th><th></th></tr></thead></table>')
    return (f'<div class="rel">{rep_modes(0)}<div class="muted small" style="margin:0 0 8px 2px">{esc(T("REP_LIKES_EXPLAIN"))}</div>'
            f'<div style="position:relative">{head}<table class="tbl tall"><tbody>{likes_rows(people, LIKE_STATES, limit)}</tbody></table>{scrollbar(70, 90) if scroll else ""}</div></div>')


@scene("reputation-likes", "Reputation: likes, one row per player; Like (a second click confirms), pending, liked and you")
def s_likes():
    return full("reputation", likes_body(), search_text="", peers=9)


@scene("reputation-social-index", "Reputation, Social: your own index, what it measures, and (officers) every player's index")
def s_social():
    own = card(f'<h2>{esc(T("SOC_YOURS"))}</h2><div style="font:600 28px/1.2 var(--mono);color:var(--accent-text)">68 <span class="muted" style="font-size:14px">/ 100</span></div>'
               f'<div class="bar" style="margin:6px 0 10px"><i style="width:68%"></i></div>'
               f'<div class="small" style="color:var(--text-2)">{esc(T("SOC_EFFECTIVE", 6.4, 38))}<br>{esc(T("SOC_DISTINCT", 17))}<br><span class="muted">{esc(T("SOC_MINUTES", T("SOC_HOURS", 14.2)))}</span></div>'
               f'<div class="small" style="margin-top:10px;color:var(--text-2)">{esc(T("SOC_TOP"))}<br>' + "".join(f'<span class="muted">{esc(T("SOC_TOP_LINE", n, p))}</span><br>' for n, p in (("Brynn", 24), ("Dunstan", 18), ("Lyra", 14), ("Fenwick", 11), ("Cora", 9))) + '</div>',
               "width:340px;padding:18px 22px")
    explain = card(f'<h2>{esc(T("SOC_TIP_TITLE"))}</h2><div class="small muted">{esc(T("SOC_TIP_1"))}<br><br>{esc(T("SOC_TIP_2"))}<br><br>{esc(T("SOC_TIP_3"))}</div>', "width:340px;margin-top:12px;padding:18px 22px")
    people = [("Lyra", "MAGE", 91, 9.8, 29), ("Brynn", "MAGE", 84, 8.6, 25), ("Dunstan", "PALADIN", 77, 7.5, 22), ("Fenwick", "ROGUE", 68, 6.4, 17), ("Aldric", "WARRIOR", 61, 5.8, 21),
              ("Cora", "PRIEST", 55, 5.1, 14), ("Hollis", "SHAMAN", 49, 4.4, 12), ("Ulric", "WARRIOR", 44, 3.9, 11), ("Zephyr", "DRUID", 38, 3.2, 9), ("Orrin", "PALADIN", 30, 2.6, 8),
              ("Wren", "HUNTER", 24, 2.0, 7), ("Quill", "WARLOCK", 0, 0, 0)]
    rows = ""
    for n, c, idx, eff, part in people:
        txt = T("SOC_LIST_ROW", idx, eff, part) if idx else T("SOC_LIST_LOW", T("SOC_HOURS", 3.4))
        rows += (f'<div style="height:28px;line-height:28px;border-top:1px solid var(--border-subtle);{"color:var(--text-3)" if not idx else ""}">{badge(c)}{name(n, c)}'
                 f'<span style="float:right" class="small muted">{esc(txt)}</span></div>')
    lst = card(f'<h2>{esc(T("SOC_LIST_TITLE"))}</h2><div class="muted small" style="margin-bottom:8px">{esc(T("SOC_LIST_NOTE"))}</div>{rows}', "width:560px;padding:18px 22px")
    body = f'<div class="rel">{rep_modes(1)}<div style="display:flex;gap:16px;align-items:flex-start"><div>{own}{explain}</div>{lst}</div></div>'
    return full("reputation", body, peers=9)


@scene("reputation-group-map", "Reputation, Groups (officers): how mixed the guild is, and its communities as circles of players")
def s_groups():
    groups = [(210, 120, 62, "var(--accent)", 9), (520, 105, 48, "var(--neon)", 7), (360, 190, 34, "var(--ok)", 5), (630, 200, 36, "var(--warn)", 5)]
    dots, links = "", ""
    centers = []
    for gx, gy, rad, col, n in groups:
        centers.append((gx, gy))
        for k in range(n):
            a = 2 * math.pi * k / n
            r = rad * (0.45 + 0.4 * ((k * 7) % 5) / 5)
            dots += f'<circle cx="{gx + r * math.cos(a):.1f}" cy="{gy + r * math.sin(a):.1f}" r="5" fill="{col}" stroke="#000" stroke-opacity=".4"/>'
        dots += f'<circle cx="{gx}" cy="{gy}" r="{rad + 10}" fill="{col}" fill-opacity=".08" stroke="{col}" stroke-opacity=".55" stroke-dasharray="3 4"/>'
    for (a, b) in ((0, 1), (0, 2), (1, 3), (2, 3), (1, 2)):
        links += f'<line x1="{centers[a][0]}" y1="{centers[a][1]}" x2="{centers[b][0]}" y2="{centers[b][1]}" stroke="var(--border-strong)" stroke-width="2"/>'
    canvas = f'<svg width="950" height="256" style="background:var(--surface-2);border-radius:12px;display:block">{links}{dots}</svg>'
    lines = [(T("MAP_MIXING_MEDIUM", 0.41), "head"), (T("MAP_SUMMARY", 26, 4, T("SOC_HOURS", 211.3)), "muted"),
             (T("MAP_GROUP", 1, 9, "Aldric, Brynn, Dunstan, Lyra, Fenwick, Cora" + T("MAP_MORE", 3)), ""), (T("MAP_GROUP_TIME", T("SOC_HOURS", 74.5), T("SOC_HOURS", 21.1)), "muted"),
             (T("MAP_GROUP", 2, 7, "Hollis, Ulric, Wren, Zephyr, Orrin, Quill" + T("MAP_MORE", 1)), ""), (T("MAP_GROUP_TIME", T("SOC_HOURS", 38.0), T("SOC_HOURS", 17.2)), "muted"),
             (T("MAP_GROUP", 3, 5, "Elowen, Garrick, Isolde, Sable, Vesper"), ""), (T("MAP_GROUP_TIME", T("SOC_HOURS", 12.6), T("SOC_HOURS", 9.8)), "muted"),
             (T("MAP_GROUP", 4, 5, "Joren, Kestrel, Maren, Nyx, Rowan"), ""), (T("MAP_GROUP_TIME", T("SOC_HOURS", 9.1), T("SOC_HOURS", 14.0)), "muted")]
    rows = "".join(f'<div class="{"gold" if k == "head" else "muted" if k == "muted" else ""} {"small" if k == "muted" else ""}" style="height:20px;line-height:20px;{"font-weight:600;font-size:14px;" if k == "head" else ""}">{esc(t)}</div>' for t, k in lines)
    body = f'<div class="rel">{rep_modes(2)}{card(canvas + f"<div style=margin-top:12px>{rows}</div>", "padding:16px 20px")}</div>'
    return full("reputation", body, peers=9)


@scene("reputation-someone-new", "Reputation, Someone new: guildmates online you have played with least; Whisper and Invite are your clicks")
def s_new():
    rows = ""
    data = [("Hollis", "SHAMAN", 60, 5, "Winterspring"), ("Quill", "WARLOCK", 60, 0, "Ironforge"), ("Orrin", "PALADIN", 59, 8, "Orgrimmar"), ("Wren", "HUNTER", 60, 12, "E. Plaguelands"),
            ("Zephyr", "DRUID", 60, 21, "Darnassus"), ("Ulric", "WARRIOR", 60, 27, "Burning Steppes")]
    for n, c, lv, mins, z in data:
        together = T("NEW_NEVER") if mins == 0 else T("NEW_MINUTES", mins)
        rows += (f'<tr><td style="width:190px">{badge(c)}{name(n, c)}</td><td class="muted">{esc(T("NEW_DETAIL", lv, z, together))}</td>'
                 f'<td style="width:206px;text-align:right">{btn(T("NEW_WHISPER"), "outlined", small=True, extra="style=width:90px")} {btn(T("NEW_INVITE"), small=True, extra="style=width:90px")}</td></tr>')
    body = (f'<div class="rel">{rep_modes(3)}<div class="muted small" style="margin:0 0 8px 2px">{esc(T("NEW_EXPLAIN", 5, 30))}</div>'
            f'<table class="tbl tall"><tbody>{rows}</tbody></table></div>')
    return full("reputation", body, peers=9)


# =====================================================================================================================
# Bank
# =====================================================================================================================
TABS = ["Consumables", "Materials", "Gear", "Recipes", "Officers"]
ITEMS = [("Linen Cloth", 1), ("Wool Cloth", 1), ("Silk Cloth", 2), ("Mageweave Cloth", 2), ("Runecloth", 2), ("Light Leather", 1), ("Iron Bar", 1), ("Mithril Bar", 2),
         ("Thorium Bar", 3), ("Peacebloom", 1), ("Firebloom", 2), ("Sungrass", 2), ("Mountain Silversage", 3), ("Heavy Leather", 1), ("Crystal Vial", 1), ("Greater Healing Potion", 2),
         ("Major Mana Potion", 3), ("Elixir of the Mongoose", 3), ("Flask of the Titans", 4), ("Black Lotus", 4), ("Arcane Crystal", 3), ("Righteous Orb", 3), ("Large Brilliant Shard", 3)]


def bank_modes(on, badge_n=None, officer=True):
    labels = [T("BANK_MODE_TABS"), T("BANK_MODE_ITEMS"), T("BANK_MODE_LOG"), T("BANK_MODE_DONATIONS"), T("BANK_MODE_MONEY"),
              T("BANK_MODE_REQUESTS")] + ([T("BANK_MODE_INBOX") + (f" ({badge_n})" if badge_n else "")] if officer else [])
    return mode_bar(labels, on)


def bank_frame(on, inner, badge_n=None, **kw):
    # every mode sits in one card under the chips
    body = f'<div class="card" style="position:absolute;left:0;right:0;top:44px;bottom:0;padding:14px;overflow:hidden">{inner}</div>'
    return full("bank", f'<div class="rel">{bank_modes(on, badge_n)}{body}</div>', badge=badge_n, **kw)


QUALITY_COLOR = {1: "#ffffff", 2: "#1eff00", 3: "#4a9bff", 4: "#c46bff"}


def bank_tabs_body(tabs_lang=None):
    grid = ""
    for r in range(7):
        row = ""
        for c in range(14):
            k = r * 14 + c
            if k < 78 and (k * 7) % 11 != 3:
                row += slot(k + 3, 1 + (k * 5) % 40 if k % 3 else 1, 2 if k % 9 == 0 else 3 if k % 17 == 0 else 4 if k == 31 else 1)
            else:
                row += slot()
        grid += f'<div style="display:flex;gap:4px;margin-bottom:4px">{row}</div>'
    tabbtns = "".join(chip(t, "sel" if i == 0 else "", small=True) + " " for i, t in enumerate(TABS[:4]))
    tipbox = tip(600, 150, '<div class="gold" style="font-size:14px">Flask of the Titans</div><div class="small" style="margin-top:2px">Binds when picked up</div>'
                 '<div class="green small" style="margin-top:4px">Use: Increases your maximum health by 1200 for 2 hours.</div>'
                 f'<div class="muted small" style="margin-top:6px">{esc(T("BANK_TAB_COUNT", TABS[0], 4))}</div>', 280)
    return (f'<div style="display:flex;gap:8px;margin-bottom:10px">{tabbtns}</div>'
            f'<div style="margin-bottom:4px"><b>{esc(T("BANK_MONEY", "", T("BANK_SEEN_BY", T("AGO_HOURS", 3), "Brynn")).replace("  ", " "))}</b>'
            f'<span style="margin-left:6px">{coins(2845610)}</span></div>'
            f'<div class="muted small" style="margin-bottom:10px">{esc(T("BANK_TAB_SEEN", T("BANK_SEEN_BY", T("AGO_HOURS", 3), "Brynn"), 63))}</div>'
            f'<div class="card sm" style="width:570px;padding:10px;position:relative">{grid}</div>{tipbox}')


@scene("bank-tabs", "Bank, Tabs: the tab as the game draws it (14 x 7 slots), the guild money, and who read it and when")
def s_bank_tabs():
    return bank_frame(0, bank_tabs_body(), badge_n=3)


@scene("bank-items-accord", "Bank, Items in the Accord theme: every item once with its total and where it is", theme="accord")
def s_bank_items_accord():
    return s_bank_items()


def bank_items_body():
    rows = ""
    for i, (n, q) in enumerate(ITEMS):
        total = 8 + (i * 37) % 260
        where = ", ".join(f"{TABS[(i + k) % 4]} x{max(1, total // (k + 2))}" for k in range(1 + i % 3))
        rows += (f'<tr class="{"hover" if i == 3 else ""}"><td style="width:34px">{pic(i + 1, q)}</td><td style="width:260px;color:{QUALITY_COLOR[q]}">{esc(n)}</td>'
                 f'<td style="width:80px" class="mono">{total}</td><td class="muted">{esc(where)}</td></tr>')
    return (f'<div class="muted small" style="margin:0 0 8px 2px">{esc(T("BANK_ITEMS_EXPLAIN"))}</div>'
            f'<div style="position:relative"><table class="tbl"><tbody>{rows}</tbody></table>{scrollbar(0, 120)}</div>')


@scene("bank-items", "Bank, Items: every item once with its total and where it is; the search box filters by name or tab")
def s_bank_items():
    return bank_frame(1, bank_items_body(), badge_n=3, search_text="")


LOG = [("Brynn", "MAGE", "deposit", "Greater Healing Potion", 20, 1, "12 min"), ("Fenwick", "ROGUE", "withdraw", "Thorium Bar", 15, 2, "40 min"),
       ("Aldric", "WARRIOR", "deposit", "Mithril Bar", 60, 2, "2 h"), ("Cora", "PRIEST", "deposit", "", 150000, 0, "3 h"), ("Dunstan", "PALADIN", "withdraw", "Large Brilliant Shard", 4, 3, "5 h"),
       ("Lyra", "MAGE", "deposit", "Runecloth", 200, 2, "6 h"), ("Hollis", "SHAMAN", "move", "Heavy Leather", 40, 2, "9 h"), ("Ulric", "WARRIOR", "repair", "", 18400, 0, "1 d"),
       ("Brynn", "MAGE", "deposit", "Mountain Silversage", 30, 2, "1 d"), ("Wren", "HUNTER", "withdraw", "Light Leather", 25, 2, "1 d"), ("Zephyr", "DRUID", "deposit", "Sungrass", 45, 2, "2 d"),
       ("Aldric", "WARRIOR", "deposit", "", 500000, 0, "2 d"), ("Orrin", "PALADIN", "deposit", "Righteous Orb", 6, 3, "3 d"), ("Sable", "ROGUE", "withdraw", "Black Lotus", 2, 3, "3 d")]
KIND_COLOR = {"deposit": "green", "withdraw": "red", "move": "muted", "repair": "muted"}


@scene("bank-log", "Bank, Log: the game's short log merged over every visit of guildmates with the addon, without duplicates")
def s_bank_log():
    rows = ""
    for n, c, kind, item, cnt, tab, when in LOG:
        what = (esc(item) + f" x{cnt}") if item else coins(cnt)
        tabname = T("BANKLOG_MONEY") if tab == 0 else TABS[tab - 1]
        rows += (f'<tr><td style="width:80px" class="muted mono small">{esc(when)}</td><td style="width:140px" class="muted">{esc(tabname)}</td>'
                 f'<td style="width:160px">{badge(c)}{name(n, c)}</td><td style="width:130px" class="{KIND_COLOR[kind]}">{esc(T("BANKLOG_KIND_" + kind.upper()))}</td><td>{what}</td></tr>')
    body = f'<div style="position:relative"><table class="tbl"><tbody>{rows}</tbody></table>{scrollbar(0, 150)}</div>'
    return bank_frame(2, body, badge_n=3, search_text="")


@scene("bank-donations", "Bank, Donations: deposits per player over 30 days, 365 days or all time, by gold or by items")
def s_bank_donations():
    data = [("Aldric", "WARRIOR", 1250000, 240), ("Lyra", "MAGE", 640000, 410), ("Brynn", "MAGE", 420000, 188), ("Cora", "PRIEST", 380000, 52), ("Dunstan", "PALADIN", 210000, 96),
            ("Hollis", "SHAMAN", 160000, 133), ("Zephyr", "DRUID", 95000, 120), ("Ulric", "WARRIOR", 60000, 41), ("Wren", "HUNTER", 42000, 77), ("Orrin", "PALADIN", 18000, 22)]
    top = data[0][2]
    rows = ""
    for i, (n, c, g, items) in enumerate(data):
        rows += (f'<tr><td style="width:46px" class="muted">{i + 1}</td><td style="width:170px">{badge(c)}{name(n, c)}</td>'
                 f'<td style="width:200px">{coins(g)}</td><td style="width:230px" class="muted small">{esc(T("BANKLOG_DEPOSITS", items // 6))} · {esc(T("BANKLOG_ITEMS_N", items))}</td>'
                 f'<td><div class="bar" style="width:260px;height:4px"><i style="width:{g * 100 // top}%"></i></div></td></tr>')
    bar = tools(chip(T("BANKLOG_D30"), "sel", True), chip(T("BANKLOG_D365"), "", True), chip(T("BANKLOG_ALL"), "", True))
    head = (f'<table class="tbl"><thead><tr><th style="width:46px">#</th><th style="width:170px">{esc(T("BANKLOG_COL_WHO"))}</th><th style="width:200px" class="sorted">{esc(T("BANKLOG_COL_GOLD"))}</th>'
            f'<th style="width:230px">{esc(T("BANKLOG_COL_DEPOSITS"))}</th><th></th></tr></thead></table>')
    return bank_frame(3, f'{bar}{head}<table class="tbl"><tbody>{rows}</tbody></table>', badge_n=3)


@scene("bank-money", "Bank, Money: the guild's money over the last 30 days, from the money records that reached this client")
def s_bank_money():
    vals = [int(2400000 + 380000 * math.sin(i / 3.2) + i * 18000 + (i % 5) * 26000) for i in range(30)]
    lo, hi = min(vals), max(vals)
    bars = "".join(f'<div style="flex:1;margin:0 3px;background:var(--accent);height:{40 + (v - lo) * 270 // (hi - lo)}px;border-radius:3px 3px 0 0"></div>' for v in vals)
    inner = (f'<h2>{esc(T("BANKLOG_MONEY_TITLE", 30))}</h2>'
             f'<div style="display:flex;align-items:flex-end;height:310px;padding:8px 8px 0;margin-top:8px;background:var(--surface-2);border-radius:12px;box-shadow:inset 0 -1px 0 var(--border)">{bars}</div>'
             f'<div style="display:flex;justify-content:space-between;margin-top:10px" class="small"><span class="muted">{esc(T("BANKLOG_LOW", ""))}{coins(lo)}</span><span class="muted">{esc(T("BANKLOG_HIGH", ""))}{coins(hi)}</span></div>')
    body = f'{tools(chip("30", "sel", True), chip("90", "", True))}{card(inner, "width:716px;padding:20px 24px")}'
    return bank_frame(4, body, badge_n=3)


# the tips of the requests, in copper, by requester (a withdrawal of an item only)
GIFTS = {"Fenwick": 20000, "Cora": 50000}
# when each waiting request was made, as the officers' list writes it
DATES = {"Fenwick": "2026-11-25 18:12", "Cora": "2026-11-25 15:40", "Lyra": "2026-11-25 11:05"}


def money(copper):
    return T("BANK_GOLD", copper // 10000)


REQS = [("Fenwick", "ROGUE", "withdraw", "Thorium Bar x20", "open", "Engineering skill-up", "2 h"), ("Cora", "PRIEST", "withdraw", "Major Mana Potion x10", "approved", "Raid night", "5 h"),
        ("Lyra", "MAGE", "donation", "Runecloth x200", "open", "", "9 h"), ("Hollis", "SHAMAN", "deposit", "Heavy Leather x60", "fulfilled", "", "1 d"),
        ("Wren", "HUNTER", "withdraw", "500 gold", "rejected", "Not this week", "1 d"), ("Zephyr", "DRUID", "withdraw", "Sungrass x30", "fulfilled", "", "2 d"),
        ("Ulric", "WARRIOR", "withdraw", "Black Lotus x1", "cancelled", "", "3 d")]
STATUS_COLOR = {"open": "gold", "approved": "green", "fulfilled": "green", "rejected": "red", "cancelled": "muted"}


REQS_IT = [("Fenwick", "ROGUE", "withdraw", "Barra di torio x20", "open", "Per salire in Ingegneria", "2 h"), ("Cora", "PRIEST", "withdraw", "Pozione di mana maggiore x10", "approved", "Serata raid", "5 h"),
           ("Lyra", "MAGE", "donation", "Pezza di Runa x200", "open", "", "9 h"), ("Hollis", "SHAMAN", "deposit", "Cuoio pesante x60", "fulfilled", "", "1 g"),
           ("Wren", "HUNTER", "withdraw", "500 monete d'oro", "rejected", "Non questa settimana", "1 g"), ("Zephyr", "DRUID", "withdraw", "Solargento x30", "fulfilled", "", "2 g"),
           ("Ulric", "WARRIOR", "withdraw", "Loto nero x1", "cancelled", "", "3 g")]


def req_rows(officer, me="Fenwick"):
    rows = ""
    for n, c, kind, what, st, note, when in (REQS_IT if lib.LANG[0] == "itIT" else REQS):
        acts = ""
        if st == "open" and n == me and not officer:
            acts = btn(T("BANKREQ_CANCEL"), small=True)
        if officer and st == "open":
            acts = btn(T("BANKREQ_APPROVE"), small=True) + " " + btn(T("BANKREQ_REJECT"), small=True)
        if officer and st == "approved":
            acts = btn(T("BANKREQ_FULFILL"), small=True)
        nt = f'<span class="muted small"> - {esc(T("BANKREQ_NOTE", note))}</span>' if note else ""
        if n in GIFTS:
            nt = f'<span class="muted small"> - {esc(T("BANKREQ_GIFT_SHORT", money(GIFTS[n])))}</span>' + nt
        rows += (f'<tr><td style="width:150px">{badge(c)}{name(n, c)}</td><td style="width:100px" class="muted">{esc(T("BANKREQ_KIND_" + kind.upper()))}</td>'
                 f'<td style="width:300px">{esc(what)}{nt}</td><td style="width:100px" class="{STATUS_COLOR[st]}">{esc(T("BANKREQ_STATUS_" + st.upper()))}</td>'
                 f'<td class="muted small" style="width:56px">{esc(when)}</td><td style="text-align:right">{acts}</td></tr>')
    return rows


def requests_body(officer=False, fields=(("Thorium Bar", 168), ("20", 56), ("2", 52), ("Engineering skill-up", 168))):
    kinds = "".join(chip(T("BANKREQ_KIND_" + k), "sel" if k == "WITHDRAW" else "", small=True) + " " for k in ("WITHDRAW", "DEPOSIT", "DONATION"))
    def field(label, value):
        return (f'<div style="display:flex;flex-direction:column;gap:4px"><span class="small muted">{esc(label)}</span>'
                f'{edit(value[0], value[1])}</div>')

    form = card(f'<div style="display:flex;gap:8px;align-items:center">{kinds}<span class="muted small" style="margin-left:8px">{esc(T("BANKREQ_TIP_WITHDRAW"))}</span></div>'
                f'<div style="display:flex;gap:10px;margin-top:10px;align-items:flex-end">{field(T("BANKREQ_ITEM_BANK"), fields[0])}'
                f'{field(T("BANKREQ_AMOUNT_ITEM"), fields[1])}{field(T("BANKREQ_GIFT"), fields[2])}{field(T("BANKREQ_REASON"), fields[3])}'
                f'{btn(T("BANKREQ_SEND"), "filled", dense=True)}</div>'
                f'<div class="small muted" style="margin-top:6px">{esc(T("BANKREQ_STOCK", 34))}<span class="mono" style="margin-left:12px">{esc(T("AGO_HOURS", 3))}</span></div>',
                "background:var(--surface-2);padding:12px 16px;margin-bottom:10px")
    return (f'{form}<div style="display:flex;gap:8px;margin-bottom:8px">{chk(T("BANKREQ_ONLY_MINE"))}{chk(T("BANKREQ_SHOW_CLOSED"), True)}</div>'
            f'<table class="tbl tall"><tbody>{req_rows(officer)}</tbody></table>')


@scene("bank-requests", "Bank, Requests: ask for an item or gold, or offer one; the guild sees it, officers decide")
def s_bank_requests():
    return bank_frame(5, requests_body(), badge_n=3)


@scene("bank-requests-aurora", "Bank, Requests in the light theme Aurora, with the buttons officers see", theme="aurora")
def s_bank_requests_aurora():
    return bank_frame(5, requests_body(True), badge_n=3)


@scene("bank-inbox", "Bank, Inbox (officers): what waits for a decision, the counters, and a chat line per new request")
def s_bank_inbox():
    head = "".join(f'<th style="{style}">{esc(T(key))}</th>' for key, style in (
        ("BANKREQ_COL_DATE", "width:150px;text-align:left"), ("BANKREQ_COL_WHO", "width:130px;text-align:left"), ("BANKREQ_COL_ITEM", "text-align:left"),
        ("BANKREQ_COL_COUNT", "width:60px;text-align:right"), ("BANKREQ_COL_GIFT", "width:80px;text-align:right")))
    rows = ""
    waiting = [r for r in REQS if r[4] in ("open", "approved")]
    for n, c, kind, what, st, note, when in reversed(waiting):
        item, qty = what.rsplit(" x", 1)
        looks = esc(T("BANKREQ_KIND_" + kind.upper()) + (" - " + note if note else ""))
        cls = "muted"
        if st == "approved":
            cls = "green"
            looks = esc(T("BANKREQ_LOOKS_DONE", "Cora", what, T("AGO_MINUTES", 35))) + "&nbsp;&nbsp; " + esc(T("BANKREQ_LOOKS_PAID", "Cora", money(GIFTS["Cora"]), T("AGO_MINUTES", 20)))
        acts = (btn(T("BANKREQ_APPROVE"), small=True) + " " + btn(T("BANKREQ_REJECT"), small=True)) if st == "open" else btn(T("BANKREQ_FULFILL"), small=True)
        gift = money(GIFTS[n]) if n in GIFTS else "-"
        rows += (f'<tr><td class="muted mono small">{esc(DATES[n])}</td><td>{badge(c)}{name(n, c)}</td><td>{esc(item)}</td>'
                 f'<td class="mono" style="text-align:right">{esc(qty)}</td><td class="mono gold" style="text-align:right">{esc(gift)}</td>'
                 f'<td rowspan="2" style="width:230px;text-align:right">{acts}</td></tr>'
                 f'<tr><td class="{STATUS_COLOR[st]} small">{esc(T("BANKREQ_STATUS_" + st.upper()))}</td><td colspan="4" class="{cls} small">{looks}</td></tr>')
    sorts = tools(chip(T("BANKREQ_SORT_OLDEST"), "sel", True), chip(T("BANKREQ_SORT_NEWEST"), "", True), chip(T("BANKREQ_SORT_GIFT"), "", True))
    chat = ('<div style="position:absolute;left:46px;bottom:74px;width:520px;padding:8px 10px;background:rgba(0,0,0,.62);border-radius:4px;font:13px/1.5 \'Segoe UI\',Arial,sans-serif;color:#fff;z-index:40">'
            f'<div><span style="color:#d4af37">{esc(T("ADDON_TITLE"))}</span> {esc(T("BANKNOTE_NEW", "Fenwick", "Thorium Bar x20"))}</div>'
            f'<div><span style="color:#d4af37">{esc(T("ADDON_TITLE"))}</span> {esc(T("BANKNOTE_NEW", "Lyra", "Runecloth x200"))}</div></div>')
    body = (f'<div class="muted small" style="margin:0 0 8px 2px">{esc(T("BANKREQ_INBOX_EXPLAIN"))}</div>{sorts}'
            f'<table class="tbl"><thead><tr class="small muted">{head}<th></th></tr></thead><tbody>{rows}</tbody></table>')
    return bank_frame(6, body, badge_n=3) + chat


# =====================================================================================================================
# Settings and Info
# =====================================================================================================================
PAGE = 520


def srow(label, control, note=""):
    return (f'<div style="display:flex;align-items:center;gap:12px;height:32px"><span style="flex:1">{esc(label)}</span>{control}</div>')


def scard(inner):
    return card(inner, f"width:{PAGE}px;margin-bottom:16px")


def pager(on):
    """The pages of Settings are tabs of the shell's row since M13.7: nothing in the page."""
    return ""


def settings_cards():
    look = scard(f'<h2>{esc(T("SET_LOOK_TITLE"))}</h2><div class="small muted" style="margin-top:6px">{esc(T("SET_LOOK_TEXT"))}</div>'
                 f'<div style="margin-top:14px">{srow(T("SET_LOOK_THEME"), seg([T("THEME_NEBULA"), T("THEME_AURORA"), T("THEME_ACCORD")], 0))}'
                 f'<div style="margin-top:8px">{srow(T("SET_LOOK_EFFECTS"), switch(True))}</div><div style="margin-top:8px">{srow(T("SET_LOOK_ANIMATIONS"), switch(True))}</div>'
                 f'<div style="margin-top:8px">{srow(T("SET_LOOK_FONT"), seg([T("SET_LOOK_FONT_ADDON"), T("SET_LOOK_FONT_GAME")], 0))}</div></div>'
                 f'<div class="small muted" style="margin-top:6px">{esc(T("SET_LOOK_FONT_NOTE"))}</div>')
    contacts = scard(f'<h2>{esc(T("SET_CONTACTS"))}</h2><div class="muted" style="margin-top:8px;color:var(--text-2)">{esc(T("SET_CONTACTS_TEXT"))}</div>'
                     f'<div style="margin-top:14px;font-weight:500">{esc(T("SET_BATTLETAG", "Fenwick#6082"))}</div>'
                     f'<div class="eyebrow" style="margin-top:14px;color:var(--text-3)">{esc(T("SET_DISCORD"))}</div>'
                     f'<div style="display:flex;gap:10px;margin-top:8px">{edit("fenwick_clockwork", 240, extra="height:40px")}{btn(T("SET_SAVE"))}</div>'
                     f'<div class="green small" style="margin-top:8px">{esc(T("SET_SAVED"))}</div><div class="muted small" style="margin-top:6px">{esc(T("SET_DISCORD_NATIVE"))}</div>')
    main = scard(f'<h2>{esc(T("SET_MAIN_TITLE"))}</h2><div class="muted" style="margin-top:8px;color:var(--text-2)">{esc(T("SET_MAIN_TEXT"))}</div>'
                 f'<div style="margin-top:12px;font-weight:500">{esc(T("SET_MAIN_CURRENT", "Fenwick", 60))}</div><div style="margin-top:8px">{btn(T("SET_MAIN_CHOOSE"))}</div>')
    notify = scard(f'<h2>{esc(T("SET_NOTIFY_TITLE"))}</h2><div style="margin-top:8px">{srow(T("SET_NOTIFY_OFFICER"), switch(True))}<div style="margin-top:6px">{srow(T("SET_NOTIFY_DECISION"), switch(True))}</div></div>'
                   f'<div class="small muted" style="margin-top:6px">{esc(T("SET_NOTIFY_NOTE"))}</div>')
    cols = [("COL_NAME", True, True), ("COL_LEVEL", True, False), ("COL_CLASS", True, False), ("COL_RANK", True, False), ("COL_ZONE", False, False), ("COL_LAST_ONLINE", True, False),
            ("COL_PROF1", True, False), ("COL_PROF2", True, False), ("COL_LIKES", True, False), ("COL_CONTACTS", False, False), ("COL_ADDON", True, False)]
    chips = "".join(chip(T(k), ("sel " if on else "") + ("lock" if always else ""), small=True) for k, on, always in cols)
    columns = scard(f'<h2>{esc(T("SET_COLUMNS_TITLE"))}</h2><div style="margin-top:8px;color:var(--text-2)">{esc(T("SET_COLUMNS_TEXT"))}</div>'
                    f'<div style="display:flex;flex-wrap:wrap;gap:8px;margin-top:12px">{chips}</div><div style="margin-top:10px">{btn(T("COLUMNS_RESET"), "text")}</div>')
    sizes = [T("SET_DATA_ACCOUNT", "412.8 KB", 1), T("SET_DATA_CHAR", "1.9 KB"), T("SET_DATA_GUILD", "1.8 MB"),
             "   " + T("SET_DATA_PART_RECORDS", "coplay", "1.3 MB", 980), "   " + T("SET_DATA_PART_RECORDS", "likes", "212.4 KB", 790),
             "   " + T("SET_DATA_PART_RECORDS", "recipes", "176.0 KB", 312), "   " + T("SET_DATA_PART_RECORDS", "accounts", "88.2 KB", 164), "   " + T("SET_DATA_PART_RECORDS", "bank", "31.5 KB", 37)]
    data = scard(f'<h2>{esc(T("SET_DATA_TITLE"))}</h2><div style="margin-top:8px;color:var(--text-2)">{esc(T("SET_DATA_TEXT"))}</div>'
                 f'<div class="small mono muted" style="line-height:1.6;white-space:pre;margin-top:10px">{esc(chr(10).join(sizes))}</div>'
                 f'<div style="margin-top:12px">{btn(T("SET_CLEAR"), "outlined", extra="style=width:240px")}</div><div class="muted small" style="margin-top:8px">{esc(T("SET_CLEAR_TEXT"))}</div>')
    return [look, contacts, main, notify, columns, data]


def settings_page(offset=0):
    return (f'<div class="rel">{pager(0)}<div style="position:absolute;left:0;top:0;bottom:0;overflow:hidden;width:{PAGE}px">'
            f'<div style="margin-top:-{offset}px">{"".join(settings_cards())}</div></div></div>')


@scene("settings", "Settings: the Appearance card (theme, effects, animations, font), contacts and main character")
def s_settings():
    return full("settings", settings_page(0), peers=9, searchable=False)


@scene("settings-saved-data", "Settings, lower part: notices, Roster columns, the saved data sizes and Clear guild data (two clicks)")
def s_settings_data():
    return full("settings", settings_page(760), peers=9, searchable=False)


NEBULA_LOGO = {"nebula": "nebula-logo-dark.png", "accord": "nebula-logo-dark.png", "aurora": "nebula-logo-light.png"}


def about_cards(theme="nebula"):
    """The Info page: four cards in a column, as UI/About.lua builds them (the logo of the guild follows the theme)."""
    logo_img = f'<img src="{lib.ASSETS}/logo-source.webp" alt="" width="72" height="72" style="border-radius:50%;box-shadow:0 0 18px var(--glow-accent)">'
    c1 = scard(f'<div style="display:flex;gap:16px;align-items:flex-start">{logo_img}<div><div style="font:700 15px/1 var(--display);letter-spacing:.1em;color:var(--accent-text);margin-top:10px;text-transform:uppercase">{esc(T("ADDON_TITLE"))}</div>'
               f'<div class="small muted" style="margin-top:8px">{esc(T("ABOUT_VERSION", "0.12.0"))}</div></div></div>'
               f'<div style="margin-top:16px;color:var(--text-2)">{esc(T("ABOUT_PURPOSE"))}</div><div style="margin-top:8px;color:var(--text-2)">{esc(T("ABOUT_PURPOSE2"))}</div>')
    nebula = f'<img src="{lib.ASSETS}/{NEBULA_LOGO[theme]}" alt="" width="64" height="64">'
    c2 = scard(f'<h2>{esc(T("ABOUT_CREDITS"))}</h2><div style="margin-top:10px">{esc(T("ABOUT_MADE_BY", "Finland"))}</div>'
               f'<div style="display:flex;gap:16px;align-items:flex-start;margin-top:12px">{nebula}<div style="width:380px"><div style="margin-top:4px">{esc(T("ABOUT_GUILD", "NEBULA"))}</div>'
               f'<div class="small muted" style="margin-top:6px">{esc(T("ABOUT_PERMISSION", "NEBULA"))}</div></div></div>')
    links = [("repo", "https://github.com/Finland6738/azeroth-accord"), ("issues", "https://github.com/Finland6738/azeroth-accord/issues"),
             ("site", "https://nebula-community.github.io/giochi/wow-forever/"), ("kofi", "https://ko-fi.com/finland6738")]
    lb = "".join(f'<div style="margin-top:14px;color:var(--text-2)" class="small">{esc(T("ABOUT_LINK_" + k.upper()))}</div><div style="margin-top:4px">{edit(u, 488, extra="height:40px")}</div>' for k, u in links)
    c3 = scard(f'<h2>{esc(T("ABOUT_LINKS"))}</h2><div class="small muted" style="margin-top:4px">{esc(T("ABOUT_LINKS_HINT"))}</div>{lb}')
    c4 = scard(f'<h2>{esc(T("ABOUT_LEGAL"))}</h2><div style="margin-top:8px;color:var(--text-2)">{esc(T("ABOUT_LICENSE", "GPL-3.0"))}</div>'
               f'<div style="margin-top:8px;color:var(--text-2)">{esc(T("ABOUT_THIRD"))}</div><div class="small muted" style="margin-top:12px">{esc(T("ABOUT_DISCLAIMER"))}</div>')
    return [c1, c2, c3, c4]


def about_page(theme="nebula", offset=0):
    return (f'<div class="rel">{pager(1)}<div style="position:absolute;left:0;top:0;bottom:0;overflow:hidden;width:{PAGE}px">'
            f'<div style="margin-top:-{offset}px">{"".join(about_cards(theme))}</div></div></div>')


@scene("about", "Settings, Info: the logo, who made it and with whom (the dark NEBULA logo), then the links to copy and the licence")
def s_about():
    return full("settings:info", about_page("nebula"), peers=9, searchable=False)


@scene("about-aurora", "Settings, Info in the light theme Aurora: the credits with the light NEBULA logo, the links and the notices", theme="aurora")
def s_about_aurora():
    return full("settings:info", about_page("aurora", 214), peers=9, searchable=False)


@scene("diagnostics-box", "/accord debug: the report in a box, already selected, to paste into a bug report (no names)")
def s_diag():
    lines = ["Azeroth Accord diagnostics", "addon: 1.0.0", "client: 1.60.1 (build 70170)", "interface: 16001", "project id: 99 (WoW Forever)", "locale: enUS", "role: officer", "guild size: 214", "",
             "== Sending ==", "sending: allowed", "", "== Last errors ==", "no addon errors recorded this session", "", "== Compat ==", "Client: 1.60.1 (build 70170), interface 16001, project id 99 (Forever)",
             "Features:", "  [available] guildTab - Blizzard layout recognised", "  [available] clubProfessions", "  [unknown] guildRecipesNative - not asked yet", "  [available] officerAddonChannel",
             "APIs: 78 available, 0 missing, 0 restricted, 0 error", "", "== Saved data ==", "AzerothAccordDB: schema found 2, current 2, about 1.8 MB", "AzerothAccordCharDB: schema found 2, current 2, about 1.9 KB",
             "Memory: about 18.4 MB in use by the addon (the game's figure)", "Saved data: no problems", "", "== Store ==", "Store: accounts 164, contacts 160, recipes 312, coplay 980, likes 790, bank 37, bankreq 24"]
    text = esc("\n".join(lines))
    box = (f'<div class="dialog" style="left:280px;top:40px;width:640px;height:610px">'
           f'<div style="display:flex;align-items:center"><span style="font:600 18px/1 var(--body)">{esc(T("DIAG_TITLE"))}</span></div>'
           f'<div class="small muted" style="margin:8px 0 10px">{esc(T("DIAG_HINT"))}</div>'
           f'<div class="edit" style="display:block;height:456px;padding:10px 12px;overflow:hidden"><pre class="mono" style="margin:0;font-size:11.5px;line-height:1.45;color:var(--text-1);background:color-mix(in srgb, var(--accent) 28%, transparent);display:inline-block;padding:0 3px;white-space:pre-wrap">{text}</pre></div>'
           f'<div style="position:absolute;left:24px;right:24px;bottom:24px;display:flex;align-items:center">{btn(T("DIAG_SELECT"), "outlined")}<span class="grow" style="text-align:center"><span class="muted small">{esc(T("DIAG_SIZE", len(lines), len(chr(10).join(lines))))}</span></span>{btn(T("DIAG_CLOSE"), "filled", extra="style=width:110px")}</div></div>')
    return f'<div style="position:absolute;inset:0;background:var(--scrim)"></div>{box}'


@scene("window-standalone", "The standalone window (/accord, Pop out): the same panel in a window you can move and resize, with its title bar")
def s_window():
    return standalone("reputation", likes_body(14), peers=9)


# =====================================================================================================================
# Italian interface
# =====================================================================================================================
class it_guild:
    """The guild window of the Italian previews: the guild is Italian too."""
    def __enter__(self):
        lib.GUILD, lib.SUB = "Compagnia della Lanterna", "Gilda"

    def __exit__(self, *a):
        lib.GUILD, lib.SUB = "Lantern Company", "Guild"


@scene("it-roster", "Interfaccia italiana: il Roster nella scheda Accord della finestra di gilda", lang="itIT")
def s_it_roster():
    ms = sorted(MEMBERS, key=lambda m: -m[1])
    rows = [roster_row(m, i) for i, m in enumerate(ms)]
    body = (f'<div class="rel">{roster_toolbar()}<div style="position:relative">{table(roster_cols(), rows, sort=1, desc=True, sel=(2,))}{scrollbar(4, 110)}</div></div>')
    with it_guild():
        return full("roster", body, peers=9, ago=1)


@scene("it-bank-requests", "Interfaccia italiana: le richieste alla banca, con i pulsanti degli ufficiali", lang="itIT")
def s_it_bank():
    with it_guild():
        return bank_frame(5, requests_body(True, (("Barra di torio", 160), ("20", 56), ("2", 52), ("Per salire in Ingegneria", 172))), badge_n=3)


@scene("it-settings", "Interfaccia italiana: la pagina Impostazioni con la scheda Aspetto", lang="itIT")
def s_it_settings():
    with it_guild():
        return full("settings", settings_page(0), peers=9, searchable=False)


@scene("it-about", "Interfaccia italiana: la pagina Info con i crediti, i link da copiare e la licenza", lang="itIT")
def s_it_about():
    with it_guild():
        return full("settings:info", about_page("nebula"), peers=9, searchable=False)
