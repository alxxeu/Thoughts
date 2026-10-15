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
