# Thoughts для iPhone — дизайн-система

Статус: **согласовано** 2026-10-15. Экраны, где используются компоненты, —
[SCREENS.md](SCREENS.md) (S1–S12). Макеты — страницы iOS — Screens / Components в Figma. Значения взяты из кода Mac: iPhone
должен узнаваться как тот же продукт.

Основа — системный iOS 26 (Liquid Glass, SF Pro, SF Symbols, системные
списки и алерты). Своё — только то, что есть у Thoughts и нет у системы:
карточка, звёздный блюр, точка тега, поле ввода ленты, панель Markdown.

---

## 1. Токены

### Цвет

| Токен | Значение | Источник на Mac |
|---|---|---|
| `tag/red … tag/purple` | 7 системных цветов SwiftUI: red, orange, yellow, green, blue, indigo, purple | `CardTagColor.color` (`Shared/Card.swift`) |
| `card/text` | белый 88 % | `CardTypography.defaultTextColor` |
| `card/surface` | Liquid Glass `.clear`, тон чёрный 5 % (тёмная) / 20 % (светлая), под ним `ultraThinMaterial` 60 % | `CardSurfaceBackground` |
| `card/surface-fallback` | `ultraThinMaterial` + чёрный 40 % (светлая 50 %) | там же, без glass |
| `card/privacy-tint` | чёрный 20 % поверх стекла | `StarFieldOverlayView` |
| `lock/fullscreen-tint` | материал + чёрный тон, без glass (иначе блик по краю) | `CardSurfaceBackground(usesGlassEffect: false)` |
| `markdown/highlight` | systemYellow 35 % | `MarkdownRenderer` |
| `markdown/code` | моноширинный, 92 % размера строки, свой цвет | `MarkdownRenderer.codeColor` |
| `accent` | фиолетовый — акцент всего приложения: отправка, выделения, активные элементы (Р18) | новое на iPhone |
| `markdown/link` | accent color, подчёркнутая | `ShortcutsSettingsView` (превью) |
| фон экрана | системный `systemBackground`; в тёмной теме — открытый вопрос: ровный фон или мягкий градиент, на котором видно стекло карточек (решаем в Figma) | на Mac под карточками — обои/холст |

Текст на карточке на Mac всегда светлый (поверхность тёмная в обеих темах).
На iPhone — то же правило, пока Figma не покажет иное.

### Типографика

| Токен | Значение | Источник |
|---|---|---|
| `card/body` | SF Pro 15 pt (M); S 13 · L 18 · XL 22 | `CardTypography.defaultFontSize`, `CardTextSize` |
| `card/heading` | жирный, крупнее body (уровни 1–3) | `MarkdownRenderer` |
| `card/code` | SF Mono, 92 % body | `MarkdownRenderer` |
| UI | системные стили iOS (Large Title, Headline, Body, Footnote) + Dynamic Type | — |

Шрифты карточек Mac (System / Rounded / Serif / Mono) — «позже» (SPEC §4).

### Форма и отступы

| Токен | Значение | Источник |
|---|---|---|
| `radius/card` | 16 | `CardSurfaceBackground`, `CardView` |
| `radius/control` | системный (капсула у кнопок iOS 26) | — |
| `space/card-padding` | 12–16 внутри карточки (на Mac 7–9 + поля текста) — подобрать в Figma | `CardView` |
| `space/feed-gap` | промежуток между карточками ленты — в Figma | — |
| `space/screen-margin` | 16 | системный |
| `preview/lines` | минимум ~2, максимум ~8–10, низ гаснет на ~15 pt | продуктовые решения; `CardView` (маска) |

## 2. Компоненты

