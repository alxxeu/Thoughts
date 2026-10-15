// Компоненты Thoughts для iPhone (тёмная тема) на деталях библиотеки
// iOS and iPadOS 27: стекло — материалы Liquid Glass, иконки — SF Symbols.
// Страница «iOS — Components». REBUILD — пересобрать (пока не правили руками).
const KIT = __JSON_kit.json__;
const SYMBOLS = __JSON_symbols.json__;
const REBUILD = false; // true — пересобрать (пока не правили руками)
const CARD_W = 370;
const SMALL = 'Liquid Glass - Regular - Small';
const MEDIUM = 'Liquid Glass - Regular - Medium';
const CLEAR = 'Liquid Glass - Clear';

// Звёзды Spoiler/Lock — псевдослучайно, одинаково при каждом запуске.
async function stars(parent, w, h, seed) {
  const paint = await boundFill('card/star');
  const rnd = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);
  const g = figma.createFrame();
  g.name = 'Stars'; g.fills = []; g.resize(w, h); g.clipsContent = true;
  for (let i = 0; i < Math.round(w * h / 420); i++) {
    const d = 1 + rnd() * 1.6;
    const s = figma.createEllipse();
    s.resize(d, d); s.x = 12 + rnd() * (w - 24); s.y = 10 + rnd() * (h - 20);
    s.fills = [{ ...paint, opacity: 0.25 + rnd() * 0.65 }];
    g.appendChild(s);
  }
  return g;
}

async function tagDot(color = 'tag/blue') {
  const d = figma.createEllipse();
  d.name = 'Tag'; d.resize(10, 10); d.fills = [await boundFill(color)];
  return d;
}

// ---- Card

const SAMPLES = {
  Text: ['Call mom about the weekend — she wanted to plan the garden.'],
  Long: ['Trip to Lisbon', 'Book the tram tour for Tuesday morning. Pastéis de Belém before 10, the line gets long. Ask Ana about the fado place in Alfama she mentioned. Check if the LX Factory market is open on Sunday. Pack the light jacket — evenings get windy by the river. Download offline maps before the flight.'],
  Task: [['Oat milk', true], ['Sourdough bread', false], ['Lemons ×3', false]],
};

async function cardVariant(kind) {
  const c = figma.createComponent();
  c.name = `Kind=${kind}`;
  c.layoutMode = 'VERTICAL'; c.itemSpacing = 6;
  c.paddingLeft = c.paddingRight = 16; c.paddingTop = c.paddingBottom = 14;
  // resize() фиксирует обе оси — режимы размеров ставим после него.
  c.resize(CARD_W, 64); c.primaryAxisSizingMode = 'AUTO'; c.counterAxisSizingMode = 'FIXED';
  c.cornerRadius = 16; c.fills = []; c.clipsContent = false;

  if (kind === 'Text') {
    const t = await label(SAMPLES.Text[0], 'Thoughts/Card Body'); c.appendChild(t); t.layoutSizingHorizontal = 'FILL';
  } else if (kind === 'Long') {
    const h = await label(SAMPLES.Long[0], 'Thoughts/Card Heading'); c.appendChild(h); h.layoutSizingHorizontal = 'FILL';
    const t = await label(SAMPLES.Long[1], 'Thoughts/Card Body'); c.appendChild(t); t.layoutSizingHorizontal = 'FILL';
    // Превью до ~8 строк, низ затухает (продуктовое решение).
    t.textAutoResize = 'NONE'; t.resize(t.width, 128); t.textTruncation = 'DISABLED';
    const base = (await boundFill('card/text')).color;
    t.fills = [{ type: 'GRADIENT_LINEAR', gradientTransform: [[0, 1, 0], [-1, 0, 1]],
      gradientStops: [{ position: 0, color: { ...base, a: 0.88 } }, { position: 0.6, color: { ...base, a: 0.88 } }, { position: 1, color: { ...base, a: 0 } }] }];
  } else if (kind === 'Task') {
    for (const [text, done] of SAMPLES.Task) {
      const row = autoFrame('Task', 'HORIZONTAL', { gap: 8 }); row.counterAxisAlignItems = 'CENTER';
      row.appendChild(await icon(SYMBOLS, done ? 'checkmark.square.fill' : 'square', 17, done ? 'card/text-secondary' : 'card/text'));
      const t = await label(text, 'Thoughts/Card Body', done ? 'card/text-secondary' : 'card/text');
      if (done) t.textDecoration = 'STRIKETHROUGH';
      row.appendChild(t);
      c.appendChild(row);
    }
  } else {
    // Spoiler / Lock: содержимое скрыто — фиксированная высота, звёзды поверх тона.
    c.primaryAxisSizingMode = 'FIXED';
    c.resize(CARD_W, kind === 'Lock' ? 64 : 104);
    c.primaryAxisAlignItems = 'CENTER'; c.counterAxisAlignItems = 'CENTER';
    if (kind === 'Lock') c.appendChild(await icon(SYMBOLS, 'lock.fill', 22));
  }

  // Стекло под содержимым; у приватных — тон и звёзды.
  const g = await glass(KIT, CLEAR, '', CARD_W, c.height, 16);
  if (kind === 'Spoiler' || kind === 'Lock') {
    const tint = figma.createRectangle(); tint.name = 'Privacy tint'; tint.cornerRadius = 16; tint.fills = [await boundFill('card/privacy-tint')];
    pinBehind(c, tint, 0);
    const st = await stars(c, CARD_W, c.height, kind === 'Lock' ? 7 : 3);
    pinBehind(c, st, 1);
  }
  pinBehind(c, g, 0);

  // Точка тега — в правом верхнем углу, включается свойством.
  const dot = await tagDot();
  c.appendChild(dot); dot.layoutPositioning = 'ABSOLUTE'; dot.x = CARD_W - 22; dot.y = 12;
  dot.constraints = { horizontal: 'MAX', vertical: 'MIN' };
  return c;
}

