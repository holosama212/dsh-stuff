# -*- coding: utf-8 -*-
"""contact-sheet.py - build a LABELED contact sheet (thumbnail grid) from a folder of images.

Why: on this machine there is NO ImageMagick (the system32 convert.exe is the Windows
filesystem tool, NOT ImageMagick - never call it for images). ffmpeg's `tile` builds grids
but can't easily put a per-cell filename/seed label. Pillow (bundled) can, so use this for
"batch out many images -> compare seed/prompt variants at a glance -> pick -> send full-res".

Usage:
  python contact-sheet.py <src_dir> <out.jpg> [cols] [--cell N] [--recursive]
  cols <= 0  -> auto (ceil(sqrt(n))).
Labels default to the filename stem (works in Chinese too; uses msyh.ttc).
"""
import os, sys, math, argparse
from PIL import Image, ImageDraw, ImageFont, ImageOps

DEF_FONT = r"C:\Windows\Fonts\msyh.ttc"   # Microsoft YaHei: supports CJK labels
EXTS = (".png", ".jpg", ".jpeg", ".webp", ".bmp")

def collect(src, recursive):
    if recursive:
        out = []
        for root, _, fs in os.walk(src):
            for f in fs:
                if f.lower().endswith(EXTS):
                    out.append(os.path.join(root, f))
        return sorted(out)
    return sorted(os.path.join(src, f) for f in os.listdir(src) if f.lower().endswith(EXTS))

def build(paths, out, cols=0, cell=320, pad=12, label_h=26,
          bg=(245, 245, 245), fg=(20, 20, 20), font_path=DEF_FONT, title=None):
    font = ImageFont.truetype(font_path, 18)
    tfont = ImageFont.truetype(font_path, 26)
    n = len(paths)
    if n == 0:
        raise SystemExit("no images found")
    if cols <= 0:
        cols = max(1, math.ceil(math.sqrt(n)))
    cols = min(cols, n)
    rows = math.ceil(n / cols)
    top = 46 if title else 0
    W = pad + cols * (cell + pad)
    H = top + pad + rows * (cell + label_h + pad)
    sheet = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(sheet)
    if title:
        d.text((pad, 10), title, font=tfont, fill=fg)
    for i, p in enumerate(paths):
        r, c = divmod(i, cols)
        x0 = pad + c * (cell + pad)
        y0 = top + pad + r * (cell + label_h + pad)
        d.rectangle([x0, y0, x0 + cell, y0 + cell], outline=(210, 210, 210))
        try:
            im = Image.open(p).convert("RGB")
            thumb = ImageOps.contain(im, (cell, cell), Image.LANCZOS)
            sheet.paste(thumb, (x0 + (cell - thumb.width) // 2, y0 + (cell - thumb.height) // 2))
        except Exception as e:
            d.text((x0 + 6, y0 + cell // 2), "ERR " + os.path.basename(p), font=font, fill=(200, 80, 80))
        d.text((x0 + 4, y0 + cell + 4), os.path.splitext(os.path.basename(p))[0][:44], font=font, fill=fg)
    sheet.save(out, quality=90)
    return out, sheet.size

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("out")
    ap.add_argument("cols", nargs="?", type=int, default=0)
    ap.add_argument("--cell", type=int, default=320)
    ap.add_argument("--recursive", action="store_true")
    ap.add_argument("--title", default=None)
    a = ap.parse_args()
    files = collect(a.src, a.recursive)
    print(build(files, a.out, cols=a.cols, cell=a.cell, title=a.title))
