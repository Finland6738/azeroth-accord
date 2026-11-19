"""Every case of the interface as a design preview, part 2: Reputation (likes, social index, group map, someone new), the guild
bank, Settings and diagnostics, the standalone window and the Italian interface. Registered after the scenes of part 1
(tools/mockup_scenes.py). The data is invented; every text is read from the addon's locale tables."""
from mockup_lib import *  # noqa: F401,F403
import mockup_lib as lib
from mockup_scenes import (scene, MEMBERS, ranks, roster_cols, roster_row, roster_toolbar, zone_of, loc_prof, PROF_IT)  # noqa: F401


def mode_bar(labels, on, extra=""):
    return tools(*[btn(t, "on" if i == on else "", small=True) for i, t in enumerate(labels)], right=extra)


# =====================================================================================================================
# Reputation
# =====================================================================================================================
def rep_modes(on, officer=True):
    labels = [T("REP_MODE_LIKES"), T("REP_MODE_SOCIAL")] + ([T("REP_MODE_GROUPS")] if officer else []) + [T("REP_MODE_NEW")]
    return mode_bar(labels, on)


@scene("reputation-likes", "Reputation: likes, one row per player; Like (a second click confirms), pending, liked and you")
def s_likes():
    people = sorted([m for m in MEMBERS if m[9] > 0], key=lambda m: -m[9])
    states = {"Aldric": ("state", "REP_LIKED", "green"), "Brynn": ("btn", None, None), "Cora": ("state", "REP_PENDING", "grey"), "Dunstan": ("btn", None, None),
              "Lyra": ("confirm", None, None), "Testchar": ("state", "REP_YOU", "grey")}
    rows = ""
    for i, m in enumerate(people[:22]):
        n, lv, c = m[0], m[1], m[2]
        kind = states.get(n, ("btn", None, None))
        if n == "Fenwick":
            kind = ("state", "REP_YOU", "grey")
        if kind[0] == "btn":
            act = btn(T("REP_LIKE"), small=True, extra='style="width:96px"')
        elif kind[0] == "confirm":
            act = btn(T("REP_CONFIRM"), "on", small=True, extra='style="width:96px"')
        else:
            act = f'<span class="{kind[2]}">{esc(T(kind[1]))}</span>'
        chars = f'<span class="muted small">{esc(T("REP_CHARS", 3))}</span>' if n in ("Brynn", "Aldric", "Dunstan") else ""
        rows += (f'<tr style="height:24px"><td style="width:42px;text-align:right" class="muted">{i + 1}</td><td style="width:150px">{badge(c)}{name(n, c)}</td>'
                 f'<td style="width:96px">{chars}</td><td style="width:70px">{m[9]}</td><td>{act}</td></tr>')
    body = (f'<div style="position:relative;height:100%">{rep_modes(0)}<div class="pad" style="padding:2px 12px 4px"><div class="muted small">{esc(T("REP_LIKES_EXPLAIN"))}</div></div>'
            f'<table class="tbl"><thead><tr><th style="width:42px"></th><th style="width:150px" class="sorted">{esc(T("REP_COL_NAME"))}</th><th style="width:96px"></th>'
            f'<th style="width:70px" class="sorted">{esc(T("REP_COL_LIKES"))}</th><th></th></tr></thead></table>'
            f'<div style="position:relative;padding-right:12px"><table class="tbl">{rows}</table></div>{scrollbar(70, 90)}</div>')
    return full("reputation", body, search_text="", peers=9)


