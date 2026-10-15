// Экраны S1 (лента) и S2 (редактор) в тёмной теме из компонентов Thoughts
// и элементов библиотеки iOS 27 — те же 9 состояний, что в вайрфреймах.
// Страница «iOS — Screens». Готовый экран не пересобирается, если его имени
// нет в REBUILD (true — все).
const KIT = __JSON_kit.json__;
const SYMBOLS = __JSON_symbols.json__;
const REBUILD = []; // имена экранов для пересборки; true — все
const W = 402, H = 874, GAP = 120, SHEET_TOP = 116;
const rebuilds = (name) => REBUILD === true || (Array.isArray(REBUILD) && REBUILD.includes(name));

const SPACES = ['Thoughts', 'Healer', 'Work', 'Space 4', 'Daily', 'Ideas', 'Space 7', 'Space 8', 'Space 9'];
const CURRENT = 4; // Daily

// Лента снизу вверх: первая — свежая, у поля ввода.
const FEED = [
  { kind: 'Text', tag: false, text: 'Call mom about the weekend — she wanted to plan the garden.' },
  { kind: 'Task', tag: true },
  { kind: 'Lock', tag: false },
  { kind: 'Long', tag: true },
  { kind: 'Text', tag: false, text: 'Idea: a widget that shows one random card from Ideas every morning.' },
  { kind: 'Spoiler', tag: true },
  { kind: 'Text', tag: true, text: 'Dentist — Thursday 9:30' },
];

let C = null; // компоненты со страницы «iOS — Components»
async function components() {
  const page = pageNamed('iOS — Components');
  await page.loadAsync();
  const card = findMarked('cmp:card', page);
  const variant = (set, name) => set.children.find((c) => c.name === name);
  C = {
    card: (kind) => variant(card, `Kind=${kind}`),
    capsule: (sel) => variant(findMarked('cmp:capsule', page), `State=${sel ? 'Selected' : 'Default'}`),
    dots: findMarked('cmp:dots', page),
    settings: findMarked('cmp:settings', page),
    composer: (state) => variant(findMarked('cmp:composer', page), `State=${state}`),
    editor: findMarked('cmp:editor', page),
    editorBar: findMarked('cmp:editorbar', page),
    mdbar: findMarked('cmp:mdbar', page),
    tagPicker: findMarked('cmp:tagpicker', page),
    menu: findMarked('cmp:menu', page),
  };
  for (const [k, val] of Object.entries(C)) if (!val) throw new Error(`нет компонента ${k} — сначала 08-components`);
}

async function setText(node, chars) {
  const t = node.findOne((n) => n.type === 'TEXT');
  await figma.loadFontAsync(t.fontName);
  t.characters = chars;
}

// ---- части экрана

async function backdrop(f) {
  const top = (await boundFill('bg/top')).color, bottom = (await boundFill('bg/bottom')).color;
  f.fills = [{ type: 'GRADIENT_LINEAR', gradientTransform: [[0, 1, 0], [-1, 0, 1]],
    gradientStops: [{ position: 0, color: { ...top, a: 1 } }, { position: 1, color: { ...bottom, a: 1 } }] }];
}

async function statusBar(f) {
  const sb = await libInstance(KIT, 'Status bar - iPhone 17 Pro');
  f.appendChild(sb); sb.x = 0; sb.y = 0;
  // Тёмная тема: время и индикаторы белые, Dynamic Island остаётся чёрным.
  sb.findAll((n) => 'fills' in n && n.type !== 'INSTANCE' && n.name !== 'Dynamic Island' && Array.isArray(n.fills) && n.fills.length)
    .forEach((n) => { n.fills = [{ type: 'SOLID', color: { r: 1, g: 1, b: 1 } }]; });
}

function homeIndicator(f) {
  const r = figma.createRectangle(); r.name = 'Home Indicator';
  r.resize(134, 5); r.cornerRadius = 3; r.x = (W - 134) / 2; r.y = H - 13;
  r.fills = [{ type: 'SOLID', color: { r: 1, g: 1, b: 1 } }];
  f.appendChild(r);
}

function settingsButton(f) {
  const b = C.settings.createInstance(); f.appendChild(b); b.x = W - 16 - b.width; b.y = 58;
}

async function feed(f, bottom, items = FEED) {
  let y = bottom;
  for (const it of items) {
    const c = C.card(it.kind).createInstance();
    c.setProperties({ [Object.keys(c.componentProperties).find((k) => k.startsWith('Tag'))]: it.tag });
    if (it.text) await setText(c, it.text);
    y -= c.height;
    if (y < 56) { c.remove(); break; }
    f.appendChild(c); c.x = 16; c.y = y;
    y -= 10;
  }
}

// Капсулы Spaces над полем ввода; возвращает верх ряда.
async function capsules(f, y) {
  const row = autoFrame('Spaces', 'HORIZONTAL', { gap: 8 });
  for (let i = 0; i < SPACES.length; i++) {
    const c = C.capsule(i === CURRENT).createInstance();
    await setText(c, SPACES[i]);
    row.appendChild(c);
  }
  f.appendChild(row); row.x = 16 - 70; row.y = y - row.height; // прокручено: текущая ближе к центру
  return row.y;
}

function dots(f, y) {
  const d = C.dots.createInstance(); f.appendChild(d); d.x = (W - d.width) / 2; d.y = y - 6 - d.height;
  return d.y;
}

