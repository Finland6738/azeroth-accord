"""Converts the rendered mockup PNGs to WebP (about 10x smaller) and removes the PNGs.
Adapted from Azeroth Guild Finder (docs/specs/mockups/optimize_images.py), same owner, GPL-3.0 (ADR 0018).
Usage: python optimize_images.py <folder>   (every PNG under it, recursively)"""
import pathlib
import sys

from PIL import Image

for p in pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "img").rglob("*.png"):
    Image.open(p).convert("RGB").save(p.with_suffix(".webp"), "WEBP", quality=80, method=6)
    p.unlink()
