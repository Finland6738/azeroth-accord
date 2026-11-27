"""Generates the textures of AzerothAccord/Media/ (M6.9, docs/specs/ui-style.md sections 3 and 7).

Adapted from FinlandDragonCreditPoints (tools/make_media.py), same owner, GPL-3.0 (ADR 0021).

Every shape is WHITE with an alpha channel: the addon tints it with the colour of a theme token (SetVertexColor), so no
file belongs to a theme. All files are 32-bit uncompressed TGA with power-of-two sizes.

  rr_fill_4/8/12/16/18/28  64x64  filled rounded rectangle, 9-slice (margin = radius); 4, 16 and 28 are the M3 shape
                                   scale of docs/specs/ui-style.md section 9.3 (M12.6)
  rr_ring_4/8/12/16/18/28  64x64  1 px ring of the same shape, 9-slice
  rr_fill_20, rr_ring_20    64x64  the full shape of a 40 pt control (ui-style.md section 9.6, M12.7)
  rr_ring2_4, rr_ring2_16   64x64  2 px rings: the focused field, the outline of the switch that is off (M12.7)
  shadow            128x128  blurred rounded rectangle for the soft shadow under windows and cards, 9-slice
  glow_s, glow_l    128x128  blurred rounded rectangle for the neon / amber glow (ADD blend), 9-slice
  pill              64x32    pill (half-circle ends), 9-slice on the left and right
  circle            64x64    filled circle
  blob_radial       128x128  radial fall-off for generated covers and soft spots
  logo_256, logo_64          the addon logo from assets/logo-source.webp
  nebula_dark_256, nebula_light_256
                             the NEBULA guild logos for the credits (assets/nebula-logo-dark.png / -light.png, used with
                             the guild's permission): 256 wide, aspect ratio kept by padding with transparency

Usage: python -X utf8 tools/make_media.py   (needs Pillow; rewrites the files; the committed result is what ships)
The list of files and their slice margins is mirrored in AzerothAccord/UI/Assets.lua (M6.10), which
tools/check_addon.py compares with the folder. The icons are not made here: tools/make_icons.py builds their atlas from
Material Symbols (M13.6).
"""
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "AzerothAccord", "Media")
SS = 4   # supersampling


def white(mask):
    img = Image.new("RGBA", mask.size, (255, 255, 255, 0))
    img.putalpha(mask)
    return img


def rounded(size, radius, inset=0.0, ring=0.0):
    w, h = size
    big = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(big)
    box = [inset * SS, inset * SS, (w - inset) * SS - 1, (h - inset) * SS - 1]
    d.rounded_rectangle(box, radius=radius * SS, fill=255)
    if ring:
        inner = Image.new("L", big.size, 0)
        di = ImageDraw.Draw(inner)
        k = ring * SS
        di.rounded_rectangle([box[0] + k, box[1] + k, box[2] - k, box[3] - k], radius=max(0, (radius - ring)) * SS, fill=255)
        big = ImageChops.subtract(big, inner)
    return big.resize(size, Image.LANCZOS)


def blurred(size, radius, inset, blur):
    mask = rounded(size, radius, inset)
    return mask.filter(ImageFilter.GaussianBlur(blur))


def circle(size):
    big = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(big).ellipse([0, 0, size * SS - 1, size * SS - 1], fill=255)
    return big.resize((size, size), Image.LANCZOS)


def radial(size):
    img = Image.new("L", (size, size), 0)
    c = (size - 1) / 2
    px = img.load()
    for y in range(size):
        for x in range(size):
            d = (((x - c) ** 2 + (y - c) ** 2) ** 0.5) / c
            v = max(0.0, 1.0 - d)
            px[x, y] = int(255 * v * v * (3 - 2 * v))   # smoothstep
    return img


def save(img, name):
    path = os.path.join(OUT, name + ".tga")
    img.save(path, compression=None)   # uncompressed 32-bit
    return path


def fit_width(img, width):
    """Scales to `width`, keeps the aspect ratio and pads with transparency up to the next power of two in height."""
    img = img.convert("RGBA")
    h = max(1, round(img.height * width / img.width))
    img = img.resize((width, h), Image.LANCZOS)
    tall = 1
    while tall < h:
        tall *= 2
    out = Image.new("RGBA", (width, tall), (0, 0, 0, 0))
    out.paste(img, (0, (tall - h) // 2))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    made = []
    for r in (4, 8, 12, 16, 18, 28):
        made.append(save(white(rounded((64, 64), r)), f"rr_fill_{r}"))
        made.append(save(white(rounded((64, 64), r, ring=1.0)), f"rr_ring_{r}"))
    made.append(save(white(rounded((64, 64), 20)), "rr_fill_20"))
    made.append(save(white(rounded((64, 64), 20, ring=1.0)), "rr_ring_20"))
    for r in (4, 16):
        made.append(save(white(rounded((64, 64), r, ring=2.0)), f"rr_ring2_{r}"))
    made.append(save(white(blurred((128, 128), 18, 40, 9)), "shadow"))
    made.append(save(white(blurred((128, 128), 14, 46, 5)), "glow_s"))
    made.append(save(white(blurred((128, 128), 20, 34, 12)), "glow_l"))
    made.append(save(white(rounded((64, 32), 16)), "pill"))
    made.append(save(white(circle(64)), "circle"))
    made.append(save(white(radial(128)), "blob_radial"))
    logo = Image.open(os.path.join(ROOT, "assets", "logo-source.webp")).convert("RGBA")
    for size in (256, 64):
        made.append(save(logo.resize((size, size), Image.LANCZOS), f"logo_{size}"))
    for theme in ("dark", "light"):
        made.append(save(fit_width(Image.open(os.path.join(ROOT, "assets", f"nebula-logo-{theme}.png")), 256),
                         f"nebula_{theme}_256"))
    total = 0
    for p in made:
        n = os.path.getsize(p)
        total += n
        print(f"{os.path.relpath(p, ROOT)}: {n} bytes")
    print(f"total {total} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
