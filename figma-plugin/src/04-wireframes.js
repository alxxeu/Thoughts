// Серые вайрфреймы S1 (лента) и S2 (редактор): только расположение
// элементов — без материалов, текстов и ассетов. iPhone 17 Pro 402×874.
// Страница «iOS — Wireframes». Готовый фрейм не пересобирается (его могли
// доработать руками); пересобрать — удалить фрейм в Figma и запустить снова.

const W = 402, H = 874, GAP = 120;
const SHEET_TOP = 116; // над картой редактора видна полоса размытой ленты
// true — пересобрать свои фреймы (только пока их не дорабатывали руками).
const REBUILD = false;
const C = {
  bg: '#F2F2F4', block: '#D9D9DE', dark: '#AEAEB4', line: '#C4C4CA',
  sys: '#C7C7CC', dim: '#8E8E93',
};
const hex = (h) => ({ r: parseInt(h.slice(1, 3), 16) / 255, g: parseInt(h.slice(3, 5), 16) / 255, b: parseInt(h.slice(5, 7), 16) / 255 });

function rect(parent, x, y, w, h, color, radius = 0, opacity = 1) {
  const r = figma.createRectangle();
  parent.appendChild(r);
  r.x = x; r.y = y; r.resize(w, h);
  r.cornerRadius = radius;
  r.fills = [{ type: 'SOLID', color: hex(color), opacity }];
  return r;
}
const circle = (parent, cx, cy, d, color) => rect(parent, cx - d / 2, cy - d / 2, d, d, color, d / 2);

// Строки текста серыми полосками.
function lines(parent, x, y, w, count, step = 18) {
  for (let i = 0; i < count; i++) rect(parent, x, y + i * step, i === count - 1 ? w * 0.6 : w, 8, C.line, 4);
}

// ---- общие части экрана

function chrome(f) {
  rect(f, 0, 0, W, 54, C.bg);                         // статус-бар (место)
  rect(f, 24, 20, 54, 14, C.sys, 7);                  // часы
  rect(f, W - 90, 22, 66, 12, C.sys, 6);              // индикаторы
  rect(f, (W - 134) / 2, H - 13, 134, 5, C.dim, 3);   // home indicator
}

// Карточка ленты: kind = text | long | tag | task | spoiler | lock
function card(f, y, h, kind) {
  const c = rect(f, 16, y, W - 32, h, C.block, 16);
  c.name = `Card · ${kind}`;
  if (kind === 'spoiler' || kind === 'lock') {
    // Звёзды — псевдослучайно, но одинаково при каждом запуске.
    let seed = y * 7 + h;
    const rnd = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
    for (let i = 0; i < 22; i++) circle(f, 32 + rnd() * (W - 64), y + 12 + rnd() * (h - 24), 3, C.dark);
    if (kind === 'lock') circle(f, W / 2, y + h / 2, 22, C.dark);
    return y + h;
  }
  const n = Math.max(1, Math.floor((h - 28) / 18));
  if (kind === 'task') {
    for (let i = 0; i < n; i++) { rect(f, 32, y + 14 + i * 18, 10, 10, C.dark, 3); rect(f, 50, y + 15 + i * 18, 200 - i * 20, 8, C.line, 4); }
  } else {
    lines(f, 32, y + 16, W - 96, n);
  }
  if (kind === 'long') { // затухание текста к низу карточки
    const fade = rect(f, 16, y + h - 48, W - 32, 48, C.block);
    fade.topLeftRadius = fade.topRightRadius = 0; fade.bottomLeftRadius = fade.bottomRightRadius = 16;
    const b = hex(C.block);
    fade.fills = [{ type: 'GRADIENT_LINEAR', gradientTransform: [[0, 1, 0], [-1, 0, 1]],
      gradientStops: [{ position: 0, color: { ...b, a: 0 } }, { position: 0.8, color: { ...b, a: 1 } }] }];
  }
  if (kind === 'tag' || kind === 'long') circle(f, W - 34, y + 16, 8, C.dark); // точка тега
  return y + h;
}

// Плавающая кнопка Settings справа сверху (заголовка нет — Р12).
function settingsButton(f) {
  circle(f, W - 36, 76, 36, C.sys).name = 'Settings';
  return 60; // лента идёт от верха, кнопка плавает над ней
}

const CAPSULES = [72, 88, 64, 96, 80, 70, 90, 76, 84];
const CURRENT = 2;