@scene("reputation-social-index", "Reputation, Social: your own index, what it measures, and (officers) every player's index")
def s_social():
    own = (f'<div class="card" style="width:330px"><h3>{esc(T("SOC_YOURS"))}</h3><div style="font:700 28px/1.2 var(--font);color:var(--gold)">68 <span class="muted" style="font-size:14px">/ 100</span></div>'
           f'<div class="bar" style="margin:4px 0 8px"><i style="width:68%"></i></div>'
           f'<div class="small">{esc(T("SOC_EFFECTIVE", 6.4, 38))}<br>{esc(T("SOC_DISTINCT", 17))}<br><span class="muted">{esc(T("SOC_MINUTES", T("SOC_HOURS", 14.2)))}</span></div>'
           f'<div class="small" style="margin-top:8px">{esc(T("SOC_TOP"))}<br>' + "".join(f'<span class="muted">{esc(T("SOC_TOP_LINE", n, p))}</span><br>' for n, p in (("Brynn", 24), ("Dunstan", 18), ("Lyra", 14), ("Fenwick", 11), ("Cora", 9))) + '</div></div>')
    explain = (f'<div class="card" style="width:330px;margin-top:10px"><h3>{esc(T("SOC_TIP_TITLE"))}</h3><div class="small muted">{esc(T("SOC_TIP_1"))}<br><br>{esc(T("SOC_TIP_2"))}<br><br>{esc(T("SOC_TIP_3"))}</div></div>')
    people = [("Lyra", "MAGE", 91, 9.8, 29), ("Brynn", "MAGE", 84, 8.6, 25), ("Dunstan", "PALADIN", 77, 7.5, 22), ("Fenwick", "ROGUE", 68, 6.4, 17), ("Aldric", "WARRIOR", 61, 5.8, 21),
              ("Cora", "PRIEST", 55, 5.1, 14), ("Hollis", "SHAMAN", 49, 4.4, 12), ("Ulric", "WARRIOR", 44, 3.9, 11), ("Zephyr", "DRUID", 38, 3.2, 9), ("Orrin", "PALADIN", 30, 2.6, 8),
              ("Wren", "HUNTER", 24, 2.0, 7), ("Quill", "WARLOCK", 0, 0, 0)]
    rows = ""
    for n, c, idx, eff, part in people:
        txt = T("SOC_LIST_ROW", idx, eff, part) if idx else T("SOC_LIST_LOW", T("SOC_HOURS", 3.4))
        rows += f'<div style="height:22px;line-height:22px;{"color:var(--muted)" if not idx else ""}">{badge(c)}{name(n, c)}<span style="float:right;margin-right:6px" class="small">{esc(txt)}</span></div>'
    lst = f'<div style="width:430px"><h3>{esc(T("SOC_LIST_TITLE"))}</h3><div class="muted small" style="margin-bottom:6px">{esc(T("SOC_LIST_NOTE"))}</div>{rows}</div>'
    body = f'<div style="position:relative;height:100%">{rep_modes(1)}<div style="display:flex;gap:28px;padding:10px 16px"><div>{own}{explain}</div>{lst}</div></div>'
    return full("reputation", body, peers=9)


@scene("reputation-group-map", "Reputation, Groups (officers): how mixed the guild is, and its communities as circles of players")
def s_groups():
    import math
    groups = [(210, 120, 62, "#f2c14e", 9), (520, 105, 48, "#59a8ff", 7), (360, 190, 34, "#7fe063", 5), (630, 200, 36, "#ff7373", 5)]
    dots, links = "", ""
    centers = []
    for gx, gy, rad, col, n in groups:
        centers.append((gx, gy))
        for k in range(n):
            a = 2 * math.pi * k / n
            r = rad * (0.45 + 0.4 * ((k * 7) % 5) / 5)
            dots += f'<circle cx="{gx + r * math.cos(a):.1f}" cy="{gy + r * math.sin(a):.1f}" r="5" fill="{col}" stroke="#000" stroke-opacity=".5"/>'
        dots += f'<circle cx="{gx}" cy="{gy}" r="{rad + 10}" fill="{col}" fill-opacity=".07" stroke="{col}" stroke-opacity=".5" stroke-dasharray="3 4"/>'
    for (a, b) in ((0, 1), (0, 2), (1, 3), (2, 3), (1, 2)):
        links += f'<line x1="{centers[a][0]}" y1="{centers[a][1]}" x2="{centers[b][0]}" y2="{centers[b][1]}" stroke="#ffffff" stroke-opacity=".12" stroke-width="2"/>'
    canvas = f'<svg width="860" height="246" style="background:rgba(125,118,107,.08);display:block">{links}{dots}</svg>'
    lines = [(T("MAP_MIXING_MEDIUM", 0.41), "head"), (T("MAP_SUMMARY", 26, 4, T("SOC_HOURS", 211.3)), "muted"),
             (T("MAP_GROUP", 1, 9, "Aldric, Brynn, Dunstan, Lyra, Fenwick, Cora" + T("MAP_MORE", 3)), ""), (T("MAP_GROUP_TIME", T("SOC_HOURS", 74.5), T("SOC_HOURS", 21.1)), "muted"),
             (T("MAP_GROUP", 2, 7, "Hollis, Ulric, Wren, Zephyr, Orrin, Quill" + T("MAP_MORE", 1)), ""), (T("MAP_GROUP_TIME", T("SOC_HOURS", 38.0), T("SOC_HOURS", 17.2)), "muted"),
             (T("MAP_GROUP", 3, 5, "Elowen, Garrick, Isolde, Sable, Vesper"), ""), (T("MAP_GROUP_TIME", T("SOC_HOURS", 12.6), T("SOC_HOURS", 9.8)), "muted"),
             (T("MAP_GROUP", 4, 5, "Joren, Kestrel, Maren, Nyx, Rowan"), ""), (T("MAP_GROUP_TIME", T("SOC_HOURS", 9.1), T("SOC_HOURS", 14.0)), "muted")]
    rows = "".join(f'<div class="{"gold" if k == "head" else "muted" if k == "muted" else ""} {"small" if k == "muted" else ""}" style="height:19px;line-height:19px;{"font-weight:700;" if k == "head" else ""}">{esc(t)}</div>' for t, k in lines)
    body = f'<div style="position:relative;height:100%">{rep_modes(2)}<div style="padding:4px 14px">{canvas}<div style="margin-top:8px">{rows}</div></div></div>'
    return full("reputation", body, peers=9)


