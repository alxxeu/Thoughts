#!/usr/bin/env python3
"""Demo board for App Store screenshots and the preview video.

Writes demo-board.json into the app's container. Launch a Debug build with
`-demoBoard YES` to use it (no iCloud, no Spotlight; see DemoMode). Quit the
demo first: it saves the board on quit.
"""
import json, os, uuid

T = 813_000_000  # seconds since 2001 — "now-ish" for the change timestamps
S = lambda tiles: tiles * 90 - 16  # card sizes snap to 90-pt tiles with a 16-pt gap


def card(text, w, h, tag=None, privacy="none", ai=False, at=None):
    return {
        "id": str(uuid.uuid5(uuid.NAMESPACE_URL, text)).upper(),
        "position": list(at or (0, 0)), "size": [S(w), S(h)],
        "text": text, "textFormat": 2,
        **({"tagColor": tag} if tag else {}),
        "privacyMode": privacy, "isAIGenerated": ai,
        "contentModifiedAt": T, "geometryModifiedAt": T, "metaModifiedAt": T, "raisedAt": T,
    }


def flow(cards, left=120, top=130, width=1560, gap=32):
    """Rows left to right; cards that already have a position keep it."""
    x, y, row = left, top, 0
    for c in cards:
        if c["position"] != [0, 0]:
            continue
        w, h = c["size"]
        if x + w > left + width:
            x, y, row = left, y + row + gap, 0
        c["position"] = [x, y]
        x, row = x + w + gap, max(row, h)
    return cards


def scatter(cards, seed):
    """A little chaos: cards spread over a 3×2 grid of the canvas, each nudged."""
    import random
    rnd = random.Random(seed)
    cells = [(c, r) for r in range(2) for c in range(3)]
    for c, (col, row) in zip(cards, cells):
        x = 120 + col * 540 + rnd.randint(-40, 80)
        y = 140 + row * 480 + rnd.randint(-30, 70)
        c["position"] = [x, y]
    return cards


# 1 — Ideas: spread over the four corners, then Tidy Cards gathers each tag.
ideas = [
    card("""# Thoughts 2.0
What if cards could **link** to each other — and the canvas drew the lines?""", 4, 3, "red", at=(160, 140)),
    card("""## Pricing
- Free canvas, forever
- **Pro**: sync and AI
- Student discount""", 3, 3, "red", at=(560, 160)),
    card("""## Onboarding
1. Drag to create a card
2. Type in Markdown
3. Press ⌥2 for the next Space""", 3, 3, "red", at=(300, 470)),
    card("""## Reading list
1. Make Something Wonderful
2. The Design of Everyday Things
3. ~~Deep Work~~""", 3, 3, "blue", at=(1250, 150)),
    card("""> The best way to have a good idea is to have lots of ideas.

— Linus Pauling""", 3, 2, "blue", at=(1400, 450)),
    card("""## Groceries
- [ ] Oat milk
- [x] Coffee beans
- [ ] Lemons
- [ ] Basil""", 3, 3, "green", at=(200, 760)),
    card("""### Command I keep forgetting
```
git commit --amend --no-edit
```""", 4, 2, at=(560, 800)),
    card("""## This weekend
- [x] Farmers market
- [ ] Call grandma
- [ ] Fix the bike""", 3, 3, at=(1300, 760)),
    card("""## Feature wishlist
- Backlinks
- Card templates
- **Calmer** canvas patterns""", 3, 3, at=(700, 420)),
    card("""## Podcast ideas
- Interview indie developers
- *Tools we love*""", 3, 3, at=(1050, 200)),
    card("""### Talk notes
**Design is how it works.** Keep the slides short.""", 4, 2, at=(1000, 420)),
    card("""## Gift ideas
- Fountain pen for Sam
- Film camera
- ~~Another mug~~""", 3, 3, at=(600, 700)),
    card("""### Movie night
*Perfect Days* — Wim Wenders""", 3, 2, at=(1000, 700)),
    card("""### Question
Why do we keep notes we **never** read again?""", 4, 2, at=(1100, 950)),
]

# 2 — Writing: one long piece for Focus Mode.
writing = flow([
    card("""# The quiet desk

Most note apps ask you to **decide where a thought goes** before you've finished thinking it. A folder, a tag, a notebook — the filing comes first.

A desk works the other way around. You put the paper down *where it makes sense right now*, and the shape of the work appears on its own.

## Three rules for a calm canvas
- One idea per card
- **Move** a card when it starts to matter
- Delete without guilt

The point isn't to keep everything. It's to see what you're thinking.

## Why it works
A folder is a decision you make **once** and live with forever. A card on a canvas is a decision you can make again tomorrow — closer to the middle when it matters, pushed to the edge when it doesn't.

Over a week, the canvas starts to look like your head: a busy corner for the project that's on fire, a quiet one for the books you mean to read, a few strays that might become something.

## What to try
- Start every morning with an **empty** card
- Keep only one Space per project
- Once a week, delete what you no longer need

You'll notice the moment a thought is ready, because you'll want to move it.""", 5, 6),
    card("""## Outline
1. The filing problem
2. Desks, not databases
3. Rules for a calm canvas""", 3, 3, "purple"),
    card("""### Title ideas
- The quiet desk
- Space to think
- ~~Notes without folders~~""", 3, 3),
])

