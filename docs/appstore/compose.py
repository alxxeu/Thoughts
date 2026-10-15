#!/usr/bin/env python3
"""App Store screenshots: a headline over a crop of each raw screen capture.

raw/<name>.png — full-screen captures (3600×2338) of the demo board
(make-demo-board.py, Debug build with -demoBoard YES). Output: out/<n>.png,
2880×1800 — the largest Mac App Store size.
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 2880, 1800
FONT = "/System/Library/Fonts/SFNS.ttf"

# name, crop (x, y, w, h) in raw pixels, headline, subtitle
SHOTS = [
    ("raw-1-overview", (60, 70, 3120, 1950), "Your ideas, anywhere on the canvas",
     "No folders, no lists — just space to think."),
    ("raw-2-markdown", (800, 600, 2000, 1250), "Write in Markdown",
     "Formatting shows next to the cursor and hides when you move on."),
    ("raw-4-spaces", (60, 70, 3120, 1950), "A Space for every project",
     "Switch instantly with ⌥1–9 — or ⌃⌥1–9 from any app."),
    ("raw-3-tags", (194, 760, 2095, 1309), "Tag, blur or lock any card",
     "Color tags right from the keyboard. Spoiler and Lock keep private notes private."),
    ("raw-5-ai", (996, 70, 2028, 1268), "Ask AI about your notes",
     "Apple Intelligence on your Mac, or ChatGPT and Claude with your own key."),
    ("raw-6-shortcuts", (630, 815, 2000, 1250), "Every shortcut, with a preview",
     "See what each Markdown style looks like before you use it."),
]


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def background():
    # Вертикальный градиент в цветах иконки: глубокий индиго → фиолетовый.
    top, bottom = (22, 16, 58), (58, 38, 150)
    bg = Image.new("RGB", (W, H))
    draw = ImageDraw.Draw(bg)
    for y in range(H):
        t = y / (H - 1)
        draw.line([(0, y), (W, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return bg


def compose(name, crop, title, subtitle):
    x, y, w, h = crop
    shot = Image.open(os.path.join(HERE, "raw", name + ".png")).convert("RGB").crop((x, y, x + w, y + h))

    canvas = background()
    draw = ImageDraw.Draw(canvas)
    title_font, sub_font = font(112, "Bold"), font(52, "Regular")
    draw.text((W / 2, 150), title, font=title_font, fill="white", anchor="mm")
    draw.text((W / 2, 262), subtitle, font=sub_font, fill=(205, 198, 240), anchor="mm")

    # Снимок по ширине до 2440 и по высоте до свободного места под текстом.
    top_space, bottom_margin = 350, 90
    scale = min(2440 / w, (H - top_space - bottom_margin) / h)
    sw, sh = round(w * scale), round(h * scale)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    left, top = (W - sw) // 2, top_space

    radius = 34
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw - 1, sh - 1), radius, fill=255)

    shadow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(shadow).rounded_rectangle((left, top + 24, left + sw, top + sh + 24), radius, fill=150)
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    canvas.paste(Image.new("RGB", (W, H), (8, 6, 24)), (0, 0), shadow)

    canvas.paste(shot, (left, top), mask)
    ImageDraw.Draw(canvas).rounded_rectangle((left, top, left + sw - 1, top + sh - 1), radius,
                                            outline=(96, 84, 170), width=2)
    return canvas


os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
for index, (name, crop, title, subtitle) in enumerate(SHOTS, 1):
    path = os.path.join(HERE, "out", f"{index}.png")
    compose(name, crop, title, subtitle).save(path)
    print(path)
