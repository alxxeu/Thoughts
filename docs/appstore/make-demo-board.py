#!/usr/bin/env python3
"""Demo board for App Store screenshots and the preview video.

Writes demo-board.json into the app's container. Launch a Debug build with
`-demoBoard YES` to use it (no iCloud, no Spotlight; see DemoMode).
"""
import json, os, uuid

T = 813_000_000  # seconds since 2001 — "now-ish" for the change timestamps
S = lambda tiles: tiles * 90 - 16  # card sizes snap to 90-pt tiles with a 16-pt gap


def card(x, y, w, h, text, tag=None, privacy="none", ai=False, order=0):
    return {
        "id": str(uuid.uuid5(uuid.NAMESPACE_URL, text)).upper(),
        "position": [x, y], "size": [S(w), S(h)],
        "text": text, "textFormat": 2,
        **({"tagColor": tag} if tag else {}),
        "privacyMode": privacy, "isAIGenerated": ai,
        "contentModifiedAt": T, "geometryModifiedAt": T, "metaModifiedAt": T,
        "raisedAt": T + order,
    }


ideas = [
    card(120, 130, 4, 5, """# Weekend app idea
A **calm** place for *scattered* thoughts — no folders, ==just space==.

## Must have
- [x] Free-form canvas
- [x] Markdown cards
- [ ] Widgets
- [ ] iPhone companion

> Make it feel like a desk, not a database.""", tag="blue"),
    card(500, 130, 3, 3, """## Reading list
1. Make Something Wonderful
2. The Design of Everyday Things
3. ~~Deep Work~~""", tag="orange"),
    card(790, 130, 4, 3, """### Command I keep forgetting
```
git commit --amend --no-edit
```
Adds staged changes to the last commit."""),
    card(500, 400, 3, 2, """> The best way to have a good idea is to have lots of ideas.

— Linus Pauling""", tag="yellow"),
    card(790, 400, 2, 2, "Gift idea for Sam: the green fountain pen from the shop on Elm Street", tag="purple", privacy="spoiler"),
    card(970, 400, 2, 2, "Studio Wi-Fi: sunflower-42-meadow", privacy="lock"),
    card(1150, 130, 4, 4, """## Summary of this Space
- A weekend **app idea** with a clear must-have list
- A reading list, *one book finished*
- Next step: ==sketch the widget==""", ai=True),
    card(1150, 490, 3, 3, """## Groceries
- [ ] Oat milk
- [x] Coffee beans
- [ ] Lemons
- [ ] Basil""", tag="green"),
    card(120, 580, 4, 3, """## Call with Mia
- Loves the **canvas**
- Wants *dark mode* everywhere

--

Follow up on **Friday**""", tag="red"),
]

launch = [
    card(120, 130, 3, 4, """## To do
- [ ] Record the preview video
- [ ] Press kit
- [ ] Reply to beta testers""", tag="red"),
    card(410, 130, 3, 4, """## Doing
- [ ] App Store screenshots
- [x] Release notes""", tag="yellow"),
    card(700, 130, 3, 4, """## Done
- [x] Markdown editor
- [x] Keyboard tags
- [x] iCloud sync""", tag="green"),
    card(990, 130, 4, 3, """### Launch tweet
Thoughts 1.4 is out — **Markdown**, task lists and tags right from the keyboard."""),
    card(990, 400, 4, 2, """### Countdown
==3 days== to launch"""),
    card(120, 490, 4, 3, """## Ideas for 1.5
- Widgets
- iPhone companion
- *Shared* Spaces""", tag="purple"),
    card(500, 490, 4, 3, """## Press kit
- [x] Icon
- [ ] Screenshots
- [ ] Preview video""", tag="blue"),
]

journal = [
    card(120, 130, 4, 4, """# October 15
Slow morning. Coffee on the balcony, *finally* finished the book.

> Small steps every day."""),
    card(500, 130, 3, 3, """## Grateful for
- Long walks
- Good friends
- Rain on the window""", tag="indigo"),
]

travel = [
    card(120, 130, 4, 4, """# Lisbon, May
- [x] Flights
- [ ] Hotel in Alfama
- [ ] Tram 28 at sunrise
- [ ] Pastéis de Belém""", tag="blue"),
    card(500, 130, 3, 2, "**Pack:** passport, charger, *the good camera*"),
]

names = {1: "Ideas", 2: "Launch", 3: "Journal", 4: "Travel"}
board = {
    "workspaces": [
        {"id": str(uuid.uuid5(uuid.NAMESPACE_URL, f"space{slot}")).upper(),
         "slot": slot, "name": name, "isProtected": False, "modifiedAt": T}
        for slot, name in names.items()
    ],
    "cardsByWorkspace": {"1": ideas, "2": launch, "3": journal, "4": travel},
}

folder = os.path.expanduser("~/Library/Containers/com.alxeu.Thoughts/Data/Library/Application Support/Thoughts")
path = os.path.join(folder, "demo-board.json")
with open(path, "w") as f:
    json.dump(board, f, ensure_ascii=False)
print(path)
