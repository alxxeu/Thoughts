# Smart Tidy — отложено (2026-11-05)

Переработка Tidy Cards (группы, выравнивание размеров, углы + остров, Undo, Apple Intelligence) отложена: результат на реальных Spaces не понравился. В основном коде Tidy возвращён к исходному (4 угла, `tidyCards` в `BoardViewModel`).

- `plan.md` — согласованный план.
- `TidyLayout.swift`, `TidyAIGrouping.swift`, `TidyLayoutTests.swift` — файлы, положить в `Thoughts/` и `ThoughtsTests/`.
- `tracked-changes.patch` — правки в `BoardViewModel`, `SpaceToolbar`, `AISettings`, `AISettingsView` (`git apply`).
- Выводы: `NLEmbedding` не годится (нет русского, слабая близость); углы + остров плохо читаются, одна сетка по центру — тоже не то.
