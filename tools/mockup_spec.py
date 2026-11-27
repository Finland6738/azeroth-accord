"""The annotated mockup pages of docs/specs/mockups/html/ (written by `python -X utf8 tools/make_mockups.py --spec`, rendered by
docs/specs/mockups/render.sh). They share the scenes and the building blocks of the design previews, so the two sets never
disagree: the previews show every case, these pages show the main screens with numbered callouts and a legend (the clean
copies, without callouts, are what the wiki and the READMEs embed: docs/specs/mockups/img/clean/). The design-system page shows the
tokens of the three themes and the pieces of the widget kit.
"""
from mockup_lib import *  # noqa: F401,F403
import mockup_lib as lib
import mockup_scenes as s1
import mockup_scenes2 as s2

SWATCH_TOKENS = ["bg", "surface-1", "surface-2", "surface-3", "raised", "text-1", "text-3", "accent", "secondary-container", "accent-2", "neon", "ok", "warn", "err"]


def design_system():
    def theme_card(th):
        tk = lib.THEMES[th]
        sw = "".join(f'<div style="width:40px"><div style="height:30px;border-radius:6px;background:{tk[k]};box-shadow:0 0 0 1px {tk["border"]}"></div>'
                     f'<div style="font:9px/1.2 var(--mono);color:var(--text-3);margin-top:3px;white-space:nowrap;overflow:hidden">{k.replace("surface", "surf")}</div></div>' for k in SWATCH_TOKENS)
        grad = f'<div style="height:6px;border-radius:3px;background:linear-gradient(120deg,{tk["grad"]});margin-top:10px"></div>'
        return card(f'<div style="display:flex;align-items:center;margin-bottom:10px"><h2 style="margin:0">{lib.THEME_NAME[th]}</h2><span class="grow"></span>'
                    f'<span class="muted small">{"light" if th == "aurora" else "dark"}{" · default" if th == "nebula" else ""}</span></div>'
                    f'<div style="display:flex;flex-wrap:wrap;gap:8px 6px;width:326px">{sw}</div>{grad}', "width:366px;padding:16px 20px;border-radius:14px")
    themes = "".join(theme_card(t) for t in lib.THEME_ORDER)
    classes = "".join(f'<span style="display:inline-block;width:104px">{badge(c)}<span class="cn small" style="color:{color_of(c)}">{class_name(c)}</span></span>' for c in CLASSES)
    slots = "".join(slot(i + 2, 1 + i * 9, q) for i, q in enumerate([1, 2, 3, 4, 1, 2, 3])) + slot()
    sample = table([("Name", 130), ("Lvl", 50), ("Rank", 120)], [[badge("MAGE") + name("Brynn", "MAGE"), "60", "Officer"], [badge("ROGUE") + name("Fenwick", "ROGUE"), "60", "Veteran"],
                                                                   [badge("PRIEST") + name("Cora", "PRIEST"), "58", "Officer"]], sort=0, sel=(1,))
    return f'''<div style="position:absolute;inset:0;padding:22px 30px;background:var(--bg)">
      <div style="display:flex;align-items:center;gap:14px">{logo(40)}<div><div style="font:700 18px/1 var(--display);letter-spacing:.12em;text-transform:uppercase;color:var(--accent-text);text-shadow:0 0 12px var(--glow)">Azeroth Accord</div>
        <div class="muted small" style="margin-top:6px">Design system: the three themes and the pieces of the widget kit (the family of Finland Dragon Credit Points)</div></div></div>
      <div style="display:flex;gap:16px;margin-top:16px">{themes}</div>
      <div style="display:flex;gap:30px;margin-top:20px">
        <div style="width:410px"><div class="eyebrow">Type</div>
          <div style="font:700 15px/1 var(--display);letter-spacing:.12em;text-transform:uppercase;margin-top:10px">Display · Orbitron</div>
          <div style="font:600 14px/1 var(--body);margin-top:10px">Titles · Outfit SemiBold</div><div style="margin-top:8px">Body text · Outfit 13</div>
          <div class="small muted" style="margin-top:6px">Small and secondary text</div><div class="mono small" style="margin-top:6px">Numbers and reports · JetBrains Mono</div>
          <div class="eyebrow" style="margin-top:18px">Buttons and pills</div>
          <div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:10px">{btn("Filled", "filled", dense=True)}{btn("Tonal", dense=True)}{btn("Outlined", "outlined", dense=True)}{btn("Text", "text", dense=True)}</div>
          <div style="display:flex;gap:8px;align-items:center;margin-top:10px">{chip("Chip")}{chip("Selected", "sel")}{select("Select", 110)}{switch(True)}{switch(False)}</div>
          <div style="display:flex;gap:8px;align-items:center;margin-top:10px">{pill("accent", "accent")}{pill("ok", "ok")}{pill("warn", "warn")}{pill("3", "err")}{pill("neutral")}</div>
          <div style="margin-top:10px">{seg(["Segmented", "Buttons", "Row"], 1)}</div><div style="margin-top:10px">{search("search text", 190)} {edit("typed text", 150)}</div></div>
        <div style="width:380px"><div class="eyebrow">Class squares</div><div style="line-height:2;margin-top:6px">{classes}</div>
          <div class="eyebrow" style="margin-top:14px">Bank slots and coins</div><div style="display:flex;gap:4px;margin-top:8px">{slots}</div><div style="margin-top:8px">{coins(1284560)}</div>
          <div class="eyebrow" style="margin-top:16px">Table</div><div style="margin-top:8px">{sample}</div></div>
        <div style="position:relative;width:170px"><div class="eyebrow">Menu</div><div class="menu" style="position:static;width:170px;margin-top:10px">
          <div class="head">Class</div><div class="on">All classes</div><div>Mage</div><div>Rogue</div></div></div></div></div>'''