launch = scatter([
    card("""## To do
- [ ] Record the preview video
- [ ] Press kit
- [ ] Reply to beta testers""", 3, 4, "red"),
    card("""## Doing
- [ ] App Store screenshots
- [x] Release notes""", 3, 4, "yellow"),
    card("""## Done
- [x] Markdown editor
- [x] Keyboard tags
- [x] iCloud sync""", 3, 4, "green"),
    card("""### Launch tweet
Thoughts 1.4 is out — **Markdown**, task lists and tags right from the keyboard.""", 4, 3),
    card("""## Ideas for 1.5
- Widgets
- iPhone companion
- *Shared* Spaces""", 4, 3, "purple"),
], 3)

journal = scatter([
    card("""# October 15
Slow morning. Coffee on the balcony, *finally* finished the book.

> Small steps every day.""", 4, 4),
    card("""## Grateful for
- Long walks
- Good friends
- Rain on the window""", 3, 3, "indigo"),
    card("""## Mood
Calm, a little sleepy. **Good** day.""", 3, 2),
    card("""## Sleep
- [x] In bed by 11
- [ ] No phone after 10""", 3, 3),
    card("""> What you do every day matters more than what you do once in a while.""", 4, 2, "indigo"),
], 4)

travel = scatter([
    card("""# Lisbon, May
- [x] Flights
- [ ] Hotel in Alfama
- [ ] Tram 28 at sunrise
- [ ] Pastéis de Belém""", 4, 4, "blue"),
    card("**Pack:** passport, charger, *the good camera*", 3, 2),
    card("""## Kyoto, someday
- Philosopher's Path
- Fushimi Inari at dawn""", 3, 3, "orange"),
    card("""## Budget
- Flights: **done**
- Hotels: ~half
- Food: *generous*""", 3, 3, "blue"),
    card("""### Phrases
Obrigado · Bom dia · *Uma bica, por favor*""", 4, 2),
], 5)

reading = scatter([
    card("""## Now reading
**The Design of Everyday Things**
Chapter 4 — knowing what to do""", 4, 3, "blue"),
    card("""> Good design is actually a lot harder to notice than poor design.

— Don Norman""", 4, 2),
    card("""## Up next
1. Make Something Wonderful
2. Four Thousand Weeks""", 3, 3),
    card("""## Highlights
- Affordances and signifiers
- **Feedback** is everything""", 3, 3, "blue"),
    card("""### Book club
Thursday, 7 pm — *bring snacks*""", 3, 2),
], 6)

recipes = scatter([
    card("""# Lemon pasta
- 200 g spaghetti
- 1 lemon, zest and juice
- Parmesan, black pepper
- **Lots** of butter""", 4, 4, "yellow"),
    card("""## Sunday soup
Carrot, ginger, coconut milk. Blend until *silky*.""", 3, 3),
    card("""## Shopping
- [ ] Lemons
- [ ] Parmesan
- [x] Spaghetti""", 3, 3, "green"),
    card("""### Weeknight rule
**Twenty minutes**, one pan, no stress.""", 4, 2),
    card("""## Try next
- Shakshuka
- Miso salmon
- *Proper* ramen""", 3, 3, "yellow"),
], 7)

finances = flow([
    card("""## October budget
- Rent
- Savings: 20%
- Travel fund""", 4, 3),
    card("Card PIN reminder lives here.", 3, 2, privacy="lock"),
])

fitness = scatter([
    card("""## This week
- [x] Run 5 km
- [x] Yoga
- [ ] Swim
- [ ] Long walk""", 3, 4, "green"),
    card("""### Personal best
5 km in **24:30**""", 3, 2),
    card("""## Long run plan
1. 6 km
2. 8 km
3. **10 km**""", 3, 3, "green"),
    card("""### Stretch
Ten minutes after every run. *No excuses.*""", 4, 2),
    card("""## Gear
- [x] New shoes
- [ ] Rain jacket""", 3, 3),
], 9)

spaces = [
    (1, "Ideas", ideas, False), (2, "Writing", writing, False), (3, "Launch", launch, False),
    (4, "Journal", journal, False), (5, "Travel", travel, False), (6, "Reading", reading, False),
    (7, "Recipes", recipes, False), (8, "Finances", finances, True), (9, "Fitness", fitness, False),
]
board = {
    "workspaces": [
        {"id": str(uuid.uuid5(uuid.NAMESPACE_URL, f"space{slot}")).upper(),
         "slot": slot, "name": name, "isProtected": protected, "modifiedAt": T}
        for slot, name, _, protected in spaces
    ],
    "cardsByWorkspace": {str(slot): cards for slot, _, cards, _ in spaces},
}

folder = os.path.expanduser("~/Library/Containers/com.alxeu.Thoughts/Data/Library/Application Support/Thoughts")
path = os.path.join(folder, "demo-board.json")
with open(path, "w") as f:
    json.dump(board, f, ensure_ascii=False)
print(path)