@scene("reputation-someone-new", "Reputation, Someone new: guildmates online you have played with least; Whisper and Invite are your clicks")
def s_new():
    rows = ""
    data = [("Hollis", "SHAMAN", 60, 5, "Winterspring"), ("Quill", "WARLOCK", 60, 0, "Ironforge"), ("Orrin", "PALADIN", 59, 8, "Orgrimmar"), ("Wren", "HUNTER", 60, 12, "E. Plaguelands"),
            ("Zephyr", "DRUID", 60, 21, "Darnassus"), ("Ulric", "WARRIOR", 60, 27, "Burning Steppes")]
    for n, c, lv, mins, z in data:
        together = T("NEW_NEVER") if mins == 0 else T("NEW_MINUTES", mins)
        rows += (f'<tr style="height:30px"><td style="width:170px">{badge(c)}{name(n, c)}</td><td class="muted small">{esc(T("NEW_DETAIL", lv, z, together))}</td>'
                 f'<td style="width:170px;text-align:right">{btn(T("NEW_WHISPER"), small=True)} {btn(T("NEW_INVITE"), small=True)}</td></tr>')
    body = (f'<div style="position:relative;height:100%">{rep_modes(3)}<div class="pad" style="padding:4px 14px"><div class="muted small">{esc(T("NEW_EXPLAIN", 5, 30))}</div></div>'
            f'<div style="padding:0 18px 0 8px"><table class="tbl">{rows}</table></div></div>')
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
    return full("bank", f'<div style="position:relative;height:100%">{bank_modes(on, badge_n)}{inner}</div>', badge=badge_n, **kw)


@scene("bank-tabs", "Bank, Tabs: the tab as the game draws it (14 x 7 slots), the guild money, and who read it and when")
def s_bank_tabs():
    grid = ""
    for r in range(7):
        row = ""
        for c in range(14):
            k = r * 14 + c
            if k < 78 and (k * 7) % 11 != 3:
                row += slot(k + 3, 1 + (k * 5) % 40 if k % 3 else 1, 2 if k % 9 == 0 else 3 if k % 17 == 0 else 4 if k == 31 else 1)
            else:
                row += slot()
        grid += f'<div style="display:flex;gap:2px;margin-bottom:2px">{row}</div>'
    tabbtns = "".join(btn(t, "on" if i == 0 else "", small=True) + " " for i, t in enumerate(TABS[:4]))
    tipbox = tip(560, 120, '<div class="gold" style="font-size:14px">Flask of the Titans</div><div class="small" style="margin-top:2px">Binds when picked up</div>'
                 '<div class="green small" style="margin-top:4px">Use: Increases your maximum health by 1200 for 2 hours.</div>'
                 f'<div class="muted small" style="margin-top:6px">{esc(T("BANK_TAB_COUNT", TABS[0], 4))}</div>', 280)
    body = (f'<div class="pad" style="padding:8px 14px"><div>{tabbtns}</div>'
            f'<div style="margin:8px 0"><b class="gold">{esc(T("BANK_MONEY", "", T("BANK_SEEN_BY", T("AGO_HOURS", 3), "Brynn")).replace("  ", " "))}</b>'
            f'<span style="margin-left:6px">{coins(2845610)}</span></div>'
            f'<div class="muted small" style="margin-bottom:8px">{esc(T("BANK_TAB_SEEN", T("BANK_SEEN_BY", T("AGO_HOURS", 3), "Brynn"), 63))}</div>'
            f'<div style="width:510px;padding:6px;background:#050403;box-shadow:inset 0 0 0 1px #2c2418;position:relative">{grid}</div></div>'
            f'{tipbox}')
    return bank_frame(0, body, badge_n=3)


