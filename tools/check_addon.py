"""Offline checks of the addon folder: TOC interface and fields, listed files, embeds.xml (Libs only when fetched),
Bindings.xml, and the locale tables.

Adapted from Azeroth Guild Finder (tools/check_addon.py), same owner, GPL-3.0 (ADR 0018). Azeroth Accord has no media
of its own (it uses the client's textures, SPEC-04 §5), so the texture and font checks of the original are left out.

Locale rules (ADR 0015): every L["KEY"] used in the code has an English string in Locale/enUS.lua (AceLocale answers
with the key itself for a missing one, which would hide the mistake), and Locale/itIT.lua defines no key that English
does not have (a typo there would silently never show).

Usage: python -I -X utf8 tools/check_addon.py (also called by tools/check_docs.py)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "AzerothAccord")
TOC = os.path.join(ADDON, "AzerothAccord.toc")
INTERFACE = "16001"
REQUIRED_TOC_KEYS = ("Title", "Author", "Version", "SavedVariables", "SavedVariablesPerCharacter",
                     "AddonCompartmentFunc")
SAVED = {"SavedVariables": "AzerothAccordDB", "SavedVariablesPerCharacter": "AzerothAccordCharDB"}
LUA_DIRS = ("Core", "Data", "Net", "UI")


def _path(base, rel):
    return os.path.join(base, *re.split(r"[\\/]", rel.strip()))


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


def main():
    problems = []
    check(problems)
    for p in problems:
        print(p)
    print(f"Addon check: {len(problems)} problem(s).")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
