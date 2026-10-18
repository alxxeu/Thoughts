#!/usr/bin/env python3
"""Тестовая доска для Debug-сборок: python3 scripts/make-test-board.py <out.json>.
Детерминированная (uuid5 от имён) — повторный запуск даёт те же id."""
import json, sys, time, uuid

NOW = time.time() - 978307200  # секунды от 2001-01-01, как Date в JSON приложения
NS = uuid.UUID("6f0b1c52-7a1e-4d2b-9a43-0c5e8f1d2a77")
def uid(*parts): return str(uuid.uuid5(NS, "/".join(map(str, parts)))).upper()

TAGS = ["red", "orange", "yellow", "green", "blue", "indigo", "purple"]
cards = {}

def add(slot, text, pos, size=(280, 200), tag=None, privacy="none", ai=False):
    n = len(cards.setdefault(slot, []))
    t = NOW - 3600 * (50 - n)
    c = {"id": uid("card", slot, n), "position": list(pos), "size": list(size), "text": text,
         "textFormat": 2, "isAIGenerated": ai, "privacyMode": privacy,
         "contentModifiedAt": t, "geometryModifiedAt": t, "metaModifiedAt": t, "raisedAt": t + n}
    if tag: c["tagColor"] = tag
    cards[slot].append(c)