@scene("bank-items", "Bank, Items: every item once with its total and where it is; the search box filters by name or tab")
def s_bank_items():
    rows = ""
    for i, (n, q) in enumerate(ITEMS):
        total = 8 + (i * 37) % 260
        where = ", ".join(f"{TABS[(i + k) % 4]} x{max(1, total // (k + 2))}" for k in range(1 + i % 3))
        col = {1: "#ffffff", 2: "#1eff00", 3: "#4a9bff", 4: "#c46bff"}[q]
        rows += f'<tr style="height:23px"><td style="width:34px">{pic(i + 1, q)}</td><td style="width:240px;color:{col}">{esc(n)}</td><td style="width:70px;text-align:right;padding-right:18px">{total}</td><td class="muted small">{esc(where)}</td></tr>'
    body = (f'<div class="pad" style="padding:6px 14px 2px"><div class="muted small">{esc(T("BANK_ITEMS_EXPLAIN"))}</div></div>'
            f'<div style="position:relative;padding:0 18px 0 8px"><table class="tbl">{rows}</table>{scrollbar(6, 120)}</div>')
    return bank_frame(1, body, badge_n=3, search_text="")


LOG = [("Brynn", "MAGE", "deposit", "Greater Healing Potion", 20, 1, "12 min"), ("Fenwick", "ROGUE", "withdraw", "Thorium Bar", 15, 2, "40 min"),
       ("Aldric", "WARRIOR", "deposit", "Mithril Bar", 60, 2, "2 h"), ("Cora", "PRIEST", "deposit", "", 150000, 0, "3 h"), ("Dunstan", "PALADIN", "withdraw", "Large Brilliant Shard", 4, 3, "5 h"),
       ("Lyra", "MAGE", "deposit", "Runecloth", 200, 2, "6 h"), ("Hollis", "SHAMAN", "move", "Heavy Leather", 40, 2, "9 h"), ("Ulric", "WARRIOR", "repair", "", 18400, 0, "1 d"),
       ("Brynn", "MAGE", "deposit", "Mountain Silversage", 30, 2, "1 d"), ("Wren", "HUNTER", "withdraw", "Light Leather", 25, 2, "1 d"), ("Zephyr", "DRUID", "deposit", "Sungrass", 45, 2, "2 d"),
       ("Aldric", "WARRIOR", "deposit", "", 500000, 0, "2 d"), ("Orrin", "PALADIN", "deposit", "Righteous Orb", 6, 3, "3 d"), ("Sable", "ROGUE", "withdraw", "Black Lotus", 2, 3, "3 d")]


@scene("bank-log", "Bank, Log: the game's short log merged over every visit of guildmates with the addon, without duplicates")
def s_bank_log():
    rows = ""
    for n, c, kind, item, cnt, tab, when in LOG:
        what = (esc(item) + f" x{cnt}") if item else coins(cnt)
        tabname = T("BANKLOG_MONEY") if tab == 0 else TABS[tab - 1]
        rows += (f'<tr style="height:23px"><td style="width:70px" class="muted">{esc(when)}</td><td style="width:130px" class="muted">{esc(tabname)}</td>'
                 f'<td style="width:140px">{badge(c)}{name(n, c)}</td><td style="width:120px">{esc(T("BANKLOG_KIND_" + kind.upper()))}</td><td>{what}</td></tr>')
    body = f'<div style="position:relative;padding:0 18px 0 8px"><table class="tbl"><thead><tr><th style="width:70px">When</th><th style="width:130px">Tab</th><th style="width:140px">{esc(T("COL_NAME"))}</th><th style="width:120px"></th><th></th></tr></thead></table><table class="tbl">{rows}</table>{scrollbar(6, 150)}</div>'
    return bank_frame(2, body, badge_n=3, search_text="")