// Spaces над полем: 'capsules' — лента капсул, 'dots' — схлопнуты в точки.
function spaces(f, y, mode) {
  if (mode === 'capsules') {
    let x = 16;
    CAPSULES.forEach((w, i) => {
      rect(f, x, y - 46, w, 36, i === CURRENT ? C.dark : C.block, 18).name = `Space capsule ${i + 1}`;
      rect(f, x + 16, y - 32, w - 32, 8, i === CURRENT ? C.dim : C.line, 4);
      x += w + 8;
    });
    return y - 46;
  }
  const n = 9, d = 6, gap = 10, total = n * d + (n - 1) * gap + 10;
  let x = (W - total) / 2;
  for (let i = 0; i < n; i++) {
    if (i === CURRENT) { rect(f, x, y - 18, 16, d, C.dim, 3); x += 16 + gap; continue; }
    circle(f, x + d / 2, y - 18 + d / 2, d, C.dark); x += d + gap;
  }
  return y - 18;
}

// Поле ввода; typed — кнопка отправки внутри поля справа (появляется с первым символом, Р14).
function composer(f, bottom, { typed = false, multiline = false, mode = 'capsules' } = {}) {
  const h = multiline ? 96 : 48;
  const y = bottom - h;
  rect(f, 16, y, W - 32, h, C.block, 24).name = 'Composer';
  if (typed) {
    lines(f, 36, y + (multiline ? 16 : 20), W - 140, multiline ? 4 : 1);
    circle(f, W - 44, y + h - 24, 32, C.dark).name = 'Send';
  } else {
    rect(f, 36, y + 20, 140, 8, C.line, 4);           // плейсхолдер
  }
  return spaces(f, y, mode);
}

function keyboard(f) {
  const y = H - 336;
  rect(f, 0, y, W, 336, C.sys).name = 'Keyboard';
  for (let r = 0; r < 4; r++) for (let k = 0; k < 10; k++) rect(f, 6 + k * 39.6, y + 12 + r * 54, 34, 44, C.bg, 6);
  return y;
}

// Лента снизу вверх: свежая у поля. Карточки: [height, kind].
function feed(f, top, bottom, cards) {
  let y = bottom - 12;
  for (const [h, kind] of cards) {
    y -= h;
    if (y < top) break;
    card(f, y, h, kind);
    y -= 10;
  }
}

const FEED = [[64, 'text'], [150, 'long'], [64, 'lock'], [96, 'task'], [110, 'spoiler'], [64, 'tag'], [120, 'text']];

// ---- состояния

// Лента под картой редактора (размыта и притемнена).
function s1Behind(f) {
  chrome(f); const top = settingsButton(f); const sy = composer(f, H - 34);
  feed(f, top, sy - 8, FEED);
  rect(f, 0, 0, W, H, C.dim, 0, 0.35);
}

