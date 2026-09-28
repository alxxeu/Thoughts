# Thoughts Plugins — Design

Status: **draft / design only.** Nothing in this document is implemented yet
except the built-in customization registry that the plugin system will extend
(see [Runtime architecture](#5-runtime-architecture)). This document is the
contract we intend to ship, published early so the community can comment on it
before any code lands.

---

## 1. Goals and constraints

**Goals**

- Let anyone extend how Thoughts looks and behaves (fonts, colors, canvas
  patterns, themes, AI actions, card templates) without access to the app's
  source code.
- Make plugins easy to author: a folder with a JSON manifest and a few asset
  files, and no Xcode or build step.
- Keep plugins safe to install. A plugin must not be able to read your
  cards, reach the network, or run code on your Mac.

**Constraints**

| Constraint | Consequence for plugins |
|---|---|
| Thoughts is a **sandboxed Mac App Store** app. | Plugins live inside the app's container. They can't reach arbitrary files. |
| App Store Review Guideline **2.5.2** forbids downloading or executing code that changes app functionality. | Plugins that anyone can download (Tier 1) are **data only**. Scripted plugins (Tier 2) stay local and user-authored. |
| Privacy promise: *no network requests with your card content*. | Plugins get no network access. Plugin AI prompts go only to the AI provider the user already configured. |
| The app is **closed source**. | The plugin API is the only extension point, so it has to be stable and versioned (`apiVersion`, see §8). |

---

## 2. Plugin tiers

### Tier 1: declarative packs (planned first)

A pack is data only. It *contributes* items to one or more **extension points**:

| Extension point | What it adds | Where it shows up |
|---|---|---|
| `fonts` | `.ttf` / `.otf` files, registered for this process only | Settings → Appearance → Font |
| `textColors` | Named card text colors | Settings → Appearance → Text Color |
| `patterns` | Canvas background patterns: procedural parameters or a tiled image | Settings → Appearance → Background |
| `themes` | A named bundle of font + text color + pattern (+ intensity) | Settings → Appearance → Theme presets |
| `aiActions` | Prompt templates | Card context menu → AI, and the Space "Ask AI" panel |
| `cardTemplates` | Starting text, size and tag for a new card | Quick Capture and a future "New from Template" menu |

### Tier 2: scripted plugins (future, exploratory)

These would be small JavaScript files run in **JavaScriptCore**, with
permission-based access to a narrow API: react to card edits, add commands,
and transform text.

Rules:

- **Local only.** A user writes or pastes the script themselves. The catalog
  (§7) never distributes scripts. That keeps us inside guideline 2.5.2, which
  allows user-created scripts but not remotely delivered features.
- Each capability (`cards.read`, `cards.write`, `commands`) is declared in the
  manifest and approved by the user on install.
- No network, no filesystem, and no timers beyond a short execution budget.

Tier 2 needs its own design review before any work starts (see §9).

---

## 3. Package format

A plugin is a folder with the `.thoughtsplugin` extension. Thoughts declares
it as a package UTType that conforms to `com.apple.package`, so Finder shows
it as a single file.

```
Midnight.thoughtsplugin/
├── manifest.json
├── fonts/
│   └── Inter-Variable.ttf
└── patterns/
    └── stars.png
```

### `manifest.json`

```json
{
  "id": "com.example.midnight",
  "name": "Midnight",
  "version": "1.0.0",
  "apiVersion": 1,
  "minAppVersion": "1.3",
  "author": "Jane Doe",
  "description": "A calm dark theme with a starry canvas.",
  "homepage": "https://example.com/midnight",
  "contributes": {
    "fonts": [
      { "id": "inter", "name": "Inter", "file": "fonts/Inter-Variable.ttf", "family": "Inter" }
    ],
    "textColors": [
      { "id": "moonlight", "name": "Moonlight", "hex": "#C8D3FF" }
    ],
    "patterns": [
      { "id": "fine-dots", "name": "Fine Dots", "kind": "dots", "spacing": 16, "dotSize": 1.5 },
      { "id": "stars", "name": "Stars", "kind": "image", "file": "patterns/stars.png", "tileSize": 128 }
    ],
    "themes": [
      {
        "id": "midnight",
        "name": "Midnight",
        "font": "com.example.midnight/inter",
        "textColor": "com.example.midnight/moonlight",
        "pattern": "com.example.midnight/stars",
        "patternIntensity": 0.15
      }
    ],
    "aiActions": [
      {
        "id": "translate-en",
        "title": "Translate to English",
        "symbol": "globe",
        "prompt": "Translate the note to English. Reply with only the translation.",
        "result": "replace"
      }
    ],
    "cardTemplates": [
      {
        "id": "standup",
        "name": "Daily Standup",
        "text": "Yesterday:\n• \n\nToday:\n• \n\nBlockers:\n• ",
        "size": { "columns": 4, "rows": 4 },
        "tag": "blue"
      }
    ]
  }
}
```

### Field reference

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Reverse-DNS, `[a-z0-9.-]`, 3–100 characters. It is globally unique and can never be reused for a different plugin. |
| `name` | yes | 1–40 characters, shown in Settings → Plugins. |
| `version` | yes | SemVer. An update is accepted only if the version is higher. |
| `apiVersion` | yes | Integer. Thoughts refuses packs with an `apiVersion` it doesn't know (§8). |
| `minAppVersion` | no | The pack stays disabled (with a notice) on older app versions. |
| `author`, `description`, `homepage` | no | Display only. `homepage` must be `https`. |
| `contributes.*[].id` | yes | Unique within the pack, `[a-z0-9-]`. Referenced from elsewhere as `<pluginID>/<itemID>`. |

Per extension point:

- **patterns.kind**: `dots`, `grid`, `lines`, `crosses` or `diagonal`. These
  take the procedural parameters `spacing`, `lineWidth` and `dotSize`, the
  same fields as the built-in `CanvasPattern`. `image` takes `file` (PNG or
  PDF) and `tileSize`. Patterns are always drawn in the adaptive `.primary`
  color at the user's chosen intensity, so a pattern image works as a mask:
  only its alpha channel is used.
- **textColors.hex**: `#RRGGBB`. Cards always have a dark surface, so
  Settings shows a low-contrast hint for colors below WCAG AA (4.5:1)
  against it. Dark colors are allowed; the built-in set has some too.
- **aiActions.result**: `replace` rewrites the card, `append` adds below it, and
  `newCard` puts the answer on a new card. The `prompt` becomes the system
  prompt, and the app appends its standard output rules (no preamble, plain
  text).
- **cardTemplates.size**: measured in grid tiles (`columns × rows`), and snapped
  the same way as hand-drawn cards (`k × 60 − 16` pt).

---

## 4. Installation and lifecycle

**Ways to install**

1. Settings → Plugins → **Install Plugin…** opens an Open panel. The app
   already has the `user-selected.read-only` entitlement.
2. Double-click a `.thoughtsplugin` in Finder. Thoughts registers the document
   type.
3. Drag a `.thoughtsplugin` onto the Thoughts icon or the Settings → Plugins
   list.

On install, Thoughts **copies** the package to

```
~/Library/Containers/com.alxeu.Thoughts/Data/Library/Application Support/Thoughts/Plugins/<id>/
```

It never runs a pack from its original location, so the pack stays usable
after the user deletes the download.

**Validation** runs before the copy. Any failure rejects the whole pack with a
readable error:

- `manifest.json` must parse and match the schema, and `apiVersion` must be
  supported.
- Only whitelisted file types are allowed (`.json`, `.ttf`, `.otf`, `.png`,
  `.pdf`), with no symlinks or executables.
- Every `file` path must resolve **inside** the package after standardizing
  it, so `..` and absolute paths are rejected.
- Size limits: 20 MB per pack, 10 MB per font, 2 MB per image, 200 items per
  extension point.
- Duplicate `id`: this is an update if `version` is higher, otherwise the pack
  is rejected.

**Settings → Plugins** lists installed packs with a name, author, version and
a count of contributed items. Each pack has an **Enable** toggle, **Remove**,
and **Reveal in Finder**.

**Removal or disable**: any setting that pointed at the pack's items (for
example `appearance.cardFont = "com.example.midnight/inter"`) falls back to
the built-in default. The stored value is kept, so re-enabling the pack
restores the user's choice.

---

## 5. Runtime architecture

```
                ┌──────────────────────────┐
 built-ins ───▶ │   ContributionRegistry   │ ◀─── PluginManager
 (Customization │  fonts / textColors /    │      (scans Plugins/,
  .swift)       │  patterns / themes /     │       validates, registers
                │  aiActions / templates   │       fonts via CoreText)
                └────────────┬─────────────┘
                             │ resolve(id) → item | default
          ┌──────────────────┼──────────────────┐
   AppearanceSettings    AI menus         Quick Capture /
   (card typography,     (AITextAction    New from Template
    canvas pattern)       + plugin ones)
```

- **Built-ins already use this shape.** `Thoughts/Customization.swift` defines
  `CardFontOption`, `TextColorOption` and `CanvasPattern` with string ids
  (`builtin.serif`, `builtin.mint`, `builtin.dots`) and `resolve(_:)` functions
  that fall back to the default for unknown ids. `AppearanceSettings` stores
  ids, not values. Plugin support replaces the static `builtIn` arrays with
  registry lookups. Storage and UI stay the same.
- **PluginManager** runs on launch and whenever the Plugins folder changes. It
  reads the manifests, validates them, and registers fonts with
  `CTFontManagerRegisterFontsForURL(url, .process, …)`. That is process-scoped:
  plugin fonts never show up in other apps and don't need a user prompt.
- **Namespacing.** Built-in ids start with `builtin.`. Plugin items are
  `<pluginID>/<itemID>`. Because the separators differ, a plugin can't
  override a built-in.
- **AI actions** become a second section of the card's AI submenu. They go
  through the existing `AITextServiceFactory`, so they respect the provider the
  user selected (Apple Intelligence runs on device, BYOK uses the user's own
  key).

---

## 6. Security and privacy model

- **Tier 1 packs are inert data.** Thoughts parses JSON and loads fonts and
  images, and nothing in a pack is ever executed.
- **No card access.** Packs contribute *presentation* and *prompts*. An AI
  action's prompt is combined with card text only when the user explicitly
  invokes that action, the same way as the built-in AI actions.
- **No network.** Packs have no URL fields that the app fetches. `homepage` is
  just a link the user can click.
- **Font parsing** is the main attack surface. CoreText is the same parser
  every app uses for user-installed fonts, and the size limits reduce the
  risk further.
- **Tier 2** (if it ships) runs in a fresh `JSContext` per plugin with no
  bridged objects beyond the declared capabilities, and a watchdog kills slow
  scripts.

---

## 7. Distribution

**Community catalog.** A public GitHub repository, `thoughts-plugins`:

```
thoughts-plugins/
├── index.json          # generated: id, name, version, author, sha256, download URL
└── plugins/
    └── com.example.midnight/
        └── Midnight.thoughtsplugin/…
```

- Plugins are submitted by pull request. CI validates each manifest with the
  same rules the app uses (§4) and computes `sha256`. A maintainer reviews the
  visual content.
- Until the in-app browser exists, users download a pack from GitHub and
  install it by double-clicking.

**Later: in-app Browse tab.** It fetches `index.json`, shows previews, and
downloads **Tier 1 packs only**. It checks the downloaded package's hash
against `index.json` before running the normal install validation. The only
new network requests are to the catalog, and they never include user content.

---

## 8. Versioning

- `apiVersion` is an integer that increases only on **breaking** changes to the
  manifest schema or item semantics. New optional fields and new extension
  points don't bump it.
- Thoughts supports the current `apiVersion` and the one before it. Packs with
  an unsupported `apiVersion` stay installed but disabled, with an "Update
  required" notice.
- A deprecated field keeps working for at least one `apiVersion` cycle and
  produces a warning in Settings → Plugins.

---

## 9. Roadmap and open questions

**Phase 0 (done):** built-in customization on a string-id registry (font, text
color, canvas pattern) and Quick Capture.

**Phase 1:** `PluginManager`, the Settings → Plugins tab, local install, the
`fonts`, `textColors`, `patterns` and `themes` extension points, and one
example pack.

**Phase 2:** the `aiActions` and `cardTemplates` extension points, and the
`thoughts-plugins` catalog repo with CI validation.

**Phase 3:** the in-app Browse tab.

**Phase 4 (exploratory):** Tier 2 scripted plugins, only after a separate
design and App Review risk assessment.

**Open questions**

1. Should themes be able to set **per-Space** appearance, or stay global? Per
   Space is attractive (work Space serif, personal Space rounded) but needs
   per-workspace settings storage.
2. Should `cardTemplates` be able to preset **privacy mode** (spoiler/lock)?
   It's probably useful for a "Passwords" template, but it's a
   security-adjacent setting coming from third-party data.
3. Should image patterns support **full color**, or stay masks tinted with
   `.primary`? Masks guarantee contrast in light and dark, while full color
   gives authors more freedom.
4. Should the catalog signing go beyond `sha256` in `index.json`, for example
   minisign signatures, to protect against a compromised GitHub account?
