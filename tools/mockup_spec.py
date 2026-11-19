"""The annotated mockup pages of docs/specs/mockups/html/ (written by `python -X utf8 tools/make_mockups.py --spec`, rendered by
docs/specs/mockups/render.sh). They share the scenes and the building blocks of the design previews, so the two sets never
disagree: the previews show every case, these pages show the main screens with numbered callouts and a legend (the clean
copies, without callouts, are what the wiki and the READMEs embed: docs/specs/mockups/img/clean/).
"""
from mockup_lib import *  # noqa: F401,F403
import mockup_lib as lib
import mockup_scenes as s1
import mockup_scenes2 as s2


def design_system():
    swatches = [("--win", "#1b1611", "window"), ("--inset", "#0f0d0b", "inset"), ("--edge", "#6b5530", "frame edge"), ("--gold", "#ffd100", "headings, buttons"),
                ("--text", "#f3ecdd", "body text"), ("--muted", "#9b9285", "secondary"), ("--green", "#4cd44c", "online, ok"), ("--red", "#ff5f52", "errors, rejected"),
                ("--blue", "#55a8ff", "links, actions")]
    sw = "".join(f'<div style="width:118px;margin:0 10px 10px 0"><div style="height:44px;border-radius:4px;background:{c};box-shadow:0 0 0 1px #4a3d28"></div>'
                 f'<div class="small" style="margin-top:3px"><b>{n}</b><br><span class="muted">{c} · {d}</span></div></div>' for n, c, d in swatches)
    classes = "".join(f'<span style="display:inline-block;width:92px">{badge(c)}<span style="color:{color_of(c)}" class="small">{class_name(c)}</span></span>' for c in CLASSES)
    slots = "".join(slot(i + 2, 1 + i * 9, q) for i, q in enumerate([1, 2, 3, 4, 1, 2, 3])) + slot()
    return f'''<div style="position:absolute;inset:0;padding:22px 30px;background:var(--win)">
      <h2 style="font-size:22px">Azeroth Accord: design system</h2>
      <p class="muted small" style="width:860px">The panel is drawn with the client's own frame templates, font objects and colours (SPEC-04 §5), so the tab feels native. These are the building blocks the previews use: an original drawing in the look of the guild window, not game art.</p>
      <div style="display:flex;flex-wrap:wrap;margin-top:6px">{sw}</div>
      <div style="display:flex;gap:40px;margin-top:6px">
        <div style="width:380px"><h3>Type</h3><div style="color:var(--gold);font:700 17px var(--font)">Heading (gold, bold)</div><div style="color:var(--gold)">Navigation and column titles (gold)</div>
          <div>Body text (white)</div><div class="small muted">Small and secondary text (grey)</div><div class="mono small">Report text (monospace)</div>
          <h3 style="margin-top:14px">Controls</h3><div style="display:flex;gap:8px;align-items:center;flex-wrap:wrap">{btn("Button")}{btn("Selected", "on")}{btn("Disabled", "off")}{btn("Small", small=True)}</div>
          <div style="display:flex;gap:16px;margin-top:8px">{chk("Checked", True)}{chk("Unchecked")}{chk("Locked", True, off=True)}</div>
          <div style="margin-top:8px">{search("search text")} {edit("typed text", 150)}</div><div style="margin-top:8px">{chip("chip")}{chip("ok", "green")}{chip("rejected", "red")}{chip("closed", "grey")}</div></div>
        <div style="width:360px"><h3>Class badges</h3><div style="line-height:2">{classes}</div>
          <h3 style="margin-top:14px">Bank slots and coins</h3><div style="display:flex;gap:2px">{slots}</div><div style="margin-top:8px">{coins(1284560)}</div>
          <h3 style="margin-top:14px">Table</h3>{table([("Name", 110), ("Lvl", 40), ("Rank", 120)], [[badge("MAGE") + name("Brynn", "MAGE"), "60", "Officer"], [badge("ROGUE") + name("Fenwick", "ROGUE"), "60", "Veteran"], [badge("PRIEST") + name("Cora", "PRIEST"), "58", "Officer"]], sort=0, sel=(1,))}</div>
        <div style="position:relative;width:200px"><h3>Menu</h3><div class="menu" style="position:static;width:190px">
          <div class="on">Online</div><div>Mains only</div><div class="on">Alchemy</div><div class="head">Class</div></div></div></div></div>'''


def _page(body):
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Azeroth Accord mockup</title>
<link rel="stylesheet" href="accord.css"><script src="accord.js"></script></head>
<body><div class="stage">{body}</div>
<div class="dp"><b>DESIGN PREVIEW</b><span class="cap">Original drawing from the addon's layout and texts (see docs/specs/mockups/README.md)</span><span class="r">Not a screenshot: nothing has run in WoW Forever yet</span></div></body></html>'''


def pages():
    out = {"00-design-system": _page(design_system())}
    out["01-accord-tab"] = _page(s1.s_accord_tab() + "".join([callout(1, 1164, 340), callout(2, 690, 64), callout(3, 160, 100), callout(4, 690, 96), callout(5, 480, 121),
                                                              callout(6, 606, 201), callout(7, 1096, 62)]) +
                                 legend(["The Accord tab, under the game's four", "Sync state: guildmates with the addon, last update", "Navigation: Roster, Professions, Reputation, Bank, Settings",
                                         "Filters, grouping by account and the column chooser", "Sortable column titles", "A click on a row opens the member card",
                                         "Pop out: the same panel in a window of its own"]))
    out["02-member-card"] = _page(s1.s_member_card() + "".join([callout(1, 1056, 104), callout(2, 1056, 259), callout(3, 1056, 330), callout(4, 1056, 426), callout(5, 1056, 512), callout(6, 1056, 582)]) +
                                  legend(["The member: class, level, main", "Details and the source of each profession (game or the member's addon)", "Every character of the same account",
                                          "Contacts: a click copies; Add BattleTag friend", "Likes: one per player, irreversible", "Social index and what it measures"], left=True))
    out["03-bank-requests"] = _page(s2.s_bank_requests() + "".join([callout(1, 168, 98), callout(2, 168, 136), callout(3, 166, 250), callout(4, 740, 250), callout(5, 1080, 250), callout(6, 1164, 340)]) +
                                    legend(["Bank modes: Tabs, Items, Log, Donations, Money, Requests, Inbox", "The form: kind, item, how many, reason", "Every request of the guild, newest first",
                                            "Status: Open, Approved, Rejected, Fulfilled, Cancelled", "Cancel your own open request (officers see Approve, Reject, Fulfilled)", "Officers see the number of requests waiting"]))
    return out
