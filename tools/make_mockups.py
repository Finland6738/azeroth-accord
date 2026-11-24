"""Generates the design-preview images of the whole interface into docs/specs/mockups/previews/ (one image per case).

Adapted from Azeroth Guild Finder (tools/make_mockups.py), same owner, GPL-3.0 (ADR 0018), and, for the look (M6.16), from the
mockup tools of Finland Dragon Credit Points (ADR 0021). Every image is drawn from the addon's own layout and texts (UI/*.lua,
Locale/enUS.lua and itIT.lua) in the new look of the widget kit (docs/specs/ui-style.md; the style sheet is
docs/specs/mockups/html/accord.css, written from tools/mockup_lib.py): Nebula for most, a few in Aurora and Accord. Original art
only (CSS shapes and inline SVG; the pictures are the addon's logo and the NEBULA logos of assets/; the fonts are the addon's
own; nothing loaded from the network) and invented characters, guild and items. Nothing has been run in the real WoW client yet,
so each image carries a "Design preview" strip at the bottom.

Usage:
    python -X utf8 tools/make_mockups.py              all images
    python -X utf8 tools/make_mockups.py bank         only the images whose name contains the text
    python -X utf8 tools/make_mockups.py --index      only rewrite docs/specs/mockups/previews/README.md (no browser needed)
    python -X utf8 tools/make_mockups.py --html       write the pages next to the images (for looking at them in a browser)
    python -X utf8 tools/make_mockups.py --spec       write the style sheet and the annotated pages of docs/specs/mockups/html/ (then bash docs/specs/mockups/render.sh)

Needs headless Chrome or Edge (the CHROME environment variable overrides the search) and Pillow (it writes the WebP files).
The scenes are in tools/mockup_scenes.py and tools/mockup_scenes2.py, the building blocks in tools/mockup_lib.py.
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(HERE)
CSS_DIR = os.path.join(ROOT, "docs", "specs", "mockups", "html")
OUT = os.path.join(ROOT, "docs", "specs", "mockups", "previews")
W, H, STRIP = 1200, 720, 34

STRIPS = {
    "enUS": ("DESIGN PREVIEW", "Not a screenshot: nothing has run in WoW Forever yet"),
    "itIT": ("ANTEPRIMA DI PROGETTO", "Non è uno screenshot: nulla è ancora stato provato in WoW Forever"),
}


def page(name, caption, body, lang="enUS", theme="nebula"):
    label, note = STRIPS[lang]
    return f"""<!doctype html><html lang="{lang[:2]}" data-theme="{theme}"><head><meta charset="utf-8"><title>{name}</title>
<link rel="stylesheet" href="{{CSS}}/accord.css"></head>
<body><div class="stage">{body}</div>
<div class="dp"><b>{label}</b><span class="cap">{caption}</span><span class="r">{note}</span></div></body></html>"""


ASSETS_URL = "file:///" + os.path.join(ROOT, "assets").replace("\\", "/")


def find_browser():
    pf, pf86 = os.environ.get("ProgramFiles", ""), os.environ.get("ProgramFiles(x86)", "")
    for p in [os.environ.get("CHROME", ""), os.path.join(pf, "Google", "Chrome", "Application", "chrome.exe"),
              os.path.join(pf86, "Google", "Chrome", "Application", "chrome.exe"), os.path.join(pf86, "Microsoft", "Edge", "Application", "msedge.exe"),
              os.path.join(pf, "Microsoft", "Edge", "Application", "msedge.exe"), "/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser",
              "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"]:
        if p and os.path.exists(p):
            return p
    for n in ("google-chrome", "chromium", "chrome", "msedge"):
        if shutil.which(n):
            return shutil.which(n)
    sys.exit("No Chrome or Edge found: set the CHROME environment variable to its path.")


def to_webp(png, webp):
    """The browser's PNG becomes a lossy WebP (quality 80): flat dark panels and text stay sharp at a few tens of KB."""
    from PIL import Image
    Image.open(png).convert("RGB").save(webp, "WEBP", quality=80, method=6)
    os.remove(png)


