// Общая обвязка, подставляется build.sh перед каждым шагом.
// done(text) — показывает итог в окне плагина и отправляет его в logs/ через локальный сервер.
const STEP = '__STEP__';
async function done(text, ok = true) {
  const body = `${ok ? '✅' : '❌'} ${STEP}\n${text}`;
  const esc = body.replace(/&/g, '&amp;').replace(/</g, '&lt;');
  figma.showUI(`<pre style="font:11px monospace;margin:6px;white-space:pre-wrap;color:${ok ? '#000' : 'red'}">${esc}</pre>`,
    { width: 360, height: 160, position: { x: 0, y: 0 } });
  try { await fetch('http://localhost:8377/log?step=' + encodeURIComponent(STEP), { method: 'POST', body }); } catch (e) {}
}
// Обёртка шага: run(async (log) => { ...; return 'итог' })
function run(fn) {
  const log = [];
  (async () => { await figma.loadAllPagesAsync(); const r = await fn(log); await done([...log, r || ''].join('\n')); })()
    .catch((e) => done(`${e.message}\n${e.stack || ''}\n${log.join('\n')}`, false));
}
// snap(node, name) — экспорт PNG узла в logs/<name>.png для проверки результата
async function snap(node, name, scale = 2) {
  const bytes = await node.exportAsync({ format: 'PNG', constraint: { type: 'SCALE', value: scale } });
  try { await fetch('http://localhost:8377/file?name=' + encodeURIComponent(name + '.png'), { method: 'POST', body: bytes }); } catch (e) {}
}

// ---- Thoughts: свои слои помечаются, повторный запуск находит их, а не плодит копии.
const MARK = 'thoughts';
const mark = (node, key) => { node.setPluginData(MARK, key); return node; };
const findMarked = (key, scope = figma.root) => scope.findAll((n) => n.getPluginData(MARK) === key)[0] || null;

// Страница по имени (создаётся, если её нет).
function pageNamed(name) {
  return figma.root.children.find((p) => p.name === name) || Object.assign(figma.createPage(), { name });
}

// ---- Сборка iOS-экранов на библиотеке iOS and iPadOS 27.
// Шаг объявляет KIT и SYMBOLS из assets/kit.json и assets/symbols.json (плейсхолдер __JSON_<файл>__).

// Экземпляр элемента библиотеки по имени в kit.json; variant — 'Mode=Dark' и т.п.
async function libInstance(KIT, name, variant = '') {
  const e = KIT.components[name];
  if (!e) throw new Error(`нет в kit.json: ${name}`);
  let comp;
  if (e.setKey) {
    const set = await figma.importComponentSetByKeyAsync(e.setKey);
    const want = variant.split(',').map((s) => s.trim()).filter(Boolean);
    const base = e.variant || {};
    comp = set.children.find((c) => {
      const props = c.variantProperties || {};
      return want.every((w) => { const [k, v] = w.split('='); return props[k] === v; })
        && Object.entries(base).every(([k, v]) => want.some((w) => w.startsWith(k + '=')) || props[k] === v);
    }) || set.children.find((c) => want.every((w) => { const [k, v] = w.split('='); return (c.variantProperties || {})[k] === v; }));
    if (!comp) throw new Error(`нет варианта ${variant} у ${name}`);
  } else {
    comp = await figma.importComponentByKeyAsync(e.key);
  }
  return comp.createInstance();
}

// Стекло: материал библиотеки, растянутый на размер, со своим скруглением.
async function glass(KIT, name, variant, w, h, radius) {
  const g = await libInstance(KIT, name, variant);
  g.resize(w, h);
  if (radius !== undefined) g.findAll((n) => 'cornerRadius' in n && (n.name === 'Fill + Shadow' || n.name === 'Glass Effect')).forEach((n) => { n.cornerRadius = radius; });
  g.name = 'Glass';
  return g;
}

// Переменные «Thoughts» по имени.
let _vars = null;
async function v(name) {
  if (!_vars) _vars = await figma.variables.getLocalVariablesAsync();
  const found = _vars.find((x) => x.name === name);
  if (!found) throw new Error(`нет переменной ${name}`);
  return found;
}
// Заливка, привязанная к переменной (сначала вычисленный цвет — figma-api-gotchas).
async function boundFill(name) {
  const variable = await v(name);
  const val = Object.values(variable.valuesByMode)[0];
  const paint = { type: 'SOLID', color: { r: val.r, g: val.g, b: val.b }, opacity: val.a ?? 1 };
  return figma.variables.setBoundVariableForPaint(paint, 'color', variable);
}

// Текст со стилем «Thoughts/…» и цветом из переменной.
async function label(chars, styleName, fillVar = 'card/text') {
  const styles = await figma.getLocalTextStylesAsync();
  const st = styles.find((s) => s.name === styleName);
  await figma.loadFontAsync(st.fontName);
  const t = figma.createText();
  await t.setTextStyleIdAsync(st.id);
  t.characters = chars;
  t.fills = [await boundFill(fillVar)];
  return t;
}

// Иконка SF Symbol вектором, вписанная в квадрат size. Путь из sym2svg в этом
// плагине выходит перевёрнутым — переворачиваем по вертикали в SVG.
async function icon(SYMBOLS, name, size, fillVar = 'card/text') {
  const s = SYMBOLS[name];
  if (!s) throw new Error(`нет символа ${name}`);
  const node = figma.createNodeFromSvg(`<svg xmlns="http://www.w3.org/2000/svg" width="${s.w}" height="${s.h}" viewBox="0 0 ${s.w} ${s.h}"><path transform="matrix(1 0 0 -1 0 ${s.h})" d="${s.d}" fill="#FFFFFF"/></svg>`);
  const k = size / Math.max(s.w, s.h);
  node.resize(s.w * k, s.h * k);
  const paint = await boundFill(fillVar);
  node.findAll((n) => n.type === 'VECTOR').forEach((n) => { n.fills = [paint]; n.strokes = []; });
  node.name = name;
  return node;
}

// Авто-лейаут фрейм без заливки.
function autoFrame(name, dir = 'VERTICAL', { gap = 0, pad = 0, padX, padY } = {}) {
  const f = figma.createFrame();
  f.name = name; f.layoutMode = dir; f.itemSpacing = gap;
  f.paddingLeft = f.paddingRight = padX ?? pad; f.paddingTop = f.paddingBottom = padY ?? pad;
  f.primaryAxisSizingMode = 'AUTO'; f.counterAxisSizingMode = 'AUTO';
  f.fills = [];
  return f;
}

// Слой поверх/под содержимым авто-лейаута, растянутый на весь фрейм.
function pinBehind(parent, node, index = 0) {
  parent.insertChild(index, node);
  node.layoutPositioning = 'ABSOLUTE';
  node.x = 0; node.y = 0; node.resize(parent.width, parent.height);
  node.constraints = { horizontal: 'STRETCH', vertical: 'STRETCH' };
}
