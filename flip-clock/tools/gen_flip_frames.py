#!/usr/bin/env python3
"""Generate flip-clock animation frames as PNGs.

A single set of single-digit cards is written under <out>/n/ with cyclic
transitions (next of 9 is 0). Layouts compose multi-digit values by
placing several <img> tags side by side, picking each digit via the
per-digit placeholders exposed by the runtime ({h1}, {h2}, {i1}, ...).

Each (digit, frame) PNG follows `{digit}_{frame}.png` with frames 0..25
(frame 0 = rest, 1..25 = ease-in-quad rotation curve).
"""
import argparse
import math
import os
import shutil

from PIL import Image, ImageDraw, ImageFont


BG_TOP = (32, 32, 32, 255)
BG_BOTTOM = (16, 16, 16, 255)
GAP_COLOR = (4, 4, 4, 255)
LINE_COLOR = (0, 0, 0, 255)
DIGIT_COLOR = (250, 250, 250, 255)

ANIM_FRAMES = 25
HEIGHT_RATIOS = [1.0]
for i in range(1, ANIM_FRAMES + 1):
    t = i / ANIM_FRAMES
    angle = math.pi * t * t
    HEIGHT_RATIOS.append(math.cos(angle))


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Generate flip-clock PNG frames for html-clock-plasmoid.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--width", type=int, default=120, help="card width in px")
    p.add_argument("--height", type=int, default=200, help="card height in px")
    p.add_argument(
        "--font",
        default="/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
        help="path to a TrueType font file",
    )
    p.add_argument(
        "--radius",
        type=int,
        default=8,
        help="rounded-corner radius in px (0 = sharp corners)",
    )
    p.add_argument(
        "--font-size",
        type=int,
        default=None,
        help="digit font size in px (default: 76%% of --height)",
    )
    p.add_argument(
        "--out",
        default=os.path.expanduser("~/.local/share/html-clock-flip"),
        help="output root directory; the digit set is written to <out>/n",
    )
    return p.parse_args()


def render_text_card(
    text: str,
    card_w: int,
    card_h: int,
    font: ImageFont.FreeTypeFont,
) -> Image.Image:
    """Card-sized image with `text` centered, transparent background."""
    img = Image.new("RGBA", (card_w, card_h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (card_w - tw) // 2 - bbox[0]
    ty = (card_h - th) // 2 - bbox[1]
    draw.text((tx, ty), text, font=font, fill=DIGIT_COLOR)
    return img


def render(
    current_text: str,
    next_text: str,
    frame: int,
    *,
    card_w: int,
    card_h: int,
    font: ImageFont.FreeTypeFont,
    radius: int,
    line_thick: int,
) -> Image.Image:
    img = Image.new("RGBA", (card_w, card_h), GAP_COLOR)
    mid_y = card_h // 2

    current_full = render_text_card(current_text, card_w, card_h, font)
    next_full = render_text_card(next_text, card_w, card_h, font)

    # Static back: top half of NEXT (revealed as flap rotates past 0°).
    next_top_bg = Image.new("RGBA", (card_w, mid_y), BG_TOP)
    next_top_bg.alpha_composite(next_full.crop((0, 0, card_w, mid_y)))
    img.alpha_composite(next_top_bg, (0, 0))

    # Static back: bottom half of CURRENT (covered as flap lands past 90°).
    lower = Image.new("RGBA", (card_w, card_h - mid_y), BG_BOTTOM)
    lower.alpha_composite(current_full.crop((0, mid_y, card_w, card_h)))
    img.alpha_composite(lower, (0, mid_y))

    ratio = HEIGHT_RATIOS[frame]
    h = abs(int(mid_y * ratio))
    if h > 0:
        if ratio > 0:
            flap_src = Image.new("RGBA", (card_w, mid_y), BG_TOP)
            flap_src.alpha_composite(current_full.crop((0, 0, card_w, mid_y)))
            flap_compressed = flap_src.resize((card_w, h), Image.LANCZOS)
            img.alpha_composite(flap_compressed, (0, mid_y - h))
        else:
            flap_src = Image.new("RGBA", (card_w, card_h - mid_y), BG_BOTTOM)
            flap_src.alpha_composite(next_full.crop((0, mid_y, card_w, card_h)))
            flap_compressed = flap_src.resize((card_w, h), Image.LANCZOS)
            img.alpha_composite(flap_compressed, (0, mid_y))

    line = Image.new("RGBA", (card_w, line_thick), LINE_COLOR)
    img.alpha_composite(line, (0, mid_y - line_thick))

    if radius > 0:
        mask = Image.new("L", (card_w, card_h), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, card_w - 1, card_h - 1), radius=radius, fill=255
        )
        img.putalpha(mask)

    return img


def generate_digits(
    out_dir: str,
    *,
    card_w: int,
    card_h: int,
    font: ImageFont.FreeTypeFont,
    radius: int,
    line_thick: int,
) -> int:
    if os.path.isdir(out_dir):
        shutil.rmtree(out_dir)
    os.makedirs(out_dir, exist_ok=True)
    count = 0
    for d in range(10):
        nxt = (d + 1) % 10
        for f in range(len(HEIGHT_RATIOS)):
            img = render(
                str(d), str(nxt), f,
                card_w=card_w, card_h=card_h,
                font=font, radius=radius, line_thick=line_thick,
            )
            img.save(os.path.join(out_dir, f"{d}_{f}.png"), "PNG", optimize=True)
            count += 1
    return count


def render_separator(
    char: str,
    *,
    card_w: int,
    card_h: int,
    font: ImageFont.FreeTypeFont,
    radius: int,
    line_thick: int,
) -> Image.Image:
    """Static separator card matching the digit cards' rest frame style."""
    img = Image.new("RGBA", (card_w, card_h), GAP_COLOR)
    mid_y = card_h // 2

    char_layer = render_text_card(char, card_w, card_h, font)

    top = Image.new("RGBA", (card_w, mid_y), BG_TOP)
    top.alpha_composite(char_layer.crop((0, 0, card_w, mid_y)))
    img.alpha_composite(top, (0, 0))

    bottom = Image.new("RGBA", (card_w, card_h - mid_y), BG_BOTTOM)
    bottom.alpha_composite(char_layer.crop((0, mid_y, card_w, card_h)))
    img.alpha_composite(bottom, (0, mid_y))

    line = Image.new("RGBA", (card_w, line_thick), LINE_COLOR)
    img.alpha_composite(line, (0, mid_y - line_thick))

    if radius > 0:
        mask = Image.new("L", (card_w, card_h), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, card_w - 1, card_h - 1), radius=radius, fill=255
        )
        img.putalpha(mask)
    return img


