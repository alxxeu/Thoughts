// Страница «iOS — References»: пустая секция на каждый экран S1–S12 с
// подписью — за что отвечает экран, функции и блоки, состояния (по
// docs/ios/SCREENS.md). Референсы автор вкладывает в секции руками.
// Повторный запуск обновляет только подписи; секции и всё, что в них
// положили, не трогает.

const SCREENS = [
  ['S1', 'Лента Space', 'Главный экран. Space = чат, карточка = сообщение: быстро записать и подсмотреть.', [
    'Вкладки Spaces сверху; свайп по ленте переключает Space (как папки в Telegram). По умолчанию все 9, скрытые — нет',
    'Навбар: Settings; меню Space (Rename, Lock Space)',
    'Лента карточек: каждая — отдельный блок; свежие внизу, у поля ввода; порядок не меняется под пальцем',
    'Превью: 2–10 строк с затуханием, Markdown отрисован; точка тега в углу',
    'Spoiler — звёздный блюр, тап открывает; Lock — замок и минимальная высота',
    'Задача [ ] в превью отмечается тапом',
    'Свайп влево → Delete; долгое нажатие → меню Copy / Share / Delete',
    'Поле ввода внизу: только текст, без «+» и микрофона; растёт до ~5 строк',
    'Строка проблемы синка: Offline / Sign in to iCloud / Couldn’t sync (только при включённом синке)',
  ], 'пустой Space · Syncing… · короткие/длинные карточки · тег · Spoiler закрыт/открыт · Lock закрыт/открыт · Space закрыт (S3) · офлайн · клавиатура открыта · длинный ввод'],
  ['S2', 'Редактор карточки', 'Полноэкранная правка одной карточки; тег, Spoiler и Lock меняются только здесь.', [
    'Навбар: назад (сохранение автоматическое); точка тега → 7 цветов + «без тега»',
    'Переключатели Spoiler и Lock',
    'Меню «…»: Copy, Share, Delete',
    'Текст целиком; разметка видна в строке под курсором, в остальных спрятана',
    'Панель Markdown над клавиатурой: Bold, Italic, Strikethrough, Highlight, Heading, Bullet, Task, Quote, Code, Link',
  ], 'просмотр · правка с клавиатурой · правка пришла с Mac (текст не меняется под курсором) · тег/Spoiler/Lock включены · пустой текст → карточка удаляется'],
  ['S3', 'Экран блокировки Space', 'Закрывает защищённый Space целиком, пока не введён код или Face ID.', [
    'Замок, имя Space',
    'Unlock with Face ID (предлагается сразу при открытии Space)',
    'Клавиатура кода: 4 цифры, ошибка — встряхивание точек',
    'Fail-closed: «Waiting for your passcode from iCloud», если Space защищён, а код ещё не доехал',
  ], 'Face ID · только код · ждём код из iCloud · неверный код'],
  ['S4', 'Открыть Lock-карточку', 'Доступ к закрытой карточке. Один раз на сессию: дальше Lock-карточки открываются тапом до ухода в фон / Auto-Lock.', [
    'Системный Face ID',
    'При отказе — клавиатура кода (как в S3) в шторке',
  ], 'Face ID · код · отказ'],
  ['S5', 'Переименовать Space', 'Имя Space, без Mac.', [
    'Алерт с полем: текущее имя, до 30 символов',
    'Пустое имя → «Space N»',
  ], 'системный алерт'],
  ['S6', 'Меню Space', 'Действия с текущим Space из навбара ленты.', [
    'Rename… → S5',
    'Lock Space (если Space Lock включён) / Turn Off Lock for This Space',
  ], 'Space Lock выключен · Space защищён · не защищён'],
  ['S7', 'Settings', 'Все настройки iPhone: синк, Space Lock, видимость Spaces, внешний вид, о приложении.', [
    'iCloud: Sync with iCloud, статус, Sync Now / Try Again, «Your Mac and iPhone share the same Thoughts»',
    'Space Lock: Passcode, Change Passcode…, Use Face ID, Auto-Lock (Never … 1 hour + при уходе в фон), защита по Spaces',
    'Spaces: показать/скрыть каждый Space, Hide Empty Spaces, Show All (настройка этого iPhone)',
    'Appearance: Theme Auto / Light / Dark; Text Size — Dynamic Type или S / M / L / XL',
    'About: версия, Replay Onboarding, GitHub, Telegram, Email, «Thoughts for Mac»',
  ], 'синк выкл / включается / Up to date / Offline / нет аккаунта / ошибка · Space Lock выкл · текущий Space закрыт'],
  ['S8', 'Код: задать / сменить', 'Свой код Space Lock на iPhone (с синком — общий с Mac через iCloud Keychain).', [
    'Ввести 4 цифры → повторить',
    'При смене — сначала текущий код',
  ], 'ввод · повтор · не совпало · смена'],
  ['S9', 'Онбординг', 'Короткое знакомство, работает без Mac; последний шаг — выбор синка с намёком «лучше с Mac».', [
    '1. Welcome — лента и поле ввода',
    '2. Spaces — вкладки и свайп; теги, Spoiler, Lock',
    '3. Private — Space Lock и Lock карточки (Face ID)',
    '4. Sync — «Thoughts is best with your Mac»: Sync with iCloud / Not Now',
    'Можно пропустить; повтор — Settings → About',
  ], '4 страницы · пропуск'],
  ['S10', 'Выбор при первом синке', 'Данные есть и на iPhone, и в iCloud — решить, что с ними делать.', [
    '«Your Thoughts are already in iCloud»',
    'Merge / Use iCloud / Use This iPhone',
    'Перед выбором — автобэкап',
  ], 'системный алерт'],
  ['S11', 'Подтверждение удаления', 'Защита от случайного удаления карточки.', [
    'Action sheet: Delete Card (деструктивное) / Cancel',
    'Lock-карточка — сначала Face ID (S4)',
  ], 'обычная · Lock'],
  ['S12', 'Меню карточки (долгое нажатие)', 'Быстрые действия с карточкой прямо из ленты.', [
    'Системное контекстное меню с превью карточки',
    'Copy — текст в буфер',
    'Share — системный лист',
    'Delete → S11',
  ], 'обычная · закрытая Lock (сначала S4)'],
];