| Компонент | Где | Варианты / состояния |
|---|---|---|
| **Spaces Bar** | S1 под полем ввода, внизу экрана | имена Spaces в ряд, текущий — в капсуле; прокрутка вбок; защищённый (замок) (Р3, Р12) |
| **Space Dots** | S1 под полем ввода | свёрнутая полоса при прокрутке к старым: точка на Space, текущая — выделена (Р12) |
| **More Button** | S1 справа сверху | плавающая стеклянная «…» → системное меню (пока Settings) (Р12) |
| **Card (лента)** | S1 | длина: 1 строка / 2–10 / длинная с мягким затуханием ~15 pt (Р20); тег — точка справа сверху: нет / 7 цветов (Р19); приватность: none / Spoiler (закрыт, открыт) / Lock (закрыт, открыт); задача в превью отмечается тапом (Р4); свайп удаления |
| **Tag Dot** | Card (справа сверху), шапка S2 (слева) | 7 цветов; без тега в S2 — полупрозрачная белая точка-кнопка (Р19) |
| **Star Field** | Card Spoiler/Lock | Spoiler — звёзды; Lock — звёзды + `lock.fill` 22 pt |
| **Composer** (поле ввода) | S1 низ | пусто с плейсхолдером / 1–3 строки с кнопкой отправки (акцент) / 4+ строк с иконкой-расширителем, до 200 pt (Р17) |
| **Sync Notice** | S1 | Offline / Sign in to iCloud / Couldn’t sync |
| **Empty Space Hint** | S1 | пусто / Syncing… |
| **Editor Sheet** | S2 | стеклянная шторка «Халф» / «Фулл», язычок; шапка: Tag Dot слева, «…» справа; кнопка «Aa» при правке (Р13) |
| **Markdown Toolbar** | S2 над клавиатурой, по кнопке «Aa» | кнопки Bold, Italic, Strikethrough, Highlight, Heading, Bullet, Task, Quote, Code, Link; активна / нет |
| **Tag Popover** | S2, от точки тега | ряд: без тега + 7 цветов в порядке `CardTagColor` (Р21), выбранный отмечен; под ним Spoiler и Lock (Р13) |
| **Passcode Pad** | S3, S4, S8 | точки 0–4, ошибка (встряхивание), кнопка Face ID |
| **Lock Screen** | S3 | Face ID / только код / ждём код из iCloud |
| **Settings Rows** | S7 | системные: тумблер, пикер, кнопка, статус; строка Space с тумблером видимости (Р3) |
| **Onboarding Page** | S9 | иллюстрация + заголовок + текст; последний — кнопки синка |

Системные, без своего дизайна: алерты S5, S10; меню S6, меню «…» в S1 и S2; action sheet S11;
контекстное меню карточки S12 (Copy, Share, Delete) и Share-лист; Face ID.

## 3. Переиспользование с Mac

| Элемент | Файл | Как берём |
|---|---|---|
| Цвета тегов | `Shared/Card.swift` (`CardTagColor`) | уже общий |
| Разбор Markdown | `Shared/Markdown/MarkdownStyler.swift`, `MarkdownFormatting.swift` | уже общий; форматирование из панели — те же правила |
| Тексты статусов синка | `Shared/Sync/CloudSyncSettings.swift` (`CloudSyncStatus.text`) | уже общий; поправить «Mac»/«System Settings» под iPhone |
| Звёздный блюр | `Thoughts/StarFieldView.swift` (`StarFieldOverlayView`, `StarFieldCanvas`) | чистый SwiftUI → перенести в Shared |
| Стекло карточки | `Thoughts/CardSurfaceStyle.swift` (`CardSurfaceBackground`) | чистый SwiftUI, проверка `#available(macOS 26)` → добавить iOS 26 и перенести |
| Кнопки тега и приватности | `Thoughts/TagPopoverView.swift` (`TagCircleButton`, `PrivacyActionButton`) | SwiftUI — кандидат для Tag Popover в S2 |
| Экран блокировки Space | `Thoughts/SpaceLockOverlayView.swift` | SwiftUI; логика ввода кода — проверить при сборке (на Mac — физические клавиши) |
| Тексты онбординга, алертов | `OnboardingView.swift`, `InitialSyncAlert.swift`, `BoardStore` | как основа формулировок |
| Иконки | SF Symbols (`lock.fill`, `sparkle`, …) | те же символы |

**Не переносится:** отрисовка Markdown на AppKit (`MarkdownRenderer`,
`MarkdownBlockDecorator`, `MarkdownBulletGlyphs` — NSTextView/NSLayoutManager;
на iOS — своя на TextKit 2 / UITextView), холст и геометрия
(`ContentView`, `CardView`), Desktop Overlay, глобальные хоткеи, поповеры
AppKit.

## 4. Для Figma

- Переменные: коллекция **Color** (режимы Light / Dark): `tag/*`, `card/*`,
  `markdown/*`; коллекция **Size**: `radius/*`, `space/*`, `type/*`.
- Компоненты — по таблице §2, с вариантами в свойствах.
- Экраны — iPhone 17 Pro, портрет; все состояния из SCREENS.md.
- Системные элементы iOS 26 (навбар, списки, клавиатура, алерты) — из
  Apple iOS 26 UI Kit, если он есть в файле.