@scene("bank-donations", "Bank, Donations: deposits per player over 30 days, 365 days or all time, by gold or by items")
def s_bank_donations():
    data = [("Aldric", "WARRIOR", 1250000, 240), ("Lyra", "MAGE", 640000, 410), ("Brynn", "MAGE", 420000, 188), ("Cora", "PRIEST", 380000, 52), ("Dunstan", "PALADIN", 210000, 96),
            ("Hollis", "SHAMAN", 160000, 133), ("Zephyr", "DRUID", 95000, 120), ("Ulric", "WARRIOR", 60000, 41), ("Wren", "HUNTER", 42000, 77), ("Orrin", "PALADIN", 18000, 22)]
    top = data[0][2]
    rows = ""
    for i, (n, c, g, items) in enumerate(data):
        rows += (f'<tr style="height:26px"><td style="width:36px;text-align:right" class="muted">{i + 1}</td><td style="width:150px">{badge(c)}{name(n, c)}</td>'
                 f'<td style="width:190px">{coins(g)}</td><td style="width:200px" class="muted small">{esc(T("BANKLOG_DEPOSITS", items // 6))} · {esc(T("BANKLOG_ITEMS_N", items))}</td>'
                 f'<td><div class="bar" style="width:240px"><i style="width:{g * 100 // top}%"></i></div></td></tr>')
    body = (f'{tools(btn(T("BANKLOG_D30"), "on", small=True), btn(T("BANKLOG_D365"), small=True), btn(T("BANKLOG_ALL"), small=True), btn(T("BANKLOG_GOLD"), "on", small=True), btn(T("BANKLOG_ITEMS"), small=True))}'
            f'<div style="padding:6px 18px 0 8px"><table class="tbl">{rows}</table></div>')
    return bank_frame(3, body, badge_n=3)


@scene("bank-money", "Bank, Money: the guild's money over the last 30 days, from the money records that reached this client")
def s_bank_money():
    import math
    vals = [int(2400000 + 380000 * math.sin(i / 3.2) + i * 18000 + (i % 5) * 26000) for i in range(30)]
    lo, hi = min(vals), max(vals)
    bars = "".join(f'<div style="flex:1;margin:0 2px;background:linear-gradient(#e6be40,#7a5a10);height:{40 + (v - lo) * 240 // (hi - lo)}px;border-radius:2px 2px 0 0"></div>' for v in vals)
    body = (f'{tools(btn("30", "on", small=True), btn("90", small=True))}<div class="pad" style="padding:6px 22px"><h3>{esc(T("BANKLOG_MONEY_TITLE", 30))}</h3>'
            f'<div style="display:flex;align-items:flex-end;height:300px;padding:6px 6px 0;background:rgba(125,118,107,.07);box-shadow:inset 0 -1px 0 var(--line)">{bars}</div>'
            f'<div style="display:flex;justify-content:space-between;margin-top:8px" class="small"><span class="muted">{esc(T("BANKLOG_LOW", ""))}{coins(lo)}</span><span class="muted">{esc(T("BANKLOG_HIGH", ""))}{coins(hi)}</span></div></div>')
    return bank_frame(4, body, badge_n=3)


REQS = [("Fenwick", "ROGUE", "withdraw", "Thorium Bar x20", "open", "Engineering skill-up", "2 h"), ("Cora", "PRIEST", "withdraw", "Major Mana Potion x10", "approved", "Raid night", "5 h"),
        ("Lyra", "MAGE", "donation", "Runecloth x200", "open", "", "9 h"), ("Hollis", "SHAMAN", "deposit", "Heavy Leather x60", "fulfilled", "", "1 d"),
        ("Wren", "HUNTER", "withdraw", "500 gold", "rejected", "Not this week", "1 d"), ("Zephyr", "DRUID", "withdraw", "Sungrass x30", "fulfilled", "", "2 d"),
        ("Ulric", "WARRIOR", "withdraw", "Black Lotus x1", "cancelled", "", "3 d")]
STATUS_COLOR = {"open": "", "approved": "green", "fulfilled": "green", "rejected": "red", "cancelled": "grey"}


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
        rows += (f'<tr style="height:26px"><td style="width:130px">{badge(c)}{name(n, c)}</td><td style="width:88px">{esc(T("BANKREQ_KIND_" + kind.upper()))}</td>'
                 f'<td style="width:260px">{esc(what)}{nt}</td><td style="width:90px"><span class="chip {STATUS_COLOR[st]}">{esc(T("BANKREQ_STATUS_" + st.upper()))}</span></td>'
                 f'<td class="muted small" style="width:60px">{esc(when)}</td><td style="text-align:right">{acts}</td></tr>')
    return rows