const W = 1600, H = 1000, GAP = 160, PER_ROW = 3;

run(async (log) => {
  await figma.loadFontAsync({ family: 'Inter', style: 'Regular' });
  await figma.loadFontAsync({ family: 'Inter', style: 'Bold' });
  const page = pageNamed('iOS — References');
  await page.loadAsync();

  let created = 0;
  SCREENS.forEach(([id, title, purpose, blocks, states], i) => {
    let section = findMarked(`ref:${id}`, page);
    if (!section) {
      section = mark(figma.createSection(), `ref:${id}`);
      page.appendChild(section);
      section.x = (i % PER_ROW) * (W + GAP);
      section.y = Math.floor(i / PER_ROW) * (H + GAP);
      section.resizeWithoutConstraints(W, H);
      created++;
    }
    section.name = `${id} · ${title}`;
    // Светлая секция читается и в светлой, и в тёмной теме Figma.
    section.fills = [{ type: 'SOLID', color: { r: 0.96, g: 0.96, b: 0.97 } }];

    let label = findMarked(`ref-label:${id}`, section);
    if (!label) {
      label = mark(figma.createText(), `ref-label:${id}`);
      section.appendChild(label);
      label.x = 40; label.y = 40;
      label.resize(520, 100);
    }
    const head = `${id} · ${title}`;
    label.characters = [head, '', purpose, '', 'Функции и блоки:', ...blocks.map((b) => `• ${b}`),
      '', `Состояния: ${states}`, '', 'Референсы — правее →'].join('\n');
    label.fontName = { family: 'Inter', style: 'Regular' };
    label.fontSize = 16;
    label.lineHeight = { value: 150, unit: 'PERCENT' };
    label.setRangeFontName(0, head.length, { family: 'Inter', style: 'Bold' });
    label.setRangeFontSize(0, head.length, 28);
    label.fills = [{ type: 'SOLID', color: { r: 0.12, g: 0.12, b: 0.14 } }];
    // resize фиксирует обе оси — высоту возвращаем по тексту (figma-api-gotchas).
    label.textAutoResize = 'HEIGHT';
  });

  await figma.setCurrentPageAsync(page);
  figma.viewport.scrollAndZoomIntoView(page.children);
  await snap(findMarked('ref:S1', page), 'ref-S1', 1);
  return `Секций: ${SCREENS.length}, новых: ${created}`;
});