// ---- Простые компоненты

async function capsule(selected) {
  const c = figma.createComponent();
  c.name = `State=${selected ? 'Selected' : 'Default'}`;
  c.layoutMode = 'HORIZONTAL'; c.paddingLeft = c.paddingRight = 16; c.paddingTop = c.paddingBottom = 9;
  c.primaryAxisSizingMode = 'AUTO'; c.counterAxisSizingMode = 'AUTO'; c.fills = [];
  const t = await label('Daily', 'Thoughts/Card Heading', selected ? 'card/text' : 'card/text-secondary');
  t.fontSize = 15; c.appendChild(t);
  pinBehind(c, await glass(KIT, SMALL, `Mode=Dark, Active=${selected ? 'True' : 'False'}, Prominent=False`, c.width, c.height), 0);
  return c;
}

async function spaceDots() {
  const c = figma.createComponent();
  c.name = 'Space Dots';
  c.layoutMode = 'HORIZONTAL'; c.itemSpacing = 8; c.counterAxisAlignItems = 'CENTER';
  c.primaryAxisSizingMode = 'AUTO'; c.counterAxisSizingMode = 'AUTO'; c.fills = [];
  for (let i = 0; i < 9; i++) {
    const d = figma.createRectangle();
    d.resize(i === 2 ? 16 : 6, 6); d.cornerRadius = 3;
    d.fills = [await boundFill(i === 2 ? 'card/text' : 'card/text-secondary')];
    c.appendChild(d);
  }
  return c;
}

async function circleButton(name, symbol, size = 44, glyph = 20) {
  const c = figma.createComponent();
  c.name = name; c.resize(size, size); c.fills = [];
  c.layoutMode = 'HORIZONTAL'; c.primaryAxisAlignItems = 'CENTER'; c.counterAxisAlignItems = 'CENTER';
  c.primaryAxisSizingMode = 'FIXED'; c.counterAxisSizingMode = 'FIXED';
  c.appendChild(await icon(SYMBOLS, symbol, glyph));
  pinBehind(c, await glass(KIT, SMALL, 'Mode=Dark, Active=False, Prominent=False', size, size), 0);
  return c;
}

// Кнопка отправки внутри поля: синий круг со стрелкой (Р14).
async function sendButton() {
  const b = figma.createFrame();
  b.name = 'Send'; b.resize(32, 32); b.cornerRadius = 16; b.fills = [await boundFill('tag/blue')];
  b.layoutMode = 'HORIZONTAL'; b.primaryAxisAlignItems = 'CENTER'; b.counterAxisAlignItems = 'CENTER';
  b.primaryAxisSizingMode = 'FIXED'; b.counterAxisSizingMode = 'FIXED';
  const a = await icon(SYMBOLS, 'arrow.up', 15);
  a.findAll((n) => n.type === 'VECTOR').forEach((n) => { n.fills = [{ type: 'SOLID', color: { r: 1, g: 1, b: 1 } }]; });
  b.appendChild(a);
  return b;
}