async function grabber(f, y) {
  const g = await libInstance(KIT, 'Grabber', 'Mode=Dark');
  f.appendChild(g); g.x = (W - g.width) / 2; g.y = y - 10 - g.height;
  return g.y;
}

async function keyboard(f) {
  const k = await libInstance(KIT, 'Keyboard', 'Type=Lower Case');
  f.appendChild(k); k.x = 0; k.y = H - k.height;
  return k.y;
}

function composerAt(f, state, bottom) {
  const c = C.composer(state).createInstance(); f.appendChild(c);
  c.x = 16; c.y = bottom - c.height;
  return c.y;
}

// Лента S1 под редактором: размыта и притемнена (полоса сверху видна).
async function s1Behind(f) {
  settingsButton(f);
  const cy = composerAt(f, 'Empty', H - 34);
  const sy = await capsules(f, cy - 10);
  await feed(f, sy - 12);
  const veil = figma.createRectangle(); veil.name = 'Dim + Blur'; veil.resize(W, H);
  veil.fills = [{ type: 'SOLID', color: { r: 0, g: 0, b: 0 }, opacity: 0.35 }];
  veil.effects = [{ type: 'BACKGROUND_BLUR', radius: 18, visible: true }];
  f.appendChild(veil);
}

function editorAt(f, bottom) {
  const e = C.editor.createInstance(); f.appendChild(e);
  e.x = (W - e.width) / 2; e.y = SHEET_TOP; e.resize(e.width, bottom - SHEET_TOP);
  return e;
}

function editorBar(f) {
  const b = C.editorBar.createInstance(); f.appendChild(b);
  b.x = (W - b.width) / 2; b.y = H - 34 - b.height;
  return b.y;
}

// ---- состояния

const STATES = [
  ['S1 · Лента', async (f) => {
    settingsButton(f);
    const cy = composerAt(f, 'Empty', H - 34);
    const sy = await capsules(f, cy - 10);
    await feed(f, sy - 12);
  }],
  ['S1 · Пустой Space', async (f) => {
    settingsButton(f);
    const cy = composerAt(f, 'Empty', H - 34);
    const sy = await capsules(f, cy - 10);
    const hint = await label('Type a thought below', 'Thoughts/Card Body', 'card/text-secondary');
    f.appendChild(hint); hint.x = (W - hint.width) / 2; hint.y = sy - 60;
  }],
  ['S1 · Прокрутка вверх (капсулы → точки)', async (f) => {
    settingsButton(f);
    const cy = composerAt(f, 'Empty', H - 34);
    const dy = dots(f, cy);
    await feed(f, dy - 12, [...FEED].reverse());
  }],
  ['S1 · Ввод (язычок, кнопка в поле)', async (f) => {
    settingsButton(f);
    const ky = await keyboard(f);
    const cy = composerAt(f, 'Typed', ky - 8);
    const gy = await grabber(f, cy);
    await feed(f, gy - 12);
  }],
  ['S1 · Длинный ввод (язычок)', async (f) => {
    settingsButton(f);
    const ky = await keyboard(f);
    const cy = composerAt(f, 'Long', ky - 8);
    const gy = await grabber(f, cy);
    await feed(f, gy - 12);
  }],
  ['S2 · Карта', async (f) => {
    await s1Behind(f);
    const by = editorBar(f);
    editorAt(f, by - 12);
  }],
  ['S2 · Правка (клавиатура + Markdown)', async (f) => {
    await s1Behind(f);
    const ky = await keyboard(f);
    const tb = C.mdbar.createInstance(); f.appendChild(tb); tb.x = (W - tb.width) / 2; tb.y = ky - 8 - tb.height;
    editorAt(f, tb.y - 8);
  }],
  ['S2 · Выбор тега', async (f) => {
    await s1Behind(f);
    const by = editorBar(f);
    editorAt(f, by - 12);
    const tp = C.tagPicker.createInstance(); f.appendChild(tp); tp.x = (W - tp.width) / 2; tp.y = by - 10 - tp.height;
  }],
  ['S2 · Меню «…»', async (f) => {
    await s1Behind(f);
    const by = editorBar(f);
    editorAt(f, by - 12);
    const m = C.menu.createInstance(); f.appendChild(m); m.x = W - 24 - m.width; m.y = SHEET_TOP + 54;
  }],
];

run(async (log) => {
  await components();
  const page = pageNamed('iOS — Screens');
  await page.loadAsync();
  await figma.setCurrentPageAsync(page);
  let made = 0;
  for (let i = 0; i < STATES.length; i++) {
    const [name, draw] = STATES[i];
    const key = `scr:${name}`;
    const old = findMarked(key, page);
    if (old && !rebuilds(name)) { log.push(`есть, не трогаю: ${name}`); continue; }
    if (old) old.remove();
    const f = mark(figma.createFrame(), key);
    page.appendChild(f);
    f.name = name; f.resize(W, H); f.cornerRadius = 48; f.clipsContent = true;
    f.x = i * (W + GAP) + (name.startsWith('S2') ? 200 : 0); f.y = 0;
    await backdrop(f);
    await draw(f);
    await statusBar(f);
    homeIndicator(f);
    await snap(f, `scr-${i + 1}`, 1);
    made++;
  }
  figma.viewport.scrollAndZoomIntoView(page.children);
  return `Экранов: ${STATES.length}, собрано: ${made}`;
});
