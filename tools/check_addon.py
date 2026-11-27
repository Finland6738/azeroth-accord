"""Offline checks of the addon folder: TOC interface and fields, listed files, embeds.xml (Libs only when fetched),
Bindings.xml, and the locale tables.

Adapted from Azeroth Guild Finder (tools/check_addon.py), same owner, GPL-3.0 (ADR 0018). The media checks (M6.9)
come from Finland Dragon Credit Points: every media path the code uses exists, every file of Media/ is listed in
docs/third-party.md and every font family has its OFL text. The icon atlas (M13.6) has the cells tools/make_icons.py
builds, its Apache 2.0 text beside it and its licence entry in docs/third-party.md.

Locale rules (ADR 0015): every L["KEY"] used in the code has an English string in Locale/enUS.lua (AceLocale answers
with the key itself for a missing one, which would hide the mistake), and Locale/itIT.lua has exactly the English keys
(an extra one is a typo that would never show, a missing one an untranslated string).

Usage: python -I -X utf8 tools/check_addon.py (also called by tools/check_docs.py)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import make_icons  # noqa: E402  (the one list of the icons; the standard library only until it draws)
ADDON = os.path.join(ROOT, "AzerothAccord")
TOC = os.path.join(ADDON, "AzerothAccord.toc")
INTERFACE = "16001"
REQUIRED_TOC_KEYS = ("Title", "Author", "Version", "SavedVariables", "SavedVariablesPerCharacter",
                     "AddonCompartmentFunc")
SAVED = {"SavedVariables": "AzerothAccordDB", "SavedVariablesPerCharacter": "AzerothAccordCharDB"}
LUA_DIRS = ("Core", "Data", "Net", "UI")


def _path(base, rel):
    return os.path.join(base, *re.split(r"[\\/]", rel.strip()))


FONT_FAMILIES = ("Outfit", "JetBrainsMono", "Orbitron")
MEDIA_PATH = re.compile(r"Media[\\/]+([A-Za-z0-9_.\\/-]+?)(?=[\"'\s]|$)")


def media_files():
    """Paths of the files of Media/ relative to it (forward slashes)."""
    media = os.path.join(ADDON, "Media")
    found = []
    for folder, _, names in os.walk(media):
        for name in names:
            found.append(os.path.relpath(os.path.join(folder, name), media).replace(os.sep, "/"))
    return sorted(found)


def referenced_media():
    """(table exists, {path relative to Media/ without extension -> where}). Without UI/Assets.lua the references are
    the `Media/<name>` strings of the TOC and of the Lua files; with it (M6.10) UI/Assets.lua is the one table and
    this reads only that file."""
    table = os.path.join(ADDON, "UI", "Assets.lua")
    sources = [table] if os.path.isfile(table) else [TOC] + list(lua_files())
    found = {}
    for path in sources:
        with open(path, encoding="utf-8") as f:
            text = f.read()
        for m in MEDIA_PATH.finditer(text):
            rel = re.sub(r"[\\/]+", "/", m.group(1)).strip("/")   # Lua source writes each backslash twice
            if not rel:
                continue
            found[os.path.splitext(rel)[0]] = os.path.relpath(path, ROOT).replace(os.sep, "/")
    return os.path.isfile(table), found


ASSET_TEXTURE = re.compile(r'path\s*=\s*"[^"]*?Media[\\/]+([A-Za-z0-9_]+\.tga)"\s*,\s*w\s*=\s*(\d+)\s*,\s*h\s*=\s*(\d+)')


def check_asset_sizes(problems):
    """The w and h that UI/Assets.lua gives a texture are the ones in the TGA header of the file (the 9-slice margins and
    the icon coordinates are computed from them)."""
    table = os.path.join(ADDON, "UI", "Assets.lua")
    if not os.path.isfile(table):
        return
    with open(table, encoding="utf-8") as f:
        text = f.read()
    for name, w, h in ASSET_TEXTURE.findall(text):
        path = os.path.join(ADDON, "Media", name)
        if not os.path.isfile(path):
            continue   # reported by check_media
        with open(path, "rb") as f:
            header = f.read(18)
        real = (header[12] | header[13] << 8, header[14] | header[15] << 8) if len(header) == 18 else None
        if real != (int(w), int(h)):
            problems.append(f"UI/Assets.lua says Media/{name} is {w}x{h}, its header says {real[0]}x{real[1]}" if real
                            else f"Media/{name} is not a TGA file")


def check_media(problems):
    """Every media path the addon uses exists; every file of Media/ is used (once UI/Assets.lua exists, because until
    then the textures wait for it) and described in docs/third-party.md; every font family has its OFL text."""
    files = media_files()
    have = {os.path.splitext(f)[0] for f in files}
    has_table, used = referenced_media()
    for rel, where in sorted(used.items()):
        if rel not in have:
            problems.append(f"{where} uses Media/{rel} but the file is missing")
    third = os.path.join(ROOT, "docs", "third-party.md")
    text = ""
    if os.path.isfile(third):
        with open(third, encoding="utf-8") as f:
            text = f.read()
    else:
        problems.append("docs/third-party.md is missing")
    for rel in files:
        if has_table and not rel.endswith(("-OFL.txt", "-LICENSE.txt")) and os.path.splitext(rel)[0] not in used:
            problems.append(f"Media/{rel} is not listed in UI/Assets.lua")
        if os.path.basename(rel) not in text:
            problems.append(f"Media/{rel} is not described in docs/third-party.md (its source and licence)")
    for family in FONT_FAMILIES:
        if not os.path.isfile(os.path.join(ADDON, "Media", "Fonts", family + "-OFL.txt")):
            problems.append(f"Media/Fonts/{family}-OFL.txt (the licence) is missing")
        if not any(f.startswith(f"Fonts/{family}-") and f.endswith(".ttf") for f in files):
            problems.append(f"Media/Fonts has no {family} font file")


def lua_table(text, name):
    """The body of `Assets.<name> = { ... }` in UI/Assets.lua, or "" without one."""
    m = re.search(rf"^Assets\.{name}\s*=\s*\{{(.*?)\}}", text, re.M | re.S)
    return m.group(1) if m else ""


def check_icons(problems):
    """The icon atlas (M13.6): UI/Assets.lua lists it with the cells and the names of tools/make_icons.py; the Apache 2.0
    text of Material Symbols lies beside it; docs/third-party.md names the source, the commit and the licence."""
    atlas = f"Media/{make_icons.ATLAS_NAME}"
    licence = f"Media/{make_icons.LICENSE_NAME}"
    for rel in (atlas, licence):
        if not os.path.isfile(os.path.join(ADDON, rel)):
            problems.append(f"{rel} is missing (tools/make_icons.py writes it)")
    path = os.path.join(ADDON, licence)
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            if "Apache License" not in f.read():
                problems.append(f"{licence} is not the Apache License text")
    table = os.path.join(ADDON, "UI", "Assets.lua")
    if not os.path.isfile(table):
        problems.append("UI/Assets.lua is missing")
        return
    with open(table, encoding="utf-8") as f:
        text = f.read()
    if make_icons.ATLAS_NAME not in text:
        problems.append(f"UI/Assets.lua does not list {atlas}")
    cell = re.search(rf'{re.escape(make_icons.ATLAS_NAME)}",[^}}]*cell\s*=\s*(\d+)', text)
    if not cell or int(cell.group(1)) != make_icons.CELL:
        problems.append(f"UI/Assets.lua: the cell of {atlas} is not {make_icons.CELL} (tools/make_icons.py)")
    for name, want in (("glyphs", make_icons.GLYPHS), ("filledGlyphs", make_icons.FILLED)):
        if re.findall(r'"(\w+)"', lua_table(text, name)) != want:
            problems.append(f"UI/Assets.lua: Assets.{name} differs from the list of tools/make_icons.py (same names, same order)")
    if dict(re.findall(r'(\w+)\s*=\s*"(\w+)"', lua_table(text, "iconNames"))) != make_icons.NAMES:
        problems.append("UI/Assets.lua: Assets.iconNames differs from NAMES of tools/make_icons.py")
    third = os.path.join(ROOT, "docs", "third-party.md")
    if os.path.isfile(third):
        with open(third, encoding="utf-8") as f:
            notices = f.read()
        for what in ("Material Symbols", "Apache License 2.0", make_icons.REPOSITORY, make_icons.COMMIT,
                     make_icons.ATLAS_NAME):
            if what not in notices:
                problems.append(f"docs/third-party.md: the licence entry of the icons does not say {what!r}")


def check_embeds(embeds, problems):
    base = os.path.dirname(embeds)
    with open(embeds, encoding="utf-8") as f:
        text = f.read()
    for kind, rel in re.findall(r'<(Script|Include)\s+file="([^"]+)"', text):
        if re.split(r"[\\/]", rel)[0] == "Libs" and not os.path.isdir(os.path.join(ADDON, "Libs")):
            continue   # libraries are fetched, not committed
        target = _path(base, rel)
        if not os.path.isfile(target):
            problems.append(f"{os.path.relpath(embeds, ROOT)}: missing {rel}")
        elif kind == "Include" and rel.lower().endswith(".xml"):
            check_embeds(target, problems)


def lua_files():
    for sub in LUA_DIRS:
        for folder, _, names in os.walk(os.path.join(ADDON, sub)):
            for name in names:
                if name.endswith(".lua"):
                    yield os.path.join(folder, name)


def locale_keys(name):
    path = os.path.join(ADDON, "Locale", name)
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as f:
        return set(re.findall(r'^L\["([^"]+)"\]\s*=', f.read(), re.M))


def check_locale(problems):
    have = locale_keys("enUS.lua")
    if have is None:
        problems.append("AzerothAccord/Locale/enUS.lua is missing")
        return
    for path in lua_files():
        with open(path, encoding="utf-8") as f:
            text = f.read()
        used = set(re.findall(r'L\["([A-Za-z0-9_]+)"\]', text)) | set(re.findall(r'labelKey\s*=\s*"(\w+)"', text))
        for key in sorted(used - have):
            problems.append(f"{os.path.relpath(path, ROOT)}: L[\"{key}\"] has no string in Locale/enUS.lua")
    italian = locale_keys("itIT.lua")
    if italian is None:
        problems.append("AzerothAccord/Locale/itIT.lua is missing")
        return
    for key in sorted(italian - have):
        problems.append(f"Locale/itIT.lua: L[\"{key}\"] is not an English key (typo?)")
    for key in sorted(have - italian):
        problems.append(f"Locale/itIT.lua: L[\"{key}\"] has no Italian string (ADR 0015: the interface is in English and Italian)")


def read_toc():
    with open(TOC, encoding="utf-8") as f:
        lines = f.read().splitlines()
    meta, files = {}, []
    for line in lines:
        m = re.match(r"^##\s*([\w-]+)\s*:\s*(.*)$", line)
        if m:
            meta[m.group(1)] = m.group(2).strip()
        elif line.strip() and not line.startswith("#"):
            files.append(line.strip())
    return meta, files


def check(problems):
    if not os.path.isfile(TOC):
        problems.append("AzerothAccord/AzerothAccord.toc is missing")
        return
    meta, files = read_toc()
    if meta.get("Interface") != INTERFACE:
        problems.append(f"TOC Interface is {meta.get('Interface')!r}, expected {INTERFACE}")
    for key in REQUIRED_TOC_KEYS:
        if not meta.get(key):
            problems.append(f"TOC is missing ## {key}")
    for key, value in SAVED.items():
        if meta.get(key) and meta[key] != value:
            problems.append(f"TOC ## {key} is {meta[key]!r}, expected {value!r} (SPEC-01 §4)")
    if not files:
        problems.append("TOC lists no files")
    for rel in files:
        if not os.path.isfile(_path(ADDON, rel)):
            problems.append(f"TOC lists a missing file: {rel}")
        elif rel.lower().endswith("embeds.xml"):
            check_embeds(_path(ADDON, rel), problems)
    listed = {f.replace("\\", "/") for f in files}
    for path in lua_files():
        rel = os.path.relpath(path, ADDON).replace(os.sep, "/")
        if rel not in listed:
            problems.append(f"AzerothAccord/{rel} is not listed in the TOC")
    if not os.path.isfile(os.path.join(ADDON, "Bindings.xml")):
        problems.append("AzerothAccord/Bindings.xml is missing")
    check_locale(problems)
    check_media(problems)
    check_asset_sizes(problems)
    check_icons(problems)
    if not (meta.get("IconTexture") or "").lower().endswith("media\\logo_64"):
        problems.append("TOC ## IconTexture must be the addon's logo (Interface\\AddOns\\AzerothAccord\\Media\\logo_64, M6.9)")


KIT_FILES = ("Core", "Controls", "DataTable", "ThinBar", "Tooltip")
KIT_TEXT = re.compile(r"""SetText\(\s*(["'])[^"']*[A-Za-z]""")
KIT_COLOUR = re.compile(r"\b(SetVertexColor|SetColorTexture|SetTextColor)\(\s*[-0-9.]")


def check_widget_kit(problems):
    """The widget kit of M6.11 (UI/Widgets/Core, Controls, DataTable, ThinBar, Tooltip): a widget never contains a
    sentence (every text comes from the caller, already translated) and writes no colour of its own (every colour is a
    theme token); the one exception is the white of the hover layer, marked `theme-ok`."""
    for name in KIT_FILES:
        path = os.path.join(ADDON, "UI", "Widgets", name + ".lua")
        if not os.path.isfile(path):
            problems.append(f"AzerothAccord/UI/Widgets/{name}.lua is missing (the widget kit, M6.11)")
            continue
        with open(path, encoding="utf-8") as f:
            for number, line in enumerate(f.read().splitlines(), 1):
                code = line.split("--", 1)[0]
                where = f"AzerothAccord/UI/Widgets/{name}.lua:{number}"
                if KIT_TEXT.search(code):
                    problems.append(f"{where}: a widget writes its own text; the caller passes every text")
                if KIT_COLOUR.search(code) and "theme-ok" not in line:
                    problems.append(f"{where}: a colour written in a widget; use a theme token (Theme.Tint, Theme.Fill, Theme.Text)")


# Colours written as values (M6.14, as in FDCP): a hex colour, a |c escape, or numbers given to a colour setter or to a
# GameTooltip line. Only the code part of a line is read (not the comment).
HARD_COLOURS = (
    (re.compile(r"#[0-9A-Fa-f]{6}\b"), "a hex colour"),
    (re.compile(r"\|c[0-9A-Fa-f]{8}"), "a |c colour escape"),
    (re.compile(r"\b(?:SetColorTexture|SetVertexColor|SetTextColor|SetShadowColor|SetGradient|CreateColor)\s*\(\s*-?\.?[0-9]"),
     "a colour given as numbers"),
    (re.compile(r"\bAdd(?:Double)?Line\s*\(.*,\s*-?\.?[0-9][0-9.]*\s*,\s*-?\.?[0-9][0-9.]*\s*,\s*-?\.?[0-9]"),
     "a tooltip line coloured with numbers"),
)


def check_ui_colours(problems):
    """Every colour of the interface comes from UI/Theme.lua (M6.14, as in FDCP): the other files of UI/ tint through
    Theme.Tint / Fill / Text / Call / ClassText / TextRGB / GameColor. A line that must give the engine a colour of its own
    (the white of a hover layer) says so with `theme-ok`."""
    ui = os.path.join(ADDON, "UI")
    for folder, _, names in os.walk(ui):
        for name in sorted(names):
            if not name.endswith(".lua") or (name == "Theme.lua" and folder == ui):
                continue
            path = os.path.join(folder, name)
            rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
            with open(path, encoding="utf-8") as f:
                for number, line in enumerate(f.read().splitlines(), 1):
                    if "theme-ok" in line:
                        continue
                    code = line.split("--", 1)[0]
                    for pattern, what in HARD_COLOURS:
                        if pattern.search(code):
                            problems.append(f"{rel}:{number}: {what} outside UI/Theme.lua (use a theme token, or mark the line theme-ok)")


def check_report_form(problems):
    """The bug report form asks for the facts the /accord debug report starts with, under the same names (M6.4): every
    header line of Core/Diagnostics.lua is named in .github/ISSUE_TEMPLATE/bug_report.yml, and the form says to paste
    the report."""
    diag = os.path.join(ADDON, "Core", "Diagnostics.lua")
    form = os.path.join(ROOT, ".github", "ISSUE_TEMPLATE", "bug_report.yml")
    if not (os.path.isfile(diag) and os.path.isfile(form)):
        return
    with open(diag, encoding="utf-8") as f:
        header = re.search(r"function Diag\.HeaderLines\(\).*?\nend\n", f.read(), re.S)
    if not header:
        problems.append("Core/Diagnostics.lua: Diag.HeaderLines not found")
        return
    keys = re.findall(r'\("([a-z][a-z ]*): %s', header.group(0))
    with open(form, encoding="utf-8") as f:
        text = f.read()
    if not keys:
        problems.append("Core/Diagnostics.lua: no header line found in Diag.HeaderLines")
    for key in keys:
        if key in ("interface", "project id"):   # the build line carries them; the form asks for the client once
            continue
        if f"`{key}:`" not in text:
            problems.append(f".github/ISSUE_TEMPLATE/bug_report.yml does not name the report line `{key}:` (M6.4)")
    if "/accord debug" not in text:
        problems.append(".github/ISSUE_TEMPLATE/bug_report.yml does not tell the player to paste /accord debug")


def main():
    problems = []
    check(problems)
    check_report_form(problems)
    check_widget_kit(problems)
    check_ui_colours(problems)
    for p in problems:
        print(p)
    print(f"Addon check: {len(problems)} problem(s).")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