async function composer(state) {
  const c = figma.createComponent();
  c.name = `State=${state}`;
  c.layoutMode = 'HORIZONTAL'; c.itemSpacing = 8;
  c.paddingLeft = 18; c.paddingRight = state === 'Empty' ? 18 : 8; c.paddingTop = c.paddingBottom = state === 'Empty' ? 15 : 8;
  c.counterAxisAlignItems = state === 'Long' ? 'MAX' : 'CENTER';
  c.resize(CARD_W, 48); c.primaryAxisSizingMode = 'FIXED'; c.counterAxisSizingMode = 'AUTO'; c.fills = [];
  const text = state === 'Empty' ? 'Type a thought…'
    : state === 'Typed' ? 'Ask Ana about the fado place'
      : 'Ideas for the onboarding:\n— show the feed first\n— Spaces as capsules\n— hint about the Mac app';
  const t = await label(text, 'Thoughts/Card Body', state === 'Empty' ? 'card/text-secondary' : 'card/text');
  c.appendChild(t); t.layoutGrow = 1;
  if (state !== 'Empty') { t.layoutSizingVertical = 'HUG'; c.paddingTop = c.paddingBottom = 8; c.appendChild(await sendButton()); }
  pinBehind(c, await glass(KIT, MEDIUM, 'Mode=Dark', CARD_W, c.height, 24), 0);
  return c;
}

async function editorCard() {
  const c = figma.createComponent();
  c.name = 'Editor Card'; c.resize(378, 620); c.fills = []; c.clipsContent = false;
  const g = await glass(KIT, MEDIUM, 'Mode=Dark', 378, 620, 28);
  c.appendChild(g); g.constraints = { horizontal: 'STRETCH', vertical: 'STRETCH' };
  const dot = await tagDot(); dot.resize(16, 16); c.appendChild(dot); dot.x = 22; dot.y = 22;
  const more = await icon(SYMBOLS, 'ellipsis', 20); c.appendChild(more); more.x = 378 - 22 - more.width; more.y = 28;
  more.constraints = { horizontal: 'MAX', vertical: 'MIN' };
  const h = await label(SAMPLES.Long[0], 'Thoughts/Card Heading'); c.appendChild(h); h.x = 22; h.y = 58;
  h.textAutoResize = 'HEIGHT'; h.resize(334, h.height); h.constraints = { horizontal: 'STRETCH', vertical: 'MIN' };
  const body = autoFrame('Body', 'VERTICAL', { gap: 6 }); c.appendChild(body); body.x = 22; body.y = 90;
  const t = await label(SAMPLES.Long[1], 'Thoughts/Card Body'); body.appendChild(t);
  t.textAutoResize = 'HEIGHT'; t.resize(334, t.height);
  const gap = figma.createFrame(); gap.name = 'Gap'; gap.fills = []; gap.resize(334, 6); body.appendChild(gap);
  for (const task of ['Book tram tour', 'Offline maps']) { // Markdown спрятан: задачи — галочками
    const row = autoFrame('Task', 'HORIZONTAL', { gap: 8 }); row.counterAxisAlignItems = 'CENTER';
    row.appendChild(await icon(SYMBOLS, 'square', 17)); row.appendChild(await label(task, 'Thoughts/Card Body'));
    body.appendChild(row);
  }
  body.constraints = { horizontal: 'STRETCH', vertical: 'MIN' };
  return c;
}

async function editorBar() {
  const c = figma.createComponent();
  c.name = 'Editor Bar'; c.layoutMode = 'HORIZONTAL'; c.itemSpacing = 8;
  c.primaryAxisSizingMode = 'AUTO'; c.counterAxisSizingMode = 'AUTO'; c.fills = [];
  for (const [title, sym] of [['Tag', null], ['Spoiler', 'sparkles'], ['Lock', 'lock.fill']]) {
    const b = autoFrame(title, 'HORIZONTAL', { gap: 6, padX: 16, padY: 11 }); b.counterAxisAlignItems = 'CENTER';
    b.appendChild(sym ? await icon(SYMBOLS, sym, 16) : await tagDot());
    const l = await label(title, 'Thoughts/Card Body'); b.appendChild(l);
    c.appendChild(b);
    pinBehind(b, await glass(KIT, SMALL, 'Mode=Dark, Active=False, Prominent=False', b.width, b.height), 0);
  }
  return c;
}

