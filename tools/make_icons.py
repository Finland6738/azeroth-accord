"""Builds the icon atlas of AzerothAccord/Media/ from Google's Material Symbols Rounded (M13.6, ui-style section 9.10).

Source: the official repository github.com/google/material-design-icons, licence Apache 2.0, at the one commit named
below (COMMIT). The tool downloads the variable font, its list of code points and the licence text into
tools/.cache/material-symbols/<commit>/ (git-ignored, never part of the addon) and refuses a file whose SHA-256 is not
the recorded one. The font is not shipped: only the glyphs the addon uses, rendered into the atlas.

Output, both committed and shipped:
  AzerothAccord/Media/symbols.tga          512x512, 32-bit uncompressed TGA, 48 px cells, 10 per row. White glyphs on a
                                           transparent ground: the theme tints them. The outlined cells come first
                                           (FILL 0), then the filled ones (FILL 1) of the icons that show an active state.
  AzerothAccord/Media/symbols-LICENSE.txt  the Apache 2.0 text of the source, which travels with the pictures

The lists below are the one place to add an icon: add its Material Symbols name to GLYPHS (and to FILLED when it shows
an active state), run the tool and mirror the lists in AzerothAccord/UI/Assets.lua. tools/check_addon.py compares the
two; it imports this file, so the top level needs nothing outside the standard library.

Rendering: weight 400, grade 0, optical size 24 (the size the addon shows them at), drawn at 4x and reduced.

Usage: python -X utf8 tools/make_icons.py   (needs Pillow; a network only for the first run)
"""
import hashlib
import os
import sys
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "AzerothAccord", "Media")
ATLAS_NAME, LICENSE_NAME = "symbols.tga", "symbols-LICENSE.txt"

REPOSITORY = "google/material-design-icons"
COMMIT = "10ecc14790612ca8fd164e3f4ffe9c16fc50d5b7"   # 2026-10-23
CACHE = os.path.join(ROOT, "tools", ".cache", "material-symbols", COMMIT)
FONT = "MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf"
CODEPOINTS = "MaterialSymbolsRounded[FILL,GRAD,opsz,wght].codepoints"
# cache name -> (path in the repository, SHA-256)
SOURCES = {
    FONT: ("variablefont/" + FONT, "7e74e36533ccee12c2b81e75bfcf3ccf123d3bb7e7e46d65d94445f23db0c97c"),
    CODEPOINTS: ("variablefont/" + CODEPOINTS, "a7404d9e5a1b63f496cf05ace45d386075886b5a7f123fba9f29527cb6006fde"),
    "LICENSE": ("LICENSE", "58d1e17ffe5109a7ae296caafcadfdbe6a7d176f0bc4ab01e12a689b0499d8bd"),
}

CELL, ATLAS, SUPERSAMPLE = 48, 512, 4
PER_ROW = ATLAS // CELL
WEIGHT, GRADE, OPTICAL_SIZE = 400, 0, 24

# Material Symbols names, in the order of the cells.
GLYPHS = [
    "chevron_right", "check", "close", "south_east", "skull", "shield", "health_and_safety", "swords", "star",
    "settings", "arrow_upward", "arrow_downward", "lock", "visibility", "fiber_manual_record", "add",
    "info", "warning", "search", "filter_alt", "content_copy", "delete", "edit", "calendar_month", "schedule", "person",
    "group", "crown", "paid", "refresh", "download", "upload",
    "notifications", "flag", "remove", "diamond", "shopping_bag", "menu_book", "link", "arrow_back",
    "favorite",
    # the destinations of the navigation rail (ui-style section 9.11, M13.7); swords and settings are above
    # (construction is also the Professions icon)
    "home", "groups", "group_add", "construction", "account_balance", "celebration", "shield_person",
    # the healer role (tank is shield, damage is swords)
    "medical_services",
]
# Also drawn filled (ui-style section 9.10: the chosen view, the switch that is on, the chosen filter): the rail's
# destinations, the icons of the view tabs, the heart, the dot and the three roles.
FILLED = [
    "home", "groups", "swords", "group_add", "construction", "account_balance", "celebration", "shield_person",
    "settings",
    "notifications", "group", "favorite", "paid", "flag", "calendar_month", "schedule", "skull",
    "menu_book", "diamond", "crown", "star", "fiber_manual_record",
    "shield", "medical_services",
]
# What the code calls an icon -> the glyph that draws it (mirrored in UI/Assets.lua). A glyph's own name works too.
NAMES = {
    "chevron": "chevron_right", "check": "check", "cross": "close", "dashed": "south_east", "skull": "skull",
    "shield": "shield", "heal": "health_and_safety", "sword": "swords", "star": "star", "gear": "settings",
    "arrow_up": "arrow_upward", "arrow_down": "arrow_downward", "lock": "lock", "eye": "visibility",
    "dot": "fiber_manual_record", "plus": "add", "info": "info", "warn": "warning", "search": "search",
    "filter": "filter_alt", "copy": "content_copy", "trash": "delete", "edit": "edit", "calendar": "calendar_month",
    "clock": "schedule", "user": "person", "users": "group", "crown": "crown", "coin": "paid", "refresh": "refresh",
    "download": "download", "upload": "upload", "bell": "notifications", "flag": "flag", "minus": "remove",
    "gem": "diamond", "bag": "shopping_bag", "book": "menu_book", "link": "link", "arrow_left": "arrow_back",
    "heart": "favorite", "hammer": "construction",
    # the roles of a group member
    "role_tank": "shield", "role_damage": "swords", "role_healer": "medical_services",
}