const STATES = [
  ['S1 · Лента', (f) => { chrome(f); const top = settingsButton(f); const sy = composer(f, H - 34); feed(f, top, sy - 8, FEED); }],
  ['S1 · Пустой Space', (f) => { chrome(f); settingsButton(f); const sy = composer(f, H - 34); rect(f, (W - 180) / 2, sy - 60, 180, 10, C.line, 5); }],
  ['S1 · Прокрутка вверх (капсулы → точки)', (f) => { chrome(f); const top = settingsButton(f); const sy = composer(f, H - 34, { mode: 'dots' }); feed(f, top, sy - 8, [...FEED].reverse()); }],
  ['S1 · Ввод (точки, кнопка в поле)', (f) => { chrome(f); const top = settingsButton(f); const ky = keyboard(f); const sy = composer(f, ky - 8, { typed: true, mode: 'dots' }); feed(f, top, sy - 8, FEED); }],
  ['S1 · Длинный ввод', (f) => { chrome(f); const top = settingsButton(f); const ky = keyboard(f); const sy = composer(f, ky - 8, { typed: true, multiline: true, mode: 'dots' }); feed(f, top, sy - 8, FEED); }],
  ['S2 · Карта', (f) => {
    s1Behind(f);
    const bar = H - 34 - 48;
    rect(f, 12, SHEET_TOP, W - 24, bar - 12 - SHEET_TOP, C.block, 28).name = 'Card sheet';
    circle(f, 40, SHEET_TOP + 28, 16, C.dark); circle(f, W - 44, SHEET_TOP + 28, 32, C.sys);
    lines(f, 32, SHEET_TOP + 60, W - 64, 9, 22);
    [[16, 120], [144, 118], [270, 116]].forEach(([x, w]) => rect(f, x, bar, w, 44, C.block, 22)); // тег · Spoiler · Lock
  }],
  ['S2 · Правка (клавиатура + Markdown)', (f) => {
    s1Behind(f);
    const ky = keyboard(f);
    const tb = ky - 52;
    rect(f, 8, tb, W - 16, 44, C.block, 22).name = 'Markdown toolbar';
    for (let i = 0; i < 10; i++) rect(f, 22 + i * 37, tb + 12, 20, 20, C.dark, 5);
    rect(f, 12, SHEET_TOP, W - 24, tb - 8 - SHEET_TOP, C.block, 28).name = 'Card sheet';
    circle(f, 40, SHEET_TOP + 28, 16, C.dark); circle(f, W - 44, SHEET_TOP + 28, 32, C.sys);
    lines(f, 32, SHEET_TOP + 60, W - 64, 6, 22);
    rect(f, 32, SHEET_TOP + 60 + 5 * 22 - 4, 2, 16, C.dim); // курсор
  }],
  ['S2 · Выбор тега', (f) => {
    s1Behind(f);
    const bar = H - 34 - 48;
    rect(f, 12, SHEET_TOP, W - 24, bar - 12 - SHEET_TOP, C.block, 28);
    circle(f, 40, SHEET_TOP + 28, 16, C.dark); circle(f, W - 44, SHEET_TOP + 28, 32, C.sys);
    lines(f, 32, SHEET_TOP + 60, W - 64, 9, 22);
    rect(f, 16, bar - 64, W - 32, 52, C.sys, 26).name = 'Tag picker';
    for (let i = 0; i < 8; i++) circle(f, 46 + i * 44, bar - 38, 28, i === 7 ? C.bg : C.dark);
    [[16, 120], [144, 118], [270, 116]].forEach(([x, w]) => rect(f, x, bar, w, 44, C.block, 22));
  }],
  ['S2 · Меню «…»', (f) => {
    s1Behind(f);
    const bar = H - 34 - 48;
    rect(f, 12, SHEET_TOP, W - 24, bar - 12 - SHEET_TOP, C.block, 28);
    circle(f, 40, SHEET_TOP + 28, 16, C.dark); circle(f, W - 44, SHEET_TOP + 28, 32, C.sys);
    lines(f, 32, SHEET_TOP + 60, W - 64, 9, 22);
    rect(f, W - 236, SHEET_TOP + 50, 210, 3 * 44, C.sys, 18).name = 'Menu: Copy · Share · Delete';
    for (let i = 0; i < 3; i++) rect(f, W - 216, SHEET_TOP + 68 + i * 44, 90, 8, i === 2 ? C.dim : C.dark, 4);
    [[16, 120], [144, 118], [270, 116]].forEach(([x, w]) => rect(f, x, bar, w, 44, C.block, 22));
  }],
];

run(async (log) => {
  const page = pageNamed('iOS — Wireframes');
  await page.loadAsync();
  let made = 0;
  if (REBUILD) { // убрать свои фреймы состояний, которых больше нет в списке
    const names = new Set(STATES.map(([n]) => `wf:${n}`));
    page.findAll((n) => n.getPluginData(MARK).startsWith('wf:') && !names.has(n.getPluginData(MARK))).forEach((n) => n.remove());
  }
  STATES.forEach(([name, draw], i) => {
    const key = `wf:${name}`;
    const old = findMarked(key, page);
    if (old && REBUILD) old.remove();
    else if (old) { log.push(`есть, не трогаю: ${name}`); return; }
    const f = mark(figma.createFrame(), key);
    page.appendChild(f);
    f.name = name;
    f.resize(W, H);
    f.x = i * (W + GAP) + (name.startsWith('S2') ? 200 : 0);
    f.cornerRadius = 48;
    f.clipsContent = true;
    f.fills = [{ type: 'SOLID', color: hex(C.bg) }];
    draw(f);
    made++;
  });
  await figma.setCurrentPageAsync(page);
  figma.viewport.scrollAndZoomIntoView(page.children);
  for (const [name] of STATES) {
    const f = findMarked(`wf:${name}`, page);
    if (f) await snap(f, `wf-${STATES.findIndex(([n]) => n === name) + 1}`, 1);
  }
  return `Фреймов: ${STATES.length}, новых: ${made}`;
});