@scene("bank-requests", "Bank, Requests: ask for an item or gold, or offer one; the guild sees it, officers decide")
def s_bank_requests():
    form = (f'<div class="card" style="margin:4px 8px 8px"><div style="display:flex;gap:8px;align-items:center">{btn(T("BANKREQ_KIND_WITHDRAW"), "on", small=True)}{btn(T("BANKREQ_KIND_DEPOSIT"), small=True)}{btn(T("BANKREQ_KIND_DONATION"), small=True)}'
            f'<span class="muted small" style="margin-left:6px">{esc(T("BANKREQ_TIP_WITHDRAW"))}</span></div>'
            f'<div style="display:flex;gap:10px;margin-top:8px;align-items:center"><span class="small muted">{esc(T("BANKREQ_ITEM"))}</span>{edit("Thorium Bar", 150)}<span class="small muted">{esc(T("BANKREQ_AMOUNT_ITEM"))}</span>{edit("20", 56)}'
            f'<span class="small muted">{esc(T("BANKREQ_REASON"))}</span>{edit("Engineering skill-up", 170)}{btn(T("BANKREQ_SEND"), small=True)}</div></div>')
    body = f'{form}<div style="padding:0 8px;">{tools(chk(T("BANKREQ_ONLY_MINE")), chk(T("BANKREQ_SHOW_CLOSED"), True))}<table class="tbl" style="margin-top:4px">{req_rows(False)}</table></div>'
    return bank_frame(5, body, badge_n=3)


@scene("bank-inbox", "Bank, Inbox (officers): what waits for a decision, the counters, and a chat line per new request")
def s_bank_inbox():
    rows = ""
    waiting = [r for r in REQS if r[4] in ("open", "approved")]
    for n, c, kind, what, st, note, when in reversed(waiting):
        looks = ""
        if st == "approved":
            looks = f'<div class="green small" style="padding-left:6px">{esc(T("BANKREQ_LOOKS_DONE", "Cora", "Major Mana Potion x10", T("AGO_MINUTES", 35)))}</div>'
        rows += (f'<div class="card" style="margin:0 8px 8px;display:flex;align-items:center;gap:12px"><div style="flex:1">{badge(c)}{name(n, c)} <span class="muted small">- {esc(T("BANKREQ_KIND_" + kind.upper()))} - {esc(T("BANKREQ_STATUS_" + st.upper()))} - {esc(when)}</span>'
                 f'<div style="margin-top:2px">{esc(what)}</div>{looks}</div><div>{btn(T("BANKREQ_APPROVE"), small=True) + " " + btn(T("BANKREQ_REJECT"), small=True) if st == "open" else btn(T("BANKREQ_FULFILL"), small=True)}</div></div>')
    chat = ('<div style="position:absolute;left:46px;bottom:26px;width:520px;padding:8px 10px;background:rgba(0,0,0,.62);border-radius:4px;font:13px/1.5 var(--font);z-index:40;box-shadow:0 0 0 1px #3a2f1e">'
            f'<div><span style="color:#d4af37">{esc(T("ADDON_TITLE"))}</span> {esc(T("BANKNOTE_NEW", "Fenwick", "Thorium Bar x20"))}</div>'
            f'<div><span style="color:#d4af37">{esc(T("ADDON_TITLE"))}</span> {esc(T("BANKNOTE_NEW", "Lyra", "Runecloth x200"))}</div></div>')
    body = f'<div class="pad" style="padding:6px 14px 4px"><div class="muted small">{esc(T("BANKREQ_INBOX_EXPLAIN"))}</div></div>{rows}'
    return bank_frame(6, body, badge_n=3) + chat


