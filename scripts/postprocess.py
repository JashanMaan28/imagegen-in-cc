#!/usr/bin/env python3
"""Image post-processing for the imagegen plugin.

Subcommands:
  transparent <in> [out]                      key white background to real alpha (in place if no out)
  convert <in> <out> [--max-width N] [--quality Q] [--crop WxH]
                                              convert by output extension (webp/jpeg/png), resize, center-crop
  favicon <in> <outdir>                       emit favicon.ico, favicon-16/32.png, apple-touch-icon.png
  placeholder <out> --size WxH [--label TEXT] [--color #RRGGBB]
                                              instant zero-cost placeholder PNG

All subcommands except `placeholder` require Pillow (pip3 install pillow).
`placeholder` degrades to a stdlib-only solid PNG when Pillow is missing.
"""
import sys
import argparse


def need_pil():
    try:
        from PIL import Image  # noqa: F401
        return True
    except ImportError:
        sys.exit("error: this operation needs Pillow — install with: pip3 install --user pillow")


def white_unmix(img):
    """Convert a subject-on-white image to RGBA with proper alpha un-mixing."""
    from PIL import Image
    img = img.convert("RGB")
    px = img.load()
    out = Image.new("RGBA", img.size)
    opx = out.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b = px[x, y]
            a = max(255 - r, 255 - g, 255 - b) / 255.0
            if a < 0.03:
                opx[x, y] = (0, 0, 0, 0)
                continue
            fr = int(min(255, max(0, (r - 255 * (1 - a)) / a)))
            fg = int(min(255, max(0, (g - 255 * (1 - a)) / a)))
            fb = int(min(255, max(0, (b - 255 * (1 - a)) / a)))
            opx[x, y] = (fr, fg, fb, int(a * 255))
    return out


def cmd_transparent(args):
    need_pil()
    from PIL import Image
    out = white_unmix(Image.open(args.input))
    bbox = out.getchannel("A").getbbox()
    if bbox:
        cropped = out.crop(bbox)
        pad = int(max(cropped.size) * 0.04)
        canvas = Image.new("RGBA", (cropped.width + 2 * pad, cropped.height + 2 * pad), (0, 0, 0, 0))
        canvas.paste(cropped, (pad, pad))
        out = canvas
    dest = args.output or args.input
    if not dest.lower().endswith(".png"):
        sys.exit("error: transparent output must be .png")
    out.save(dest)
    print(f"transparent: {dest} {out.size[0]}x{out.size[1]}")


def cmd_convert(args):
    need_pil()
    from PIL import Image
    img = Image.open(args.input)
    if args.crop:
        tw, th = (int(v) for v in args.crop.lower().split("x"))
        scale = max(tw / img.width, th / img.height)
        img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
        left, top = (img.width - tw) // 2, (img.height - th) // 2
        img = img.crop((left, top, left + tw, top + th))
    if args.max_width and img.width > args.max_width:
        img = img.resize((args.max_width, round(img.height * args.max_width / img.width)), Image.LANCZOS)
    ext = args.output.rsplit(".", 1)[-1].lower()
    save_kwargs = {}
    if ext in ("jpg", "jpeg"):
        img = img.convert("RGB")
        save_kwargs["quality"] = args.quality
        save_kwargs["optimize"] = True
    elif ext == "webp":
        save_kwargs["quality"] = args.quality
        save_kwargs["method"] = 6
    elif ext == "png":
        save_kwargs["optimize"] = True
    else:
        sys.exit(f"error: unsupported output format .{ext} (use png, webp, or jpeg)")
    img.save(args.output, **save_kwargs)
    import os
    print(f"convert: {args.output} {img.size[0]}x{img.size[1]} ({os.path.getsize(args.output)} bytes)")


def cmd_favicon(args):
    need_pil()
    import os
    from PIL import Image
    img = Image.open(args.input).convert("RGBA")
    # square it on a transparent canvas before scaling down
    side = max(img.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - img.width) // 2, (side - img.height) // 2))
    os.makedirs(args.outdir, exist_ok=True)
    outputs = []
    for name, px in (("favicon-16.png", 16), ("favicon-32.png", 32), ("apple-touch-icon.png", 180)):
        path = os.path.join(args.outdir, name)
        canvas.resize((px, px), Image.LANCZOS).save(path)
        outputs.append(path)
    ico = os.path.join(args.outdir, "favicon.ico")
    canvas.resize((48, 48), Image.LANCZOS).save(ico, sizes=[(16, 16), (32, 32), (48, 48)])
    outputs.append(ico)
    print("favicon set:", ", ".join(outputs))


def _stdlib_solid_png(path, w, h, rgb):
    """Write a solid-color PNG with zlib+struct only (no Pillow)."""
    import struct
    import zlib

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)

    row = b"\x00" + bytes(rgb) * w
    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(row * h))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def cmd_placeholder(args):
    w, h = (int(v) for v in args.size.lower().split("x"))
    if args.color:
        rgb = tuple(int(args.color.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
    else:
        # deterministic muted pastel from the label
        hue = sum(bytearray((args.label or args.out).encode())) % 360
        import colorsys
        rgb = tuple(int(c * 255) for c in colorsys.hls_to_rgb(hue / 360, 0.85, 0.35))
    try:
        from PIL import Image, ImageDraw
        img = Image.new("RGB", (w, h), rgb)
        draw = ImageDraw.Draw(img)
        border = tuple(max(0, c - 40) for c in rgb)
        draw.rectangle([0, 0, w - 1, h - 1], outline=border, width=max(2, w // 200))
        draw.line([0, 0, w - 1, h - 1], fill=border, width=max(1, w // 400))
        draw.line([w - 1, 0, 0, h - 1], fill=border, width=max(1, w // 400))
        text = f"{args.label + ' — ' if args.label else ''}{w}x{h}"
        tw = draw.textlength(text)
        pad_w, pad_h = int(tw) + 24, 36
        cx, cy = (w - pad_w) // 2, (h - pad_h) // 2
        draw.rectangle([cx, cy, cx + pad_w, cy + pad_h], fill=(255, 255, 255))
        draw.text((cx + 12, cy + 12), text, fill=(60, 60, 60))
        img.save(args.out)
    except ImportError:
        _stdlib_solid_png(args.out, w, h, rgb)
    print(f"placeholder: {args.out} {w}x{h}")


def main():
    p = argparse.ArgumentParser(prog="postprocess.py")
    sub = p.add_subparsers(dest="cmd", required=True)

    t = sub.add_parser("transparent")
    t.add_argument("input")
    t.add_argument("output", nargs="?")
    t.set_defaults(fn=cmd_transparent)

    c = sub.add_parser("convert")
    c.add_argument("input")
    c.add_argument("output")
    c.add_argument("--max-width", type=int)
    c.add_argument("--quality", type=int, default=85)
    c.add_argument("--crop")
    c.set_defaults(fn=cmd_convert)

    f = sub.add_parser("favicon")
    f.add_argument("input")
    f.add_argument("outdir")
    f.set_defaults(fn=cmd_favicon)

    pl = sub.add_parser("placeholder")
    pl.add_argument("out")
    pl.add_argument("--size", required=True)
    pl.add_argument("--label", default="")
    pl.add_argument("--color")
    pl.set_defaults(fn=cmd_placeholder)

    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
