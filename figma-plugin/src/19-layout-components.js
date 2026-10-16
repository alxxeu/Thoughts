// Реорганизация, шаг 4: страница компонентов — секциями по категориям.
// Feed · Editor · Controls · Menus · System · iOS 27 (образцы библиотеки) · Drafts
// (всё остальное, что не используется: старые компоненты и черновики — не удаляются).
// Плюс проверка: шапки шторок на экранах — экземпляры Editor/Sheet Header.
const KIT = __JSON_kit.json__;

run(async (log) => {
  await figma.loadAllPagesAsync();
  const comps = pageNamed('iOS — Components');
  const screens = pageNamed('iOS — Screens');
  const byName = (name) => comps.findOne((n) => (n.type === 'COMPONENT' || n.type === 'COMPONENT_SET') && n.name === name);

  // Шапки шторок: фрейм с тегом и кнопкой «…» (экземпляр тега после переименования набора
  // называется «Controls/Tag»). Если компонента ещё нет — делаем его из первой шапки.
  const isHeader = (n) => n.type === 'FRAME' && n.name === 'Toolbar - Top - iPhone' && n.findOne((c) => c.type === 'INSTANCE' && /Tag/.test(c.name));
  const headerFrames = screens.findAll(isHeader);
  let header = byName('Editor/Sheet Header');
  if (!header && headerFrames.length) {
    const src = headerFrames[0].clone(); comps.appendChild(src);
    header = figma.createComponentFromNode(src); header.name = 'Editor/Sheet Header';
  }
  let fixed = 0;
  if (header) {
    for (const h of headerFrames) {
      const inst = header.createInstance(); const p = h.parent; p.insertChild(p.children.indexOf(h), inst);
      if (!('layoutMode' in p) || p.layoutMode === 'NONE') { inst.x = h.x; inst.y = h.y; }
      inst.name = 'Sheet Header'; h.remove(); fixed++;
    }
  }
  const headerCount = header ? (await header.getInstancesAsync()).length : 0;
  log.push(`Sheet Header: экземпляров ${headerCount}${fixed ? ` (заменено сейчас ${fixed})` : ''}`);

  // Дубли компонентов без экземпляров (от двойного запуска) — убрать.
  for (const name of ['Menus/Card Menu', 'Menus/More Menu', 'Editor/Tag Popover', 'Editor/Sheet Header']) {
    const all = comps.findAll((n) => n.type === 'COMPONENT' && n.name === name);
    if (all.length < 2) continue;
    const counts = await Promise.all(all.map(async (c) => (await c.getInstancesAsync()).length));
    const keep = all[counts.indexOf(Math.max(...counts))];
    all.filter((c) => c !== keep).forEach((c) => c.remove());
    log.push(`${name}: убрано дублей ${all.length - 1}`);
  }

  const fill = async (name) => { const v = (await figma.variables.getLocalVariablesAsync()).find((x) => x.name === name); const c = Object.values(v.valuesByMode)[0]; return { type: 'SOLID', color: { r: c.r, g: c.g, b: c.b } }; };
  const dark = await fill('bg/top');

  const GROUPS = [
    ['Feed', ['Feed/Card', 'Feed/Composer', 'Feed/Spaces Bar', 'Feed/Space Capsule']],
    ['Editor', ['Editor/Sheet Header', 'Editor/Markdown Toolbar', 'Editor/Tag Popover']],
    ['Controls', ['Controls/Button', 'Controls/Tag', ...comps.findAll((n) => n.type === 'COMPONENT' && n.name.startsWith('Controls/Icon/')).map((n) => n.name)]],
    ['Menus', ['Menus/Card Menu', 'Menus/More Menu']],
  ];

  const section = (title) => {
    let s = comps.children.find((n) => n.type === 'SECTION' && n.name === title);
    if (!s) { s = figma.createSection(); s.name = title; comps.appendChild(s); }
    s.fills = [dark];
    return s;
  };
  // Разложить узлы в секции рядами шириной до 2200.
  const flow = (s, nodes) => {
    let x = 60, y = 100, rowH = 0;
    for (const n of nodes) {
      if (x + n.width > 2260 && x > 60) { x = 60; y += rowH + 60; rowH = 0; }
      s.appendChild(n); n.x = x; n.y = y;
      x += n.width + 60; rowH = Math.max(rowH, n.height);
    }
    s.resizeWithoutConstraints(2320, y + rowH + 80);
  };

  const used = new Set();
  let top = 0;
  for (const [title, names] of GROUPS) {
    const nodes = names.map(byName).filter(Boolean);
    nodes.forEach((n) => used.add(n.id));
    const s = section(title);
    flow(s, nodes); s.x = 0; s.y = top; top += s.height + 120;
    log.push(`${title}: ${nodes.map((n) => n.name).join(', ')}`);
  }

  // System · iOS 27 — образцы элементов библиотеки, которые стоят на экранах.
  const sys = section('System · iOS 27');
  if (!sys.children.length) {
    const samples = [
      ['Status bar - iPhone 17 Pro', ''], ['Keyboard', 'Type=Lower Case'], ['Grabber', 'Mode=Dark'],
      ['Liquid Glass - Clear', ''], ['Liquid Glass - Regular - Medium', 'Mode=Dark'],
      ['Liquid Glass - Regular - Small', 'Mode=Dark, Active=False, Prominent=False'],
      ['Menu', 'Mode=Dark'], ['Toolbar - Top - iPhone', ''],
    ];
    const nodes = [];
    for (const [name, v] of samples) { try { nodes.push(await libInstance(KIT, name, v)); } catch (e) { log.push(`нет образца ${name}: ${e.message}`); } }
    flow(sys, nodes);
  }
  sys.x = 0; sys.y = top; top += sys.height + 120;

  // Drafts — всё прочее на странице (старые компоненты, черновики): не удаляем, убираем вниз.
  const drafts = section('Drafts');
  const rest = comps.children.filter((n) => n.type !== 'SECTION' && !used.has(n.id));
  if (rest.length) flow(drafts, [...drafts.children, ...rest]);
  drafts.x = 0; drafts.y = top;
  log.push(`Drafts: ${drafts.children.map((n) => n.name).join(', ')}`);

  // Снимки секций и всех экранов — убедиться, что ничего не съехало.
  for (const s of comps.children.filter((n) => n.type === 'SECTION')) await snap(s, `sec-${s.name.split(' ')[0]}`, 0.5);
  let i = 0;
  for (const f of screens.children) await snap(f, `final-${++i}`, 0.5);
  return 'страница разложена';
});