# =====================================================================================================================
# Settings and diagnostics
# =====================================================================================================================
def settings_page(offset=0):
    def head(t):
        return f'<h2 style="margin-top:22px">{esc(t)}</h2>'
    cols = [("COL_NAME", True, True), ("COL_LEVEL", True, False), ("COL_CLASS", True, False), ("COL_RANK", True, False), ("COL_ZONE", False, False), ("COL_LAST_ONLINE", True, False),
            ("COL_PROF1", True, False), ("COL_PROF2", True, False), ("COL_LIKES", True, False), ("COL_CONTACTS", False, False), ("COL_ADDON", True, False)]
    colhtml = "".join(f'<span style="display:inline-block;width:158px;margin-bottom:4px">{chk(T(k), on, off=always)}</span>' for k, on, always in cols)
    sizes = [(T("SET_DATA_ACCOUNT", "412.8 KB", 1), ""), (T("SET_DATA_CHAR", "1.9 KB"), ""), (T("SET_DATA_GUILD", "1.8 MB"), ""),
             ("   " + T("SET_DATA_PART_RECORDS", "coplay", "1.3 MB", 980), ""), ("   " + T("SET_DATA_PART_RECORDS", "likes", "212.4 KB", 790), ""),
             ("   " + T("SET_DATA_PART_RECORDS", "recipes", "176.0 KB", 312), ""), ("   " + T("SET_DATA_PART_RECORDS", "accounts", "88.2 KB", 164), ""),
             ("   " + T("SET_DATA_PART_RECORDS", "bank", "31.5 KB", 37), "")]
    page = f'''<div style="position:absolute;left:18px;top:{14 - offset}px;width:600px">
      <h2 style="margin-top:0">{esc(T("SET_CONTACTS"))}</h2><p class="small">{esc(T("SET_CONTACTS_TEXT"))}</p>
      <div>{esc(T("SET_BATTLETAG", "Fenwick#6082"))}</div><div style="margin-top:10px" class="small">{esc(T("SET_DISCORD"))}</div>
      <div style="margin-top:4px">{edit("fenwick_clockwork", 220)} {btn(T("SET_SAVE"), small=True)}</div><div class="green small" style="margin-top:6px">{esc(T("SET_SAVED"))}</div>
      <div class="muted small" style="margin-top:6px">{esc(T("SET_DISCORD_NATIVE"))}</div>
      {head(T("SET_MAIN_TITLE"))}<p class="small">{esc(T("SET_MAIN_TEXT"))}</p><div>{esc(T("SET_MAIN_CURRENT", "Fenwick", 60))}</div><div style="margin-top:6px">{btn(T("SET_MAIN_CHOOSE"))}</div>
      {head(T("SET_NOTIFY_TITLE"))}<div>{chk(T("SET_NOTIFY_OFFICER"), True)}</div><div style="margin-top:4px">{chk(T("SET_NOTIFY_DECISION"), True)}</div><div class="muted small" style="margin-top:6px">{esc(T("SET_NOTIFY_NOTE"))}</div>
      {head(T("SET_COLUMNS_TITLE"))}<p class="small">{esc(T("SET_COLUMNS_TEXT"))}</p><div style="width:520px">{colhtml}</div><div style="margin-top:8px">{btn(T("COLUMNS_RESET"))}</div>
      {head(T("SET_DATA_TITLE"))}<p class="small">{esc(T("SET_DATA_TEXT"))}</p>
      <div class="small mono" style="line-height:1.55;white-space:pre">{esc(chr(10).join(t for t, _ in sizes))}</div>
      <div style="margin-top:10px">{btn(T("SET_CLEAR"), extra='style="width:200px"')}</div><p class="muted small" style="margin-top:6px;width:520px">{esc(T("SET_CLEAR_TEXT"))}</p></div>'''
    return page + f'<div class="sb" style="--t:{6 + offset // 5}px;--h:260px"></div>'


@scene("settings", "Settings: contacts, main character, notices and Roster columns (also in the game's settings window)")
def s_settings():
    return full("settings", settings_page(0), peers=9, searchable=False)


@scene("settings-saved-data", "Settings, saved data: what the addon keeps on this computer, and Clear guild data (two clicks)")
def s_settings_data():
    return full("settings", settings_page(470), peers=9, searchable=False)


@scene("diagnostics-box", "/accord debug: the report in a box, already selected, to paste into a bug report (no names)")
def s_diag():
    lines = ["Azeroth Accord diagnostics", "addon: 1.0.0", "client: 1.60.1 (build 70170)", "interface: 16001", "project id: 99 (WoW Forever)", "locale: enUS", "role: officer", "guild size: 214", "",
             "== Sending ==", "sending: allowed", "", "== Last errors ==", "no addon errors recorded this session", "", "== Compat ==", "Client: 1.60.1 (build 70170), interface 16001, project id 99 (Forever)",
             "Features:", "  [available] guildTab - Blizzard layout recognised", "  [available] clubProfessions", "  [unknown] guildRecipesNative - not asked yet", "  [available] officerAddonChannel",
             "APIs: 78 available, 0 missing, 0 restricted, 0 error", "", "== Saved data ==", "AzerothAccordDB: schema found 1, current 1, about 1.8 MB", "AzerothAccordCharDB: schema found 1, current 1, about 1.9 KB",
             "Memory: about 18.4 MB in use by the addon (the game's figure)", "Saved data: no problems", "", "== Store ==", "Store: accounts 164, contacts 160, recipes 312, coplay 980, likes 790, bank 37, bankreq 24"]
    text = esc("\n".join(lines))
    box = f'''<div style="position:absolute;left:280px;top:60px;width:640px;height:600px;background:linear-gradient(#241d15,#15110c);border-radius:6px;box-shadow:0 0 0 2px var(--edge),0 0 0 4px var(--edge-dark),0 16px 44px rgba(0,0,0,.8)">
      <div style="padding:8px 14px"><b class="gold" style="font-size:15px">{esc(T("DIAG_TITLE"))}</b><span style="float:right" class="btn sm">x</span></div>
      <div class="small muted" style="padding:0 16px 6px">{esc(T("DIAG_HINT"))}</div>
      <div style="margin:0 16px;height:468px;background:#060504;box-shadow:inset 0 0 0 1px #4a3d28;padding:8px 10px;overflow:hidden"><pre class="mono" style="margin:0;font-size:11.5px;line-height:1.45;color:#fff;background:#2a5db0;display:inline-block;padding:0 3px;white-space:pre-wrap">{text}</pre></div>
      <div style="position:absolute;left:14px;right:14px;bottom:12px;display:flex;align-items:center"><span class="btn" style="width:120px">{esc(T("DIAG_SELECT"))}</span><span class="grow" style="flex:1;text-align:center" ><span class="muted small">{esc(T("DIAG_SIZE", len(lines), len(chr(10).join(lines))))}</span></span><span class="btn" style="width:100px">{esc(T("DIAG_CLOSE"))}</span></div></div>'''
    return f'<div style="position:absolute;inset:0;background:rgba(0,0,0,.35)"></div>{box}'