def cells():
    """[(glyph, filled)] in the order of the cells of the atlas."""
    return [(g, False) for g in GLYPHS] + [(g, True) for g in FILLED]


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def fetch(name):
    """The bytes of a source file, from the cache or from the repository at COMMIT; the SHA-256 must be the recorded one."""
    path_in_repo, want = SOURCES[name]
    cached = os.path.join(CACHE, name)
    if os.path.isfile(cached):
        with open(cached, "rb") as f:
            data = f.read()
        if sha256(data) == want:
            return data
    url = f"https://raw.githubusercontent.com/{REPOSITORY}/{COMMIT}/{urllib.parse.quote(path_in_repo)}"
    print(f"downloading {url}")
    request = urllib.request.Request(url, headers={"User-Agent": "make-icons"})
    with urllib.request.urlopen(request, timeout=300) as response:
        data = response.read()
    if sha256(data) != want:
        raise SystemExit(f"{name}: SHA-256 {sha256(data)} is not the recorded {want or '(none)'}")
    os.makedirs(CACHE, exist_ok=True)
    with open(cached, "wb") as f:
        f.write(data)
    return data


def code_points(text):
    return {name: int(code, 16) for name, code in (line.split() for line in text.splitlines() if line.strip())}


def load_font(path, size, filled):
    from PIL import ImageFont

    font = ImageFont.truetype(path, size)
    wanted = {b"Fill": 1 if filled else 0, b"Grade": GRADE, b"Optical Size": OPTICAL_SIZE, b"Weight": WEIGHT}
    names = [axis["name"] for axis in font.get_variation_axes()]
    unknown = [n for n in names if n not in wanted]
    if unknown:
        raise SystemExit(f"the font has axes the tool does not know: {unknown}")
    font.set_variation_by_axes([wanted[n] for n in names])
    return font


def draw_glyph(font, char):
    """One cell: the glyph's em square fills the cell (the 24-unit grid of the symbols, with its own margin)."""
    from PIL import Image, ImageDraw

    side = CELL * SUPERSAMPLE
    mask = Image.new("L", (side, side), 0)
    ImageDraw.Draw(mask).text((0, side), char, font=font, fill=255, anchor="ls")   # the em square sits on the baseline
    return mask.resize((CELL, CELL), Image.LANCZOS)


def build(font_path, points):
    from PIL import Image

    todo = cells()
    if len(todo) > PER_ROW * PER_ROW:
        raise SystemExit(f"{len(todo)} cells do not fit a {ATLAS}x{ATLAS} atlas of {CELL} px cells")
    missing = [g for g, _ in todo if g not in points]
    if missing:
        raise SystemExit(f"unknown Material Symbols names: {missing}")
    fonts = {filled: load_font(font_path, CELL * SUPERSAMPLE, filled) for filled in (False, True)}
    sheet = Image.new("L", (ATLAS, ATLAS), 0)
    for i, (glyph, filled) in enumerate(todo):
        mask = draw_glyph(fonts[filled], chr(points[glyph]))
        if not mask.getbbox():
            raise SystemExit(f"{glyph}: nothing was drawn")
        sheet.paste(mask, ((i % PER_ROW) * CELL, (i // PER_ROW) * CELL))
    atlas = Image.new("RGBA", sheet.size, (255, 255, 255, 0))
    atlas.putalpha(sheet)
    return atlas


def main():
    unknown = [g for g in FILLED if g not in GLYPHS] + [g for g in NAMES.values() if g not in GLYPHS]
    if unknown:
        raise SystemExit(f"FILLED or NAMES use glyphs that are not in GLYPHS: {unknown}")
    fetch(FONT)
    points = code_points(fetch(CODEPOINTS).decode("utf-8"))
    licence = fetch("LICENSE").decode("utf-8").replace("\r\n", "\n")
    os.makedirs(MEDIA, exist_ok=True)
    atlas_path = os.path.join(MEDIA, ATLAS_NAME)
    build(os.path.join(CACHE, FONT), points).save(atlas_path, compression=None)   # uncompressed 32-bit
    with open(os.path.join(MEDIA, LICENSE_NAME), "w", encoding="utf-8", newline="\n") as f:
        f.write(licence)
    print(f"{os.path.relpath(atlas_path, ROOT)}: {os.path.getsize(atlas_path)} bytes, "
          f"{len(GLYPHS)} outlined and {len(FILLED)} filled glyphs")
    return 0


if __name__ == "__main__":
    sys.exit(main())
