# Thoughts для iPhone — дизайн-система

Статус: **согласовано** 2026-10-15. Экраны, где используются компоненты, —
[SCREENS.md](SCREENS.md) (S1–S12). Значения взяты из кода Mac: iPhone
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
| `preview/lines` | минимум ~2, максимум ~8–10 с затуханием | продуктовые решения |

## 2. Компоненты

| Компонент | Где | Варианты / состояния |
|---|---|---|
| **Space Capsule** | S1 над полем ввода | выбрана / нет; защищённый (замок); до 9 капсул — прокрутка вбок (Р3) |
| **Space Dots** | S1 над полем ввода | схлопнутые капсулы: точка на Space, текущая — вытянутая (Р12) |
| **Composer Grabber** | S1, на поле ввода в фокусе | язычок: потянуть вверх → S2 (Р17) |
| **Settings Button** | S1 справа сверху | плавающая стеклянная круглая кнопка |
| **Card (лента)** | S1 | длина: 1 строка / 2–10 / длинная с затуханием; тег: нет / 7 цветов; приватность: none / Spoiler (закрыт, открыт) / Lock (закрыт, открыт); задача в превью отмечается тапом (Р4); свайп удаления |
| **Tag Dot** | Card, навбар S2 | 7 цветов + «нет тега» (пустой круг) |
| **Star Field** | Card Spoiler/Lock | Spoiler — звёзды; Lock — звёзды + `lock.fill` 22 pt |
| **Composer** (поле ввода) | S1 низ | пусто с плейсхолдером / текст / многострочный (до ~5 строк) / над клавиатурой |
| **Sync Notice** | S1 | Offline / Sign in to iCloud / Couldn’t sync |
| **Empty Space Hint** | S1 | пусто / Syncing… |
| **Editor Nav Bar** | S2 | Tag Dot, Spoiler, Lock (вкл / выкл), меню «…» |
| **Markdown Toolbar** | S2 над клавиатурой | кнопки Bold, Italic, Strikethrough, Highlight, Heading, Bullet, Task, Quote, Code, Link; активна / нет |
| **Tag Picker** | S2 | 7 цветов + без тега, выбранный отмечен |
| **Passcode Pad** | S3, S4, S8 | точки 0–4, ошибка (встряхивание), кнопка Face ID |
| **Lock Screen** | S3 | Face ID / только код / ждём код из iCloud |
| **Settings Rows** | S7 | системные: тумблер, пикер, кнопка, статус; строка Space с тумблером видимости (Р3) |
| **Onboarding Page** | S9 | иллюстрация + заголовок + текст; последний — кнопки синка |

Системные, без своего дизайна: алерты S5, S10; меню S6; action sheet S11;
контекстное меню карточки S12 (Copy, Share, Delete) и Share-лист; Face ID.

## 3. Переиспользование с Mac

| Элемент | Файл | Как берём |
|---|---|---|
| Цвета тегов | `Shared/Card.swift` (`CardTagColor`) | уже общий |
| Разбор Markdown | `Shared/Markdown/MarkdownStyler.swift`, `MarkdownFormatting.swift` | уже общий; форматирование из панели — те же правила |
| Тексты статусов синка | `Shared/Sync/CloudSyncSettings.swift` (`CloudSyncStatus.text`) | уже общий; поправить «Mac»/«System Settings» под iPhone |
| Звёздный блюр | `Thoughts/StarFieldView.swift` (`StarFieldOverlayView`, `StarFieldCanvas`) | чистый SwiftUI → перенести в Shared |
| Стекло карточки | `Thoughts/CardSurfaceStyle.swift` (`CardSurfaceBackground`) | чистый SwiftUI, проверка `#available(macOS 26)` → добавить iOS 26 и перенести |
| Кнопки тега и приватности | `Thoughts/TagPopoverView.swift` (`TagCircleButton`, `PrivacyActionButton`) | SwiftUI — кандидат для Tag Picker и навбара S2 |
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
