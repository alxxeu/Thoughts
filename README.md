# Thoughts

A free-form canvas for scattered ideas — no folders, no lists, just space to think.

Thoughts is a native macOS app built with SwiftUI. Instead of organizing
notes into folders or lists, you scatter cards freely across an
open canvas, exactly where they make sense to you.


https://github.com/user-attachments/assets/3dead5b6-c2e1-49d7-8cc9-fe3771b8cc8c


## Features

- **Free-form canvas** — click and drag anywhere to create a card, move and resize it freely
- **Rich text** — bold/italic formatting, smart bulleted and numbered lists, dividers
- **Color tags** — tag cards by color to organize at a glance
- **Card privacy** — blur a card's contents (Spoiler) or hide it completely behind your passcode (Lock)
- **Space Lock** — protect an entire Space with a passcode and Touch ID
- **Multiple Spaces** — separate boards for different parts of your life, switch instantly with ⌥1–9
- **Spotlight integration** — search your cards' text from anywhere on your Mac
- **Quick Capture** — a global shortcut (⌃⌥⌘N by default, customizable) opens a floating panel over any app; type, press Return, and the card lands in your active Space
- **Ask AI** — ask about a card, a selection or a whole Space: right-click any text and choose Ask AI, then replace, insert or copy the answer. Works with Apple Intelligence on-device, or ChatGPT and Claude with your own API key
- **Customization** — pick the card font, text size and color, and add a subtle background pattern to the canvas
- **iCloud sync** — optional, end-to-end encrypted sync of your Spaces and cards between your Macs
- **Backup & export** — full backups (optionally password-protected) and a readable Markdown export
- **Liquid Glass** on macOS 26, with a graceful fallback look on macOS 14–25

## What's new in 1.3

iCloud sync, Quick Capture, backups and Markdown export, Ask AI from the
right-click menu, and appearance customization. See the
[release notes](https://github.com/alxxeu/Thoughts/releases/tag/v1.3).

## Plugins

Community plugins — fonts, colors, canvas patterns, themes, AI actions and
card templates — are being designed. See the draft spec in
[docs/plugins.md](docs/plugins.md); feedback is welcome.

## Privacy

All data is stored locally in the app's own sandboxed container on your
Mac. There is no account and no server: the developer never receives your
content. Optional iCloud sync stores your Spaces and cards in *your own*
iCloud account, end-to-end encrypted. Ask AI with Apple Intelligence runs
on your Mac; with ChatGPT or Claude, the text you ask about goes straight
from your Mac to that provider using your own API key. Details are in the
[privacy policy](docs/privacy.html). The source code in this repository
is published so anyone can verify that for themselves.

## Requirements

macOS 14.0 or later.

## License

The source code is published for transparency and auditing purposes
only. See [LICENSE](LICENSE) — this is **not** an open-source license;
all rights are reserved.
