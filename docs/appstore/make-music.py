#!/usr/bin/env python3
"""Original background music for the App Preview — synthesized here, so there
are no licensing questions. Light, bright, Apple-ish: a soft pad, a plucked
arpeggio with an echo, bass and a gentle beat that enters after the intro.

    make-music.py <out.wav> [seconds]
"""
import math, random, struct, sys, wave

RATE = 48000
OUT = sys.argv[1]
LENGTH = float(sys.argv[2]) if len(sys.argv) > 2 else 30.0
BPM = 104
BEAT = 60 / BPM
BAR = 4 * BEAT
N = int(LENGTH * RATE)
left = [0.0] * N
right = [0.0] * N


def hz(midi):
    return 440 * 2 ** ((midi - 69) / 12)


def add(start, samples, pan=0.0, gain=1.0):
    """Mix a mono buffer in at `start` seconds; pan -1…1."""
    i0 = int(start * RATE)
    gl, gr = gain * math.cos((pan + 1) * math.pi / 4), gain * math.sin((pan + 1) * math.pi / 4)
    for k, v in enumerate(samples):
        i = i0 + k
        if i >= N:
            break
        left[i] += v * gl
        right[i] += v * gr


def pad_note(freq, dur, attack=0.5, release=0.8):
    out = []
    total = dur + release
    for k in range(int(total * RATE)):
        t = k / RATE
        env = min(1, t / attack) * (1 if t < dur else max(0, 1 - (t - dur) / release))
        v = (math.sin(2 * math.pi * freq * 0.998 * t) + math.sin(2 * math.pi * freq * 1.002 * t)
             + 0.25 * math.sin(4 * math.pi * freq * t))
        out.append(v * env * 0.33)
    return out


def pluck(freq, dur=0.9):
    """Karplus–Strong: a short noise burst through a damped delay line."""
    period = max(2, int(RATE / freq))
    buf = [random.uniform(-1, 1) for _ in range(period)]
    for _ in range(3):  # сглаженный шум — мягкая атака без щелчка
        buf = [(buf[i - 1] + buf[i] + buf[(i + 1) % period]) / 3 for i in range(period)]
    out = []
    for k in range(int(dur * RATE)):
        v = buf[k % period]
        nxt = buf[(k + 1) % period]
        buf[k % period] = 0.497 * (v + nxt)
        out.append(v * (1 - k / (dur * RATE)) ** 1.5)
    return out


def bass(freq, dur):
    return [math.sin(2 * math.pi * freq * k / RATE) * math.exp(-3.2 * k / RATE / dur)
            for k in range(int(dur * RATE))]


def kick():
    out, phase = [], 0.0
    for k in range(int(0.3 * RATE)):
        t = k / RATE
        phase += 2 * math.pi * (45 + 75 * math.exp(-t * 28)) / RATE
        out.append(math.sin(phase) * math.exp(-t * 11))
    return out


def hat():
    out, prev = [], 0.0
    for k in range(int(0.04 * RATE)):
        n = random.uniform(-1, 1)
        out.append((n - prev) * math.exp(-k / RATE * 90))  # first difference ≈ high-pass
        prev = n
    return out


random.seed(14)
# F major: Fmaj7 – Am7 – Dm7 – B♭maj7, one chord per bar.
chords = [(53, [65, 69, 72, 76]), (57, [64, 67, 69, 72]), (50, [62, 65, 69, 72]), (46, [62, 65, 69, 70])]
bars = int(LENGTH / BAR)
last_bar = bars - 1  # the final bar rings out on F
kick_buf, hat_buf = kick(), hat()

for b in range(bars):
    root, notes = chords[b % 4] if b < last_bar else (53, [65, 69, 72, 76, 79])
    start = b * BAR
    hold = BAR if b < last_bar else LENGTH - start
    for n in notes:
        add(start, pad_note(hz(n - 12), hold), gain=0.05 if b < last_bar else 0.11)
    if b == last_bar:  # финальный аккорд перебором — под карточку с иконкой
        for e, n in enumerate(notes):
            add(start + e * 0.06, pluck(hz(n), dur=hold), pan=-0.3 + 0.15 * e, gain=0.14)
    if b >= 1:
        add(start, bass(hz(root - 12), BAR * 0.9), gain=0.16)
    if b < last_bar:
        pattern = [0, 2, 3, 1, 2, 3, 1, 2]  # indexes into the chord, eighth notes
        for e, idx in enumerate(pattern):
            note = notes[idx % len(notes)] + 12
            t = start + e * BEAT / 2
            p = pluck(hz(note))
            add(t, p, pan=-0.35 if e % 2 else 0.35, gain=0.16)
            add(t + 3 * BEAT / 4, p, pan=0.35 if e % 2 else -0.35, gain=0.05)  # echo
    if 2 <= b < last_bar:
        for beat in range(4):
            if beat in (0, 2):
                add(start + beat * BEAT, kick_buf, gain=0.32)
            add(start + beat * BEAT + BEAT / 2, hat_buf, pan=0.2, gain=0.05)
    else:
        if b == last_bar:
            add(start, kick_buf, gain=0.3)

# Fade out the last two seconds; normalize.
fade = int(2.0 * RATE)
for i in range(N - fade, N):
    g = (N - i) / fade
    left[i] *= g
    right[i] *= g
peak = max(max(map(abs, left)), max(map(abs, right))) or 1
scale = 0.85 / peak
with wave.open(OUT, "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes(b"".join(struct.pack("<hh", int(l * scale * 32767), int(r * scale * 32767))
                           for l, r in zip(left, right)))
print(OUT, f"{LENGTH:.1f}s")
