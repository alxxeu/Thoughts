#!/usr/bin/env python3
"""App Preview for the Mac App Store: 1920×1080, 30 fps, under 30 s.

Cuts scenes out of a Recordly export of the demo board (Thoughts in full
screen, see make-demo-board.py), zooms in where the action is, crossfades
the scenes, puts a short Apple-style caption on each, ends on the app icon
and lays music from make-music.py under it.

    make-preview.py <recordly-export.mp4>
"""
import os, subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1]
OUT = os.path.join(HERE, "out", "preview.mp4")
TMP = tempfile.mkdtemp()
W, H, FPS, FADE = 1920, 1080, 30, 0.3
FULL = (0, 108, 3240, 1822)  # the whole Recordly frame as 16:9

# (caption, [(start, end, speed, crop)]) — times in the Recordly export.
SCENES = [
    ("Drag anywhere to create.", [(11.6, 14.4, 1.0, FULL)]),
    ("Write in Markdown.", [(28.85, 31.85, 1.0, (1200, 680, 1200, 675))]),
    ("Tag by color.", [(35.3, 37.0, 1.15, FULL), (41.2, 43.8, 1.15, FULL)]),
    ("Tidy up in one click.", [(50.2, 56.0, 1.4, FULL)]),
    ("Focus on one thought.", [(60.4, 63.4, 1.2, FULL), (70.0, 72.4, 1.0, (782, 522, 1700, 956))]),
    ("Ask AI about your notes.", [(74.2, 75.8, 1.15, FULL), (80.3, 82.3, 1.15, (917, 6, 1400, 788)),
                                  (83.6, 86.4, 1.15, (725, 394, 1800, 1012))]),
    ("Lock what’s private.", [(96.6, 101.0, 1.2, (806, 517, 1600, 900))]),
]
END_CARD = 3.0
FONT = "/System/Library/Fonts/SFNS.ttf"


def font(size, weight):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def caption_png(text, path):
    """Подпись внизу кадра на мягком затемнении — читается поверх любого фона."""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    shade = Image.new("L", (1, 340))
    for y in range(340):
        shade.putpixel((0, y), int(150 * (y / 339) ** 1.6))
    im.paste((0, 0, 0, 255), (0, H - 340, W, H), shade.resize((W, 340)))
    d = ImageDraw.Draw(im)
    d.text((W / 2, H - 120), text, font=font(64, "Semibold"), fill=(255, 255, 255, 255), anchor="mm")
    im.save(path)


def end_card(path):
    wall = Image.open(os.path.join(HERE, "raw", "wall-purple-dark.png")).convert("RGB")
    wall = wall.resize((W, round(W / 1.6)), Image.LANCZOS)
    top = (wall.height - H) // 2
    im = wall.crop((0, top, W, top + H)).filter(ImageFilter.GaussianBlur(6))
    icon = Image.open(os.path.join(HERE, "raw", "icon.png")).convert("RGBA").resize((220, 220), Image.LANCZOS)
    im.paste(icon, ((W - 220) // 2, 300), icon)
    d = ImageDraw.Draw(im)
    d.text((W / 2, 610), "Thoughts", font=font(110, "Bold"), fill="white", anchor="mm")
    d.text((W / 2, 715), "Space to think.", font=font(52, "Regular"), fill=(220, 214, 245), anchor="mm")
    im.save(path)


clips = []  # (start, end, speed, crop)
scene_of_clip = []
for n, (_, parts) in enumerate(SCENES):
    for part in parts:
        clips.append(part)
        scene_of_clip.append(n)

inputs, filters = [], []
durations = []
for i, (start, end, speed, (cx, cy, cw, ch)) in enumerate(clips):
    inputs += ["-ss", f"{start}", "-t", f"{end - start}", "-i", SRC]
    durations.append((end - start) / speed)
    filters.append(f"[{i}:v]setpts=(PTS-STARTPTS)/{speed},crop={cw}:{ch}:{cx}:{cy},"
                   f"scale={W}:{H}:flags=lanczos,fps={FPS},format=yuv420p,setsar=1[c{i}]")

card = os.path.join(TMP, "end.png")
end_card(card)
k = len(clips)
inputs += ["-loop", "1", "-t", f"{END_CARD}", "-i", card]
filters.append(f"[{k}:v]fps={FPS},format=yuv420p,setsar=1[c{k}]")
durations.append(END_CARD)

# Crossfade chain; remember when each clip starts in the final timeline.
starts, t, prev = [0.0], durations[0], "c0"
for i in range(1, len(durations)):
    offset = t - FADE
    starts.append(offset)
    filters.append(f"[{prev}][c{i}]xfade=transition=fade:duration={FADE}:offset={offset:.3f}[x{i}]")
    prev, t = f"x{i}", offset + durations[i]
total = t

# Captions over each scene, from its first clip to the end of its last.
caption_inputs = k + 1
for n, (text, _) in enumerate(SCENES):
    idx = [i for i, s in enumerate(scene_of_clip) if s == n]
    a = starts[idx[0]] + 0.15
    b = starts[idx[-1]] + durations[idx[-1]] - FADE
    png = os.path.join(TMP, f"cap{n}.png")
    caption_png(text, png)
    inputs += ["-loop", "1", "-t", f"{b - a:.3f}", "-i", png]
    j = caption_inputs + n
    filters.append(f"[{j}:v]format=rgba,fade=t=in:st=0:d=0.3:alpha=1,fade=t=out:st={b - a - 0.3:.3f}:d=0.3:alpha=1,"
                   f"setpts=PTS-STARTPTS+{a:.3f}/TB[cap{n}]")
    filters.append(f"[{prev}][cap{n}]overlay=0:0:eof_action=pass[o{n}]")
    prev = f"o{n}"

music = os.path.join(TMP, "music.wav")
subprocess.run([sys.executable, os.path.join(HERE, "make-music.py"), music, f"{total:.2f}"], check=True)
inputs += ["-i", music]
m = caption_inputs + len(SCENES)

os.makedirs(os.path.dirname(OUT), exist_ok=True)
subprocess.run(["ffmpeg", "-v", "error", "-y", *inputs, "-filter_complex", ";".join(filters),
                "-map", f"[{prev}]", "-map", f"{m}:a", "-t", f"{total:.3f}",
                "-af", "lowpass=f=11000,loudnorm=I=-16:TP=-1.5:LRA=11",
                "-c:v", "libx264", "-profile:v", "high", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p",
                "-r", str(FPS), "-c:a", "aac", "-b:a", "256k", "-ar", "48000", "-movflags", "+faststart", OUT],
               check=True)
print(OUT, f"{total:.1f}s")