async function markdownToolbar() {
  const c = figma.createComponent();
  c.name = 'Markdown Toolbar'; c.layoutMode = 'HORIZONTAL'; c.itemSpacing = 0;
  c.paddingLeft = c.paddingRight = 10; c.primaryAxisAlignItems = 'SPACE_BETWEEN'; c.counterAxisAlignItems = 'CENTER';
  c.primaryAxisSizingMode = 'FIXED'; c.counterAxisSizingMode = 'FIXED'; c.resize(386, 44); c.fills = [];
  for (const s of ['bold', 'italic', 'strikethrough', 'highlighter', 'textformat.size', 'list.bullet', 'checklist', 'text.quote', 'chevron.left.forwardslash.chevron.right', 'link']) {
    const cell = autoFrame(s, 'HORIZONTAL'); cell.resize(34, 34); cell.primaryAxisSizingMode = 'FIXED'; cell.counterAxisSizingMode = 'FIXED';
    cell.primaryAxisAlignItems = 'CENTER'; cell.counterAxisAlignItems = 'CENTER';
    cell.appendChild(await icon(SYMBOLS, s, 17));
    c.appendChild(cell);
  }
  pinBehind(c, await glass(KIT, MEDIUM, 'Mode=Dark', 386, 44, 22), 0);
  return c;
}

async function tagPicker() {
  const c = figma.createComponent();
  c.name = 'Tag Picker'; c.layoutMode = 'HORIZONTAL'; c.itemSpacing = 14;
  c.paddingLeft = c.paddingRight = 18; c.paddingTop = c.paddingBottom = 12; c.counterAxisAlignItems = 'CENTER';
  c.primaryAxisSizingMode = 'AUTO'; c.counterAxisSizingMode = 'AUTO'; c.fills = [];
  for (const col of ['red', 'orange', 'yellow', 'green', 'blue', 'indigo', 'purple']) {
    const d = figma.createEllipse(); d.resize(28, 28); d.fills = [await boundFill(`tag/${col}`)];
    if (col === 'blue') { d.strokes = [{ type: 'SOLID', color: { r: 1, g: 1, b: 1 } }]; d.strokeWeight = 2.5; d.strokeAlign = 'OUTSIDE'; }
    c.appendChild(d);
  }
  c.appendChild(await icon(SYMBOLS, 'circle.slash', 26, 'card/text-secondary'));
  pinBehind(c, await glass(KIT, MEDIUM, 'Mode=Dark', c.width, c.height, 30), 0);
  return c;
}

async function cardMenu() {
  const c = figma.createComponent();
  c.name = 'Card Menu'; c.layoutMode = 'VERTICAL'; c.paddingTop = c.paddingBottom = 8;
  c.resize(220, 40); c.primaryAxisSizingMode = 'AUTO'; c.counterAxisSizingMode = 'FIXED'; c.fills = [];
  for (const [title, sym, destructive] of [['Copy', 'doc.on.doc'], ['Share', 'square.and.arrow.up'], ['Delete', 'trash', true]]) {
    const row = autoFrame(title, 'HORIZONTAL', { padX: 18, padY: 11 }); row.primaryAxisAlignItems = 'SPACE_BETWEEN'; row.counterAxisAlignItems = 'CENTER';
    c.appendChild(row); row.layoutSizingHorizontal = 'FILL';
    row.appendChild(await label(title, 'Thoughts/Card Body', destructive ? 'tag/red' : 'card/text'));
    row.appendChild(await icon(SYMBOLS, sym, 17, destructive ? 'tag/red' : 'card/text'));
  }
  pinBehind(c, await glass(KIT, MEDIUM, 'Mode=Dark', 220, c.height, 26), 0);
  return c;
}

// ---- Сборка страницы