def _page(body, theme="nebula"):
    return f'''<!doctype html><html lang="en" data-theme="{theme}"><head><meta charset="utf-8"><title>Azeroth Accord mockup</title>
<link rel="stylesheet" href="accord.css"><script src="accord.js"></script></head>
<body><div class="stage">{body}</div>
<div class="dp"><b>DESIGN PREVIEW</b><span class="cap">Original drawing from the addon's layout and texts (see docs/specs/mockups/README.md)</span><span class="r">Not a screenshot: nothing has run in WoW Forever yet</span></div></body></html>'''.replace("{ASSETS}", "../../../../assets")


def pages():
    out = {"00-design-system": _page(design_system())}
    out["01-accord-tab"] = _page(s1.s_accord_tab() + "".join([callout(1, 1100, 330), callout(2, 30, 132), callout(3, 905, 50), callout(4, 124, 132), callout(5, 124, 176),
                                                              callout(6, 1064, 262), callout(7, 1031, 50), callout(8, 420, 672)]) +
                                 legend(["The Accord tab, under the game's four (the addon's logo)", "The navigation rail: one icon per destination, the open one on its pill; the name in a tooltip", "Search, and Pop out: the same panel in a window of its own",
                                         "Filters: online, mains only, by account, class, rank, profession, and the column chooser", "Sortable column titles; the sorted one is in the accent colour",
                                         "A click on a row opens the member card", "Pop out", "The sync state: guildmates with the addon, last update"]))
    out["02-member-card"] = _page(s1.s_member_card() + "".join([callout(1, 764, 148), callout(2, 764, 238), callout(3, 764, 366), callout(4, 764, 474), callout(5, 764, 582), callout(6, 764, 650)]) +
                                  legend(["The member: class square, name, level, class and badges (online, main, addon)", "Details", "Professions and the source of each (the game or the member's addon)",
                                          "Every character of the same account", "Contacts: a click copies; Add BattleTag friend", "A long card scrolls with the mouse wheel: likes (one per player, irreversible) and the social index come after"], left=True))
    out["03-bank-requests"] = _page(s2.s_bank_requests() + "".join([callout(1, 124, 134), callout(2, 1066, 150), callout(3, 316, 322), callout(4, 900, 359), callout(5, 668, 359), callout(6, 30, 366)]) +
                                    legend(["The Show menu of the Bank's modes: Tabs, Items, Log, Donations, Money, Requests, Inbox", "The form in a card: kind, item from the bank, how many, tip, reason, Send", "Filters: only mine, closed ones too",
                                            "Every request of the guild, newest first", "Status: Open, Approved, Rejected, Fulfilled, Cancelled", "The count of requests waiting, on the Economy icon of the rail"]))
    return out