def generate_separators(
    out_dir: str,
    *,
    card_w: int,
    card_h: int,
    font: ImageFont.FreeTypeFont,
    radius: int,
    line_thick: int,
) -> int:
    if os.path.isdir(out_dir):
        shutil.rmtree(out_dir)
    os.makedirs(out_dir, exist_ok=True)
    seps = [(":", "colon"), ("/", "slash")]
    sep_w = max(1, card_w // 2)
    sep_radius = max(0, min(radius, sep_w // 2, card_h // 2))
    for char, name in seps:
        img = render_separator(
            char,
            card_w=sep_w, card_h=card_h,
            font=font, radius=sep_radius, line_thick=line_thick,
        )
        img.save(os.path.join(out_dir, f"{name}.png"), "PNG", optimize=True)
    return len(seps)


def main() -> None:
    args = parse_args()
    font_size = args.font_size if args.font_size is not None else max(8, int(args.height * 0.76))
    line_thick = max(2, args.height // 50)
    font = ImageFont.truetype(args.font, font_size)

    os.makedirs(args.out, exist_ok=True)
    # Tear down legacy pair-based sets (h, ms, dd, mm) so old PNGs don't linger.
    for legacy in ("h", "ms", "dd", "mm"):
        legacy_path = os.path.join(args.out, legacy)
        if os.path.isdir(legacy_path):
            shutil.rmtree(legacy_path)
    for fname in os.listdir(args.out):
        full = os.path.join(args.out, fname)
        if os.path.isfile(full) and fname.endswith(".png"):
            os.remove(full)

    digit_count = generate_digits(
        os.path.join(args.out, "n"),
        card_w=args.width, card_h=args.height,
        font=font, radius=args.radius, line_thick=line_thick,
    )
    sep_count = generate_separators(
        os.path.join(args.out, "sep"),
        card_w=args.width, card_h=args.height,
        font=font, radius=args.radius, line_thick=line_thick,
    )

    print(
        f"generated n/={digit_count} sep/={sep_count} "
        f"size={args.width}x{args.height} radius={args.radius} "
        f"font={args.font} font-size={font_size} -> {args.out}"
    )


if __name__ == "__main__":
    main()