run(async (log) => {
  const page = pageNamed('iOS — Components');
  await page.loadAsync();
  await figma.setCurrentPageAsync(page);
  if (!REBUILD && findMarked('cmp:card', page)) return 'Компоненты уже есть — не трогаю (REBUILD = true, чтобы пересобрать)';
  if (REBUILD) page.children.filter((n) => n.getPluginData(MARK).startsWith('cmp:')).forEach((n) => n.remove());

  // Доска с градиентом Thoughts: без фона стекло не видно. Компоненты — внутри.
  let bg = findMarked('cmp:bg', page);
  if (bg && REBUILD) { bg.remove(); bg = null; }
  if (!bg) {
    bg = mark(figma.createFrame(), 'cmp:bg'); page.appendChild(bg); bg.name = 'Components — Dark';
    bg.x = 0; bg.y = 0; bg.resize(1400, 960);
    const top = (await boundFill('bg/top')).color, bottom = (await boundFill('bg/bottom')).color;
    bg.fills = [{ type: 'GRADIENT_LINEAR', gradientTransform: [[0, 1, 0], [-1, 0, 1]], gradientStops: [{ position: 0, color: { ...top, a: 1 } }, { position: 1, color: { ...bottom, a: 1 } }] }];
  }

  const place = (node, key, x, y) => { mark(node, key); bg.appendChild(node); node.x = x + 40; node.y = y + 40; return node; };

  // Card — набор вариантов + свойство Tag.
  const kinds = [];
  for (const k of ['Text', 'Long', 'Task', 'Spoiler', 'Lock']) kinds.push(await cardVariant(k));
  const cardSet = figma.combineAsVariants(kinds, page);
  cardSet.name = 'Card'; cardSet.layoutMode = 'VERTICAL'; cardSet.itemSpacing = 16; cardSet.paddingLeft = cardSet.paddingTop = 16;
  cardSet.paddingRight = cardSet.paddingBottom = 16; cardSet.fills = [];
  const tagProp = cardSet.addComponentProperty('Tag', 'BOOLEAN', true);
  for (const variant of cardSet.children) variant.findOne((n) => n.name === 'Tag').componentPropertyReferences = { visible: tagProp };
  cardSet.primaryAxisSizingMode = 'AUTO'; cardSet.counterAxisSizingMode = 'AUTO'; cardSet.clipsContent = false;
  place(cardSet, 'cmp:card', 0, 0);

  const capSet = figma.combineAsVariants([await capsule(false), await capsule(true)], page);
  capSet.name = 'Space Capsule'; capSet.layoutMode = 'HORIZONTAL'; capSet.itemSpacing = 12; capSet.paddingLeft = capSet.paddingTop = capSet.paddingRight = capSet.paddingBottom = 12; capSet.fills = [];
  capSet.primaryAxisSizingMode = 'AUTO'; capSet.counterAxisSizingMode = 'AUTO'; capSet.clipsContent = false;
  place(capSet, 'cmp:capsule', 460, 0);
  place(await spaceDots(), 'cmp:dots', 460, 90);
  place(await circleButton('Settings Button', 'gearshape'), 'cmp:settings', 460, 130);
  place(await circleButton('More Button', 'ellipsis', 36, 16), 'cmp:more', 520, 134);

  const compSet = figma.combineAsVariants([await composer('Empty'), await composer('Typed'), await composer('Long')], page);
  compSet.name = 'Composer'; compSet.layoutMode = 'VERTICAL'; compSet.itemSpacing = 16; compSet.paddingLeft = compSet.paddingTop = compSet.paddingRight = compSet.paddingBottom = 16; compSet.fills = [];
  compSet.primaryAxisSizingMode = 'AUTO'; compSet.counterAxisSizingMode = 'AUTO'; compSet.clipsContent = false;
  place(compSet, 'cmp:composer', 460, 200);

  place(await editorCard(), 'cmp:editor', 900, 0);
  place(await editorBar(), 'cmp:editorbar', 900, 650);
  place(await markdownToolbar(), 'cmp:mdbar', 900, 720);
  place(await tagPicker(), 'cmp:tagpicker', 900, 790);
  place(await cardMenu(), 'cmp:menu', 460, 560);

  await snap(bg, 'components', 1);
  log.push(`Card: ${cardSet.children.length} вариантов; Composer: ${compSet.children.length}`);
  return 'Компоненты собраны';
});
