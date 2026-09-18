# Backlog — Thoughts

Рабочий бэклог проекта. Протокол работы с этим файлом — в
[`EXECUTE.md`](./EXECUTE.md). Каждая задача идёт по пути:

```
Backlog / Идеи → В работе (план согласован) → Готово
```

---

## В работе

_(пусто)_

---

## Backlog / Идеи

_(сюда попадают новые задачи и идеи до того, как для них согласован план —
см. EXECUTE.md, Правило 2)_

---

## Готово

> Раздел ниже восстановлен по `git log` на момент создания бэклога
> (2026-09-18) — это снимок того, что уже сделано, а не живая история
> планирования (её для этих задач не велось). Начиная с этого файла,
> новые задачи проходят полный цикл выше.

### Core / доска карточек
- Доска карточек и Spaces: переключение, переименование, drag/resize/create
- Кастомный NSTextView-редактор карточек вместо `TextEditor`
- Персистентность форматирования текста (bold и т.д.) между перезапусками и переключением Spaces
- Списки: авто-буллеты (`- `), нумерованные списки, чекбоксы (`[] `)
- Разделитель по `---`
- Spoiler / Lock для отдельных карточек (звёздное поле, запрет выделения под маркером)
- Tidy Cards: упаковка к ближайшему углу, кластеризация карточек по тегу
- Clear Space, лимит длины имени Space

### Spotlight
- Индексация карточек в системный Spotlight (кроме spoiler/lock карточек)
- Переход по результату поиска: активация приложения, переключение на нужный Space, подсветка карточки — через `NSApplicationDelegate.application(_:continue:restorationHandler:)`, так как `.onContinueUserActivity` на SwiftUI-View для уже запущенного macOS-приложения ненадёжен

### Security / Space Lock
- Per-Space passcode lock — независимая блокировка каждого Space (не всего приложения)
- Cmd+L — заблокировать текущий Space немедленно
- "Manage Space Locks" в Settings — включение/выключение защиты по каждому Space отдельно
- Touch ID как опциональная надстройка поверх обязательного passcode
- Passcode — 4 физические клавиши (не только цифры), хранится в Keychain (не в UserDefaults/plaintext)
- Idle auto-lock с настраиваемым интервалом (Never / 30 сек / 1 / 5 / 10 / 30 мин / 1 час)
- Settings недоступны из заблокированного Space (защита от обхода lock screen)
- Системные шорткаты пропускаются через passcode key capture, не блокируются им

### AI (BYOK)
- Интеграция ChatGPT и Claude по собственному API-ключу пользователя
- Apple Intelligence как третий провайдер — on-device, без API-ключа
- Ask AI для отдельной карточки и для всего Space целиком
- Extract Action Items
- Полировка AI-настроек: шит для API-ключей, плейсхолдеры, постоянный AI-бейдж

### Onboarding / UI
- Onboarding-тур при первом запуске, позже переработан в интерактивный
  gesture-gated тур; повторить в любой момент через Settings → General →
  "Replay Onboarding", продублировано в системном меню Help
- Светлая/тёмная тема (адаптация UI под системный Appearance)
- Desktop Overlay mode (экспериментальный режим, тумблер в Settings,
  продублирован в системном меню Window)
- About tab и privacy policy (для App Store)
- Toolbar Space переработан в кластер иконок
- Многочисленная визуальная полировка: Liquid Glass фон карточек, tag dimming, контраст toolbar/Ask AI поверх реальных фонов, hover-тултип на имени Space, фикс "карточки просвечивают" при переходе в Lock

### Settings → Shortcuts
- Справочный список шорткатов приложения (Lock Space ⌘L, Show Desktop
  ⌥D, Switch Between Spaces ⌥1–9) с названием и кратким описанием у
  каждого — только для просмотра, сами комбинации фиксированы и не
  переназначаются. ⌘Q и Escape-хендлеры не входят (системные конвенции),
  как и встроенный `TextFormattingCommands()`

### Инфраструктура
- LICENSE, README
- Рефакторинг: security fixes, dead code, консистентность (проходы Stage A–C)
- Performance pass: более дешёвый Spotlight reindex, gesture guard, ограничение числа звёзд в StarFieldCanvas
- Xcode: dead-code stripping, string catalog по рекомендациям Xcode
- Версия приложения 1.1, поднят build number для App Store
