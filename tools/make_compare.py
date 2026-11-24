"""Makes the comparison sheet of docs/specs/mockups/compare/: Azeroth Accord's design previews beside the ones of Finland Dragon
Credit Points (FDCP), the sibling addon whose look Accord follows (ADR 0021), so a glance shows whether the two still match
(M6.16). Each row is the same kind of screen in both addons: a table, the settings cards, the Info page, the light theme, the
logo-palette theme and the design system.

Usage (Pillow needs plain `python`, not `python -I`):
    python -X utf8 tools/make_compare.py

Reads, and never changes, ../finland-dragon-credit-points/docs/specs/mockups/ (the previews of FDCP: drawings, no game art); the
sheet is then a committed picture, so tools/check_docs.py only checks that it exists, and the tool is rerun by hand after the
previews of either addon change. The labels are set in Outfit (SIL OFL 1.1, the addon's own font).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FDCP = os.path.join(os.path.dirname(ROOT), "finland-dragon-credit-points", "docs", "specs", "mockups")
OUT = os.path.join(ROOT, "docs", "specs", "mockups", "compare", "accord-vs-fdcp.webp")
PREV = os.path.join(ROOT, "docs", "specs", "mockups", "previews")
CLEAN = os.path.join(ROOT, "docs", "specs", "mockups", "img", "clean")
FONT = os.path.join(ROOT, "AzerothAccord", "Media", "Fonts", "Outfit-SemiBold.ttf")
FONT_REG = os.path.join(ROOT, "AzerothAccord", "Media", "Fonts", "Outfit-Regular.ttf")

# (what is compared, Accord's picture, what it is, FDCP's picture, what it is)
ROWS = [
    ("A table in Nebula", os.path.join(PREV, "roster-table.webp"), "Roster", os.path.join(FDCP, "fdcp-credits-en.webp"), "Credits"),
    ("Cards, switches and pills", os.path.join(PREV, "settings.webp"), "Settings", os.path.join(FDCP, "fdcp-settings-en.webp"), "Settings"),
    ("The Info page", os.path.join(PREV, "about.webp"), "Info", os.path.join(FDCP, "fdcp-about-en.webp"), "Info"),
    ("The light theme, Aurora", os.path.join(PREV, "roster-aurora.webp"), "Roster", os.path.join(FDCP, "fdcp-credits-aurora-en.webp"), "Credits"),
    ("The theme of the logo's colours (Accord / Drago)", os.path.join(PREV, "member-card-accord.webp"), "Member card", os.path.join(FDCP, "fdcp-roster-drago-en.webp"), "Roster"),
    ("Tokens and components", os.path.join(CLEAN, "00-design-system.webp"), "Design system", os.path.join(FDCP, "fdcp-design-system-en.webp"), "Design system"),
]
COL_W, GAP, PAD, LABEL_H, TITLE_H = 620, 16, 20, 34, 70
BG, FG, MUTED = (14, 12, 20), (240, 236, 245), (160, 152, 175)


def main():
    missing = [p for r in ROWS for p in (r[1], r[3]) if not os.path.isfile(p)]
    if missing:
        sys.exit("Missing pictures (run tools/make_mockups.py, and keep ../finland-dragon-credit-points next to this repository):\n  " + "\n  ".join(missing))
    thumbs = []
    for _, a, _, f, _ in ROWS:
        row = []
        for p in (a, f):
            im = Image.open(p).convert("RGB")
            row.append(im.resize((COL_W, round(im.height * COL_W / im.width)), Image.LANCZOS))
        thumbs.append(row)
    width = PAD * 2 + COL_W * 2 + GAP
    height = TITLE_H + sum(LABEL_H + max(t.height for t in row) + PAD for row in thumbs)
    sheet = Image.new("RGB", (width, height), BG)
    d = ImageDraw.Draw(sheet)
    big, mid, small = ImageFont.truetype(FONT, 26), ImageFont.truetype(FONT, 15), ImageFont.truetype(FONT_REG, 13)
    d.text((PAD, 16), "Azeroth Accord beside Finland Dragon Credit Points", font=big, fill=FG)
    d.text((PAD, 48), "Design previews, not screenshots: the same kind of screen in both addons, to check that they look like one family.", font=small, fill=MUTED)
    y = TITLE_H
    for (title, _, na, _, nf), row in zip(ROWS, thumbs):
        d.text((PAD, y + 6), title, font=mid, fill=FG)
        d.text((PAD + COL_W - 4, y + 8), f"Accord: {na}", font=small, fill=MUTED, anchor="ra")
        d.text((PAD + COL_W + GAP + COL_W - 4, y + 8), f"FDCP: {nf}", font=small, fill=MUTED, anchor="ra")
        y += LABEL_H
        sheet.paste(row[0], (PAD, y))
        sheet.paste(row[1], (PAD + COL_W + GAP, y))
        y += max(t.height for t in row) + PAD
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    sheet.save(OUT, "WEBP", quality=78, method=6)
    print(f"{os.path.relpath(OUT, ROOT)}  {sheet.width}x{sheet.height}  {os.path.getsize(OUT) // 1024} KB")


if __name__ == "__main__":
    main()
