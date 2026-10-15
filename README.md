# Thoughts

A free-form canvas for scattered ideas — no folders, no lists, just space to think.

Thoughts is a native macOS app built with SwiftUI. Instead of organizing
notes into folders or lists, you scatter cards freely across an
open canvas, exactly where they make sense to you.

## Features

- **Free-form canvas** — click and drag anywhere to create a card, move and resize it freely
- **Markdown** — headings, bold, italic, underline, strikethrough, highlight, code, links, lists, task lists, quotes, code blocks and dividers; the formatting characters show next to the cursor and hide everywhere else
- **Color tags** — tag cards by color to organize at a glance, right from the keyboard with ⌃1–7
- **Card privacy** — blur a card's contents (Spoiler) or hide it completely behind your passcode (Lock)
- **Space Lock** — protect an entire Space with a passcode and Touch ID
- **Multiple Spaces** — separate boards for different parts of your life, switch instantly with ⌥1–9, or with ⌃⌥1–9 from any app
- **Spotlight integration** — search your cards' text from anywhere on your Mac
- **Quick Capture** — a global shortcut (⌃⌥⌘N by default, customizable) opens a floating panel over any app; type, press Return, and the card lands in your active Space
- **Ask AI** — ask about a card, a selection or a whole Space: right-click any text and choose Ask AI, then replace, insert or copy the answer. Works with Apple Intelligence on-device, or ChatGPT and Claude with your own API key
- **Customization** — pick the card font, text size and color, and add a subtle background pattern to the canvas
- **iCloud sync** — optional, end-to-end encrypted sync of your Spaces and cards between your Macs
- **Backup & export** — full backups (optionally password-protected) and a readable Markdown export
- **Liquid Glass** on macOS 26, with a graceful fallback look on macOS 14–25

## Install

- **Mac App Store** — [Thoughts on the App Store](https://apps.apple.com/app/id6809164763)
- **Download** — [Thoughts.dmg](https://github.com/alxxeu/Thoughts/releases/latest/download/Thoughts.dmg), signed and notarized; it updates itself
- **Homebrew**

  ```bash
  brew install alxxeu/tap/thoughts
  ```

Install one or the other, not both.

## What's new in 1.4

Cards are now written in Markdown — with task lists, quotes and code
blocks — and AI answers arrive formatted. Tag cards with ⌃1–7, switch
Spaces from any app with ⌃⌥1–9, see what's new right after an update, and
check for updates in Settings → About. See the
[release notes](https://github.com/alxxeu/Thoughts/releases/tag/v1.4).

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
