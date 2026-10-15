#!/usr/bin/env python3
"""App Store screenshots, 2880×1800 (the largest Mac App Store size).

raw/ holds full-screen captures (3600×2338) of the demo board
(make-demo-board.py, Debug build with -demoBoard YES), the nine Spaces in
raw/spaces/, SF Symbols exported to raw/sym/ and two hello wallpapers.
Every shot gets a headline; 1–3 frame a screen capture without the menu bar.
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(HERE, "raw")
W, H = 2880, 1800
FONT = "/System/Library/Fonts/SFNS.ttf"
INK, INK_SOFT = (29, 29, 31), (72, 72, 80)


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def screen(path):
    """Full-screen capture without the menu bar, as 16:10."""
    im = Image.open(path).convert("RGB")
    w, h = im.size
    keep = round(w / 1.6)
    return im.crop((0, h - keep, w, h)).resize((W, H), Image.LANCZOS)


def rounded(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), radius, fill=255)
    return mask


def shadow(canvas, box, radius, blur=30, alpha=90, dy=16):
    layer = Image.new("L", canvas.size, 0)
    x0, y0, x1, y1 = box
    ImageDraw.Draw(layer).rounded_rectangle((x0, y0 + dy, x1, y1 + dy), radius, fill=alpha)
    canvas.paste(Image.new("RGB", canvas.size, (40, 30, 70)), (0, 0), layer.filter(ImageFilter.GaussianBlur(blur)))


def headline(draw, title, subtitle, top=150, light=False):
    ink, soft = ((255, 255, 255), (215, 212, 230)) if light else (INK, INK_SOFT)
    draw.text((W / 2, top), title, font=font(112, "Bold"), fill=ink, anchor="mm")
    draw.text((W / 2, top + 108), subtitle, font=font(50, "Regular"), fill=soft, anchor="mm")


def framed(shot, wall, title, subtitle):
    """Заголовок на тёмных обоях и под ним снимок экрана в скруглённой рамке."""
    canvas = Image.open(os.path.join(RAW, wall)).convert("RGB")
    headline(ImageDraw.Draw(canvas), title, subtitle, light=True)
    sh = H - 330 - 90
    sw = round(sh * 1.6)
    im = screen(os.path.join(RAW, shot)).resize((sw, sh), Image.LANCZOS)
    x, y = (W - sw) // 2, 330
    shadow(canvas, (x, y, x + sw, y + sh), 30, blur=40, alpha=160, dy=20)
    canvas.paste(im, (x, y), rounded(im, 30))
    ImageDraw.Draw(canvas).rounded_rectangle((x, y, x + sw - 1, y + sh - 1), 30, outline=(255, 255, 255), width=2)
    return canvas


def spaces_grid():
    canvas = Image.open(os.path.join(RAW, "wall-purple-light.png")).convert("RGB")
    draw = ImageDraw.Draw(canvas)
    headline(draw, "Up to nine Spaces",
             "A separate canvas for every part of your life — switch with ⌥1–9.")
    names = ["Ideas", "Writing", "Launch", "Journal", "Travel", "Reading", "Recipes", "Finances", "Fitness"]
    tw, gap = 680, 44
    th = round(tw / 1.6)
    left = (W - 3 * tw - 2 * gap) // 2
    top = 360
    label = font(34, "Semibold")
    for i, name in enumerate(names):
        x = left + (i % 3) * (tw + gap)
        y = top + (i // 3) * (th + gap)
        thumb = screen(os.path.join(RAW, "spaces", f"{i + 1}.png")).resize((tw, th), Image.LANCZOS)
        shadow(canvas, (x, y, x + tw, y + th), 22, blur=22, alpha=70, dy=10)
        canvas.paste(thumb, (x, y), rounded(thumb, 22))
        text = f"⌥{i + 1}  {name}"
        tx0, _, tx1, _ = draw.textbbox((0, 0), text, font=label)
        pw, ph = tx1 - tx0 + 40, 58
        px, py = x + 18, y + th - ph - 18
        draw.rounded_rectangle((px, py, px + pw, py + ph), ph // 2, fill=(255, 255, 255))
        draw.text((px + 20, py + ph / 2), text, font=label, fill=INK, anchor="lm")
    return canvas


FEATURES = [
    ("sparkles", (124, 77, 255), "Ask AI", "Apple Intelligence, ChatGPT or Claude — about a card or a whole Space."),
    ("tag.fill", (255, 149, 0), "Color tags", "Seven colors, right from the keyboard with ⌃1–7."),
    ("sparkles.square.filled.on.square", (88, 86, 214), "Spoiler", "Blur a card until you’re ready to look."),
    ("lock.square.fill", (52, 120, 246), "Locked cards", "Hide a card behind your passcode or Touch ID."),
    ("icloud.fill", (10, 132, 255), "iCloud sync", "Your Spaces on every Mac, end-to-end encrypted."),
    ("externaldrive.fill", (52, 199, 89), "Backups", "Password-protected backups and Markdown export."),
    ("bolt.fill", (255, 179, 0), "Quick Capture", "Jot down a card from any app with one shortcut."),
    ("magnifyingglass", (142, 142, 147), "Spotlight", "Find any card from anywhere on your Mac."),
]


def tint(symbol, color, size):
    alpha = Image.open(os.path.join(RAW, "sym", symbol + ".png")).getchannel("A").resize((size, size), Image.LANCZOS)
    icon = Image.new("RGBA", (size, size), color + (0,))
    icon.putalpha(alpha)
    return icon


def wrap(draw, text, fnt, width):
    lines, line = [], ""
    for word in text.split():
        trial = (line + " " + word).strip()
        if draw.textlength(trial, font=fnt) <= width:
            line = trial
        else:
            lines.append(line)
            line = word
    return lines + [line]


def features_grid():
    canvas = Image.open(os.path.join(RAW, "wall-yellow-light.png")).convert("RGB")
    draw = ImageDraw.Draw(canvas)
    headline(draw, "Private, synced and smart", "Everything around your notes, built in.", top=200)
    cols, tw, th, gap = 4, 620, 520, 44
    left = (W - cols * tw - (cols - 1) * gap) // 2
    top = 430
    title_font, body_font = font(52, "Bold"), font(36, "Regular")
    for i, (symbol, color, title, body) in enumerate(FEATURES):
        x = left + (i % cols) * (tw + gap)
        y = top + (i // cols) * (th + gap)
        shadow(canvas, (x, y, x + tw, y + th), 44, blur=26, alpha=50, dy=12)
        tile = Image.new("RGB", (tw, th), (255, 255, 255))
        canvas.paste(Image.blend(canvas.crop((x, y, x + tw, y + th)), tile, 0.72), (x, y), rounded(tile, 44))
        badge = 150
        draw.rounded_rectangle((x + 56, y + 60, x + 56 + badge, y + 60 + badge), 36, fill=color)
        icon = tint(symbol, (255, 255, 255), 96)
        canvas.paste(icon, (x + 56 + (badge - 96) // 2, y + 60 + (badge - 96) // 2), icon)
        draw.text((x + 56, y + 270), title, font=title_font, fill=INK)
        for n, line in enumerate(wrap(draw, body, body_font, tw - 112)):
            draw.text((x + 56, y + 350 + n * 50), line, font=body_font, fill=INK_SOFT)
    return canvas


SHOTS = [
    lambda: framed("1-ideas.png", "wall-purple-dark.png", "Your ideas, anywhere on the canvas",
                   "Drag to create, tag by color, tidy up in one click."),
    lambda: framed("2-focus.png", "wall-yellow-dark.png", "Write in focus",
                   "Markdown that hides itself \u2014 just you and the words."),
    lambda: framed("3-locked.png", "wall-silver-dark.png", "Lock a whole Space",
                   "Private Spaces open only with your passcode or Touch ID."),
    spaces_grid,
    features_grid,
]

os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
for index, make in enumerate(SHOTS, 1):
    path = os.path.join(HERE, "out", f"{index}.png")
    make().save(path)
    print(path)