def grid(slot, items, cols=4, w=280, h=200, gap=24, x0=40, y0=100):
    for i, (text, tag, *rest) in enumerate(items):
        add(slot, text, (x0 + (i % cols) * (w + gap), y0 + (i // cols) * (h + gap)), (w, h), tag, *(rest or []))

# 1 Full — много карточек разной длины и цвета
full = ["# Groceries\n- [x] Oat milk\n- [ ] Coffee beans\n- [ ] Basil", "Call mom on Sunday", "# Ideas\n- Dark mode for widgets\n- Share a Space by link",
        "**Reminder:** dentist at 15:30", "Book flights to Lisbon", "# Reading\n1. Piranesi\n2. The Overstory\n3. Klara and the Sun",
        "Buy a birthday gift for Anna", "> The best way out is always through.\n\n— Robert Frost", "# Budget\n- Rent\n- Food\n- Transport",
        "Water the plants 🌱", "Pick up the parcel from the post office", "# Weekend\n- [ ] Hike\n- [ ] Laundry", "Renew passport", "Try the new ramen place"]
grid(1, [(t, TAGS[i % 7] if i % 3 else None) for i, t in enumerate(full)], cols=5, w=240, h=170)

# 2 Half — полупустой
grid(2, [("# Today\n- [ ] Write report\n- [ ] Reply to emails", "blue"), ("Short note", None), ("# Later\nSomeday maybe", "green")], cols=3)

# 3 Empty — без карточек
cards[3] = []

# 4 Locked — защищённый Space
grid(4, [("# Passwords hint\nNothing real here — test data.", "red"), ("Private diary entry:\nToday was a quiet day.", None), ("# Medical\n- [ ] Book check-up", "purple"), ("Secret plan 🤫", "orange")], cols=2, w=300, h=200)

# 5 Privacy — Spoiler / Lock / обычные вперемешку
grid(5, [("# Normal\nVisible card", "green", "none"), ("# Spoiler\nHidden until revealed", "blue", "spoiler"), ("# Lock\nNeeds Touch ID", "red", "lock"),
         ("Spoiler with a long body. " * 12, None, "spoiler"), ("Lock with a long body. " * 12, "purple", "lock"), ("Normal with tag", "yellow", "none"),
         ("# Spoiler list\n- [ ] one\n- [x] two\n- [ ] three", "orange", "spoiler"), ("Lock tiny", None, "lock"), ("Normal tiny", None, "none")], cols=3, w=300, h=220)
add(5, "Spoiler wide", (40, 780), (620, 120), "indigo", "spoiler")
add(5, "Lock tall", (700, 780), (240, 300), "red", "lock")

# 6 Markdown — все конструкции
md = [
 "# Heading 1\n## Heading 2\n### Heading 3\nBody text under headings.",
 "**Bold**, *italic*, ***bold italic***, ~~strike~~ and `inline code`.",
 "- Bullet one\n- Bullet two\n  - Nested a\n  - Nested b\n- Bullet three",
 "1. First\n2. Second\n3. Third\n10. Tenth",
 "- [ ] Open task\n- [x] Done task\n- [ ] Task with **bold** and a [link](https://example.com)",
 "> A quote on one line\n\n> Multi-line quote\n> continues here",
 "```\nlet x = 42\nprint(x)\n```\nText after the code block.",
 "```swift\nstruct Card {\n    var text: String\n}\n```",
 "Link: [Apple](https://apple.com) and bare https://example.com/path?q=1",
 "Line one\n\nLine after blank\n\n\n\nLine after three blanks",
 "---\nDivider above and below\n---",
 "Эмодзи и кириллица 🙂🚀\nСтрока с ёжиком и «кавычками» — тире.",
 "# Heading only",
 "",
 "x",
 "A very long single line without spaces: " + "abcdefghij" * 20,
 "# Mixed\n> **Quote with bold** and `code`\n- [ ] Task in a list\n1. Numbered\n\nParagraph with trailing spaces   \nand a hard break.",
 "\\*Escaped\\* stars and \\# hash, 2 * 3 * 4 = 24, snake_case_name, a_b_c",
]
grid(6, [(t, TAGS[i % 7] if i % 4 == 0 else None) for i, t in enumerate(md)], cols=5, w=260, h=190)

# 7 Edge — наложение, крайние размеры, за пределами экрана
add(7, "Overlap A", (100, 120), (300, 200), "red"); add(7, "Overlap B", (220, 200), (300, 200), "blue"); add(7, "Overlap C", (340, 280), (300, 200), "green")
add(7, "Tiny", (700, 120), (80, 60)); add(7, "# Huge\n" + "Lorem ipsum dolor sit amet. " * 40, (760, 200), (520, 560), "purple")
add(7, "Far right", (2400, 150), (260, 180), "orange"); add(7, "Far below", (150, 2200), (260, 180), "yellow"); add(7, "Negative", (-120, -80), (260, 180), "indigo")
add(7, "Wide strip", (40, 640), (1200, 70)); add(7, "Tall strip", (1350, 100), (70, 700))

# 8 Long — много карточек для прокрутки ленты
for i in range(36):
    body = f"# Note {i + 1}\n" + ("Line of text for scrolling. " * (1 + (i * 7) % 9))
    add(8, body, (40 + (i % 6) * 250, 100 + (i // 6) * 190), (230, 170), TAGS[i % 7] if i % 2 else None)

# 9 AI & Tags — все цвета и AI-карточки
for i, tg in enumerate(TAGS):
    add(9, f"# {tg.capitalize()} tag\nCard with the {tg} tag.", (40 + (i % 4) * 300, 100 + (i // 4) * 220), (280, 200), tg)
add(9, "# AI summary\n- Point one\n- Point two\n- Point three", (40, 560), (280, 200), "blue", ai=True)
add(9, "Generated by Ask AI.\n\n> Quoted source", (340, 560), (280, 200), None, ai=True)
add(9, "# AI + Lock\nGenerated and locked.", (640, 560), (280, 200), "purple", "lock", ai=True)

names = {1: "Full", 2: "Half", 3: "Empty", 4: "Locked", 5: "Privacy", 6: "Markdown", 7: "Edge", 8: "Long", 9: "AI & Tags"}
board = {
    "workspaces": [{"id": uid("ws", s), "slot": s, "name": n, "isProtected": s == 4, "modifiedAt": NOW} for s, n in names.items()],
    "cardsByWorkspace": {str(s): v for s, v in cards.items()},
}
json.dump(board, open(sys.argv[1], "w"), ensure_ascii=False)
print(f"{len(board['workspaces'])} spaces, {sum(len(v) for v in cards.values())} cards -> {sys.argv[1]}")