@scene("window-standalone", "The standalone window (/accord, Pop out): the same panel in a window you can move and resize")
def s_window():
    people = sorted([m for m in MEMBERS if m[9] > 0], key=lambda m: -m[9])
    rows = ""
    for i, m in enumerate(people[:18]):
        n, c = m[0], m[2]
        act = btn(T("REP_LIKE"), small=True, extra='style="width:96px"') if i not in (0, 3) else f'<span class="green">{esc(T("REP_LIKED"))}</span>'
        rows += f'<tr style="height:24px"><td style="width:42px;text-align:right" class="muted">{i + 1}</td><td style="width:150px">{badge(c)}{name(n, c)}</td><td style="width:96px"></td><td style="width:70px">{m[9]}</td><td>{act}</td></tr>'
    body = (f'<div style="position:relative;height:100%">{rep_modes(0)}<div class="pad" style="padding:2px 12px 4px"><div class="muted small">{esc(T("REP_LIKES_EXPLAIN"))}</div></div>'
            f'<div style="position:relative;padding-right:12px"><table class="tbl">{rows}</table></div></div>')
    return guild_window(panel("reputation", body, popout=False, peers=9, searchable=True), tabs=False, pop=True, title=T("ADDON_TITLE"), sub="")


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
    cols = roster_cols()
    body = (f'<div style="position:relative;height:100%">{roster_toolbar()}<div style="padding-right:12px;position:relative">{table(cols, rows, sort=1, desc=True, sel=(2,))}</div>{scrollbar(4, 110)}</div>')
    with it_guild():
        return full("roster", body, peers=9, ago=1)


@scene("it-bank-requests", "Interfaccia italiana: le richieste alla banca, con i pulsanti degli ufficiali", lang="itIT")
def s_it_bank():
    form = (f'<div class="card" style="margin:4px 8px 8px"><div style="display:flex;gap:8px;align-items:center">{btn(T("BANKREQ_KIND_WITHDRAW"), "on", small=True)}{btn(T("BANKREQ_KIND_DEPOSIT"), small=True)}{btn(T("BANKREQ_KIND_DONATION"), small=True)}'
            f'<span class="muted small" style="margin-left:6px">{esc(T("BANKREQ_TIP_WITHDRAW"))}</span></div>'
            f'<div style="display:flex;gap:10px;margin-top:8px;align-items:center"><span class="small muted">{esc(T("BANKREQ_ITEM"))}</span>{edit("Barra di torio", 130)}<span class="small muted">{esc(T("BANKREQ_AMOUNT_ITEM"))}</span>{edit("20", 40)}'
            f'<span class="small muted">{esc(T("BANKREQ_REASON"))}</span>{edit("Per salire in Ingegneria", 150)}{btn(T("BANKREQ_SEND"), small=True)}</div></div>')
    body = f'{form}<div style="padding:0 8px;">{tools(chk(T("BANKREQ_ONLY_MINE")), chk(T("BANKREQ_SHOW_CLOSED"), True))}<table class="tbl" style="margin-top:4px">{req_rows(True)}</table></div>'
    with it_guild():
        return bank_frame(5, body, badge_n=3)


@scene("it-settings", "Interfaccia italiana: la pagina Impostazioni", lang="itIT")
def s_it_settings():
    with it_guild():
        return full("settings", settings_page(0), peers=9, searchable=False)