GROUP_ORDER = ["The Accord tab", "Roster and member card", "Professions", "Reputation", "Guild bank", "Settings, Info and diagnostics", "Other themes", "Italian interface"]


def group_of(name):
    if name.endswith(("-aurora", "-accord")):
        return "Other themes"
    for pre, g in [("accord-", "The Accord tab"), ("window-", "The Accord tab"), ("roster", "Roster and member card"), ("member-", "Roster and member card"),
                   ("professions", "Professions"), ("recipes", "Professions"), ("reputation", "Reputation"), ("bank", "Guild bank"),
                   ("settings", "Settings, Info and diagnostics"), ("about", "Settings, Info and diagnostics"), ("diagnostics", "Settings, Info and diagnostics"), ("notices", "Guild bank"),
                   ("it-", "Italian interface")]:
        if name.startswith(pre):
            return g
    return "Other"


def write_index(rows):
    lines = ["# Interface previews", "",
             "One image for each main view of the Azeroth Accord interface, so you can see what the addon looks like before you install it.", "",
             "> **Design previews, not screenshots.** They are drawn from the addon's own layout and texts (`UI/*.lua`, `Locale/enUS.lua`, `Locale/itIT.lua`) "
             "in the new look of the interface (the widget kit and the theme: Nebula, the default, and a few in Aurora and Accord), with original art "
             "(CSS shapes, the addon's logo and the fonts it ships: no game screenshot, icon or texture is used) and invented "
             "characters, guild and items. Nothing has been run in the WoW Forever client yet, so the real window may differ in small details "
             "(fonts, textures, exact spacing). Every image says so in its bottom strip.", "",
             "The images are generated by `tools/make_mockups.py` (`python -X utf8 tools/make_mockups.py`): rerun it after a change of the interface. "
             "The scenes are in `tools/mockup_scenes.py` and `tools/mockup_scenes2.py`; the design system and the annotated screens are in "
             "[`../html/`](../html/) and [`../img/`](../img/); [`../compare/`](../compare/README.md) puts them beside the previews of Finland Dragon Credit Points.", ""]
    groups = {}
    for name, cap in rows:
        groups.setdefault(group_of(name), []).append((name, cap))
    for title in GROUP_ORDER:
        items = groups.get(title)
        if not items:
            continue
        lines += [f"## {title}", "", "| Preview | What it shows |", "|---|---|"]
        for name, cap in items:
            lines.append(f"| [![{cap}]({name}.webp)]({name}.webp) | **{name}**<br>{cap} |")
        lines.append("")
    with open(os.path.join(OUT, "README.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def render_scene(scene):
    import mockup_lib
    name, caption, fn, lang, theme = scene
    mockup_lib.set_lang(lang)
    try:
        return page(name, caption, fn(), lang, theme)
    finally:
        mockup_lib.set_lang("enUS")


def write_spec_pages():
    import mockup_lib
    import mockup_spec
    folder = os.path.join(ROOT, "docs", "specs", "mockups", "html")
    with open(os.path.join(folder, "accord.css"), "w", encoding="utf-8", newline="\n") as f:
        f.write(mockup_lib.css())
    print("accord.css")
    for name, html in mockup_spec.pages().items():
        with open(os.path.join(folder, name + ".html"), "w", encoding="utf-8", newline="\n") as f:
            f.write(html)
        print(f"{name}.html")


def check(problems):
    """Called by tools/check_docs.py (no browser): every scene builds from the addon's locale tables (a key that was renamed
    or removed breaks the preview that uses it) and has its image, and the annotated pages build too."""
    try:
        import mockup_scenes2  # noqa: F401
        import mockup_spec
        from mockup_scenes import SCENES
        import mockup_lib
        names = [s[0] for s in SCENES]
        if len(names) != len(set(names)):
            problems.append("tools/make_mockups.py: two scenes have the same name")
        css_file = os.path.join(CSS_DIR, "accord.css")
        if not os.path.isfile(css_file) or open(css_file, encoding="utf-8", newline="").read() != mockup_lib.css():
            problems.append("docs/specs/mockups/html/accord.css is out of date: run python -X utf8 tools/make_mockups.py --spec")
        known = {s[0] + ".webp" for s in SCENES} | {"README.md"}
        for f in sorted(os.listdir(OUT)):
            if f not in known:
                problems.append(f"docs/specs/mockups/previews/{f} is not made by tools/make_mockups.py (an obsolete file: delete it)")
        for scene in SCENES:
            html = render_scene(scene)
            if len(html) < 2000:
                problems.append(f"tools/make_mockups.py: the scene {scene[0]} is almost empty")
            if not os.path.isfile(os.path.join(OUT, scene[0] + ".webp")):
                problems.append(f"docs/specs/mockups/previews/{scene[0]}.webp is missing: run python -X utf8 tools/make_mockups.py")
        if not os.path.isfile(os.path.join(ROOT, "docs", "specs", "mockups", "compare", "accord-vs-fdcp.webp")):
            problems.append("docs/specs/mockups/compare/accord-vs-fdcp.webp is missing: run python tools/make_compare.py (it needs ../finland-dragon-credit-points)")
        for name, html in mockup_spec.pages().items():
            on_disk = os.path.join(CSS_DIR, name + ".html")
            if not os.path.isfile(on_disk) or open(on_disk, encoding="utf-8", newline="").read() != html:
                problems.append(f"docs/specs/mockups/html/{name}.html is out of date: run python -X utf8 tools/make_mockups.py --spec")
            if not os.path.isfile(os.path.join(ROOT, "docs", "specs", "mockups", "img", name + ".webp")):
                problems.append(f"docs/specs/mockups/img/{name}.webp is missing: run bash docs/specs/mockups/render.sh")
    except Exception as e:  # noqa: BLE001 - a broken generator is a problem to report, not a crash
        problems.append(f"tools/make_mockups.py: the scenes do not build: {type(e).__name__}: {e}")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--spec" in sys.argv:
        import mockup_scenes2  # noqa: F401
        write_spec_pages()
        return
    import mockup_scenes2  # noqa: F401  (registers the scenes of part 2 after those of part 1)
    from mockup_scenes import SCENES
    names = [s[0] for s in SCENES]
    assert len(names) == len(set(names)), "duplicate scene names"
    os.makedirs(OUT, exist_ok=True)
    only = args[0] if args else ""
    css = "file:///" + CSS_DIR.replace("\\", "/")
    assets = ASSETS_URL
    if "--index" not in sys.argv:
        chrome = None if "--html" in sys.argv else find_browser()
        tmp = tempfile.mkdtemp(prefix="accord-mockups-")
        try:
            for scene in SCENES:
                name = scene[0]
                if only and only not in name:
                    continue
                html = render_scene(scene).replace("{CSS}", css).replace("{ASSETS}", assets)
                if chrome is None:
                    with open(os.path.join(OUT, name + ".html"), "w", encoding="utf-8", newline="\n") as f:
                        f.write(html)
                    print(f"{name}.html")
                    continue
                src = os.path.join(tmp, name + ".html")
                with open(src, "w", encoding="utf-8", newline="\n") as f:
                    f.write(html)
                out = os.path.join(tmp, name + ".png")
                subprocess.run([chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1", "--allow-file-access-from-files",
                                f"--window-size={W},{H + STRIP}", "--virtual-time-budget=3000", f"--screenshot={out}", "file:///" + src.replace("\\", "/")],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=120)
                to_webp(out, os.path.join(OUT, name + ".webp"))
                print(f"{name}.webp  {os.path.getsize(os.path.join(OUT, name + '.webp')) // 1024} KB")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    write_index([(n, c) for n, c, _, _, _ in SCENES])
    print(f"{len(SCENES)} scenes, index written to docs/specs/mockups/previews/README.md")


if __name__ == "__main__":
    main()
