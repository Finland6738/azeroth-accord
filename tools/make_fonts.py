"""Provides the fonts of AzerothAccord/Media/Fonts/ (M6.9, docs/specs/ui-style.md section 4).

Adapted from FinlandDragonCreditPoints (tools/make_fonts.py), same owner, GPL-3.0 (ADR 0021).

  * Outfit (Regular, Medium, SemiBold) and JetBrains Mono (Regular, Medium): static instances cut from the variable
    fonts of the google/fonts repository and reduced to the Latin subset the addon needs, each with the OFL.txt of its
    family. Neither family declares a Reserved Font Name, so a modified (subset) file may keep the name.
  * Orbitron Bold: the file of the original author (theleagueof/orbitron), shipped WHOLE AND UNMODIFIED, because its
    OFL.txt declares the Reserved Font Name "Orbitron" (a modified version could not use it).

The files are the exact output of FDCP's tool: by default this script COPIES them byte for byte from the sibling
repository (../finland-dragon-credit-points, read only), so it needs no network and running it twice changes nothing.
The cut itself (fontTools plus a download) is still in FDCP's make_fonts.py; docs/third-party.md records the origin.

Usage: python -X utf8 tools/make_fonts.py [path to FDCP's Media/Fonts folder]
"""
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "AzerothAccord", "Media", "Fonts")
DEFAULT_SOURCE = os.path.join(os.path.dirname(ROOT), "finland-dragon-credit-points", "FinlandDragonCreditPoints",
                              "Media", "Fonts")
FILES = ["Outfit-Regular.ttf", "Outfit-Medium.ttf", "Outfit-SemiBold.ttf", "Outfit-OFL.txt",
         "JetBrainsMono-Regular.ttf", "JetBrainsMono-Medium.ttf", "JetBrainsMono-OFL.txt",
         "Orbitron-Bold.ttf", "Orbitron-OFL.txt"]


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SOURCE
    os.makedirs(OUT, exist_ok=True)
    for name in FILES:
        src = os.path.join(source, name)
        if not os.path.isfile(src):
            print(f"missing source file: {src}")
            return 1
        with open(src, "rb") as f:
            data = f.read()
        dest = os.path.join(OUT, name)
        old = None
        if os.path.isfile(dest):
            with open(dest, "rb") as f:
                old = f.read()
        if old != data:
            with open(dest, "wb") as f:
                f.write(data)
        print(f"{name}: {len(data)} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
