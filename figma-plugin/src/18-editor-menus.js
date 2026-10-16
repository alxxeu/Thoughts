// Реорганизация, шаг 3: компоненты Editor и Menus из готовых фреймов, на экранах — экземпляры.
// - Editor/Sheet Header — шапка шторки (Tag + кнопка «…»);
// - Editor/Tag Popover — ряд цветов + Spoiler / Lock (кнопки Controls/Button с подписью);
// - Menus/Card Menu — меню «…» редактора (настроенное библиотечное меню);
// - Menus/More Menu — меню «…» ленты: пока только Settings.
// Плюс: оставшиеся экземпляры старых Buttons → Controls/Button.
const KIT = __JSON_kit.json__;
const SYMBOLS = __JSON_symbols.json__;

run(async (log) => {
  await figma.loadAllPagesAsync();
  const comps = pageNamed('iOS — Components');
  const screens = pageNamed('iOS — Screens');
  const button = comps.findOne((n) => n.type === 'COMPONENT_SET' && n.name === 'Controls/Button');
  const iconC = (name) => comps.findOne((n) => n.type === 'COMPONENT' && n.name === `Controls/Icon/${name}`);
  const bKey = (p) => Object.keys(button.componentPropertyDefinitions).find((k) => k.startsWith(p));
  const makeButton = (style, size, icon, label) => {
    const i = button.children.find((c) => c.name === `Style=${style}, Size=${size}`).createInstance();
    const props = { [bKey('Icon')]: iconC(icon).id };
    if (label) { props[bKey('Label')] = label; props[bKey('Show Label')] = true; }
    i.setProperties(props); i.name = label || icon;
    return i;
  };
  const sameSpot = (old, inst) => {
    const parent = old.parent; parent.insertChild(parent.children.indexOf(old), inst);
    if (old.layoutPositioning === 'ABSOLUTE') inst.layoutPositioning = 'ABSOLUTE';
    if (!('layoutMode' in parent) || parent.layoutMode === 'NONE' || old.layoutPositioning === 'ABSOLUTE') { inst.x = old.x; inst.y = old.y; }
    old.remove();
  };
  const place = { x: 2600, y: 1100 };

  // 0) Остатки старых Buttons где угодно → Plain 44 (…).
  const oldSet = comps.findOne((n) => n.type === 'COMPONENT_SET' && n.name === 'Buttons');
  if (oldSet) {
    for (const v of oldSet.children) for (const i of await v.getInstancesAsync()) {
      const where = []; let q = i.parent; while (q && q.type !== 'PAGE') { where.unshift(q.name); q = q.parent; }
      try { sameSpot(i, makeButton('Plain', 44, 'Ellipsis')); log.push(`Buttons → Button: ${where.join(' › ')}`); }
      catch (e) { log.push(`не заменить (${e.message}): ${where.join(' › ')}`); }
    }
    if (!(await Promise.all(oldSet.children.map((c) => c.getInstancesAsync()))).flat().length) { oldSet.remove(); log.push('старый набор Buttons удалён'); }
  }

  // 1) Editor/Sheet Header — из шапки шторки первого экрана S2.
  let header = comps.findOne((n) => n.type === 'COMPONENT' && n.name === 'Editor/Sheet Header');
  const sheetHeaders = screens.findAll((n) => n.type === 'FRAME' && n.name === 'Toolbar - Top - iPhone' && n.findOne((c) => c.type === 'INSTANCE' && c.name === 'Tags'));
  if (!header && sheetHeaders.length) {
    const src = sheetHeaders[0].clone(); comps.appendChild(src);
    header = figma.createComponentFromNode(src); header.name = 'Editor/Sheet Header';
    header.x = place.x; header.y = place.y;
  }
  let nHeader = 0;
  for (const h of sheetHeaders) { const inst = header.createInstance(); sameSpot(h, inst); inst.name = 'Sheet Header'; nHeader++; }
  log.push(`Sheet Header: экземпляров ${nHeader}`);

  // 2) Editor/Tag Popover — ряд цветов + Spoiler / Lock кнопками.
  let popover = comps.findOne((n) => n.type === 'COMPONENT' && n.name === 'Editor/Tag Popover');
  // Недоделанные клоны от упавших запусков (с нашей капсулой внутри) — убрать.
  comps.children.filter((n) => n.type === 'FRAME' && n.name === 'Frame 12' && n.findOne((c) => c.name === 'Spoiler & Lock')).forEach((n) => n.remove());
  // Черновик поповера — на странице компонентов (где угодно), иначе берём с экрана.
  const compsFrame12 = comps.findOne((n) => n.type === 'FRAME' && n.name === 'Frame 12') || screens.findOne((n) => n.type === 'FRAME' && n.name === 'Frame 12');
  if (!popover && compsFrame12) {
    const src = compsFrame12.clone(); comps.appendChild(src);
    // Библиотечное меню с быстрыми действиями → стеклянная капсула с двумя кнопками.
    const libMenu = src.children.find((n) => n.type === 'INSTANCE' && n.name === 'Menu');
    if (libMenu) {
      const pill = figma.createFrame(); pill.name = 'Spoiler & Lock'; pill.fills = [];
      pill.layoutMode = 'HORIZONTAL'; pill.itemSpacing = 4; pill.paddingLeft = pill.paddingRight = 10; pill.paddingTop = pill.paddingBottom = 6;
      pill.primaryAxisSizingMode = 'AUTO'; pill.counterAxisSizingMode = 'AUTO';
      pill.appendChild(makeButton('Plain', 44, 'Spoiler', 'Spoiler'));
      pill.appendChild(makeButton('Plain', 44, 'Lock', 'Lock'));
      const g = await glass(KIT, 'Liquid Glass - Regular - Medium', 'Mode=Dark', pill.width, pill.height, 28);
      pill.insertChild(0, g); g.layoutPositioning = 'ABSOLUTE'; g.x = 0; g.y = 0; g.resize(pill.width, pill.height);
      g.constraints = { horizontal: 'STRETCH', vertical: 'STRETCH' };
      src.insertChild(src.children.indexOf(libMenu), pill);
      pill.layoutAlign = libMenu.layoutAlign;
      libMenu.remove();
    }
    popover = figma.createComponentFromNode(src); popover.name = 'Editor/Tag Popover';
    popover.x = place.x + 420; popover.y = place.y;
    if (compsFrame12.parent && compsFrame12.parent.type !== 'PAGE' ? false : comps.children.includes(compsFrame12)) compsFrame12.remove(); // черновик со страницы компонентов заменён компонентом
  }
  let nPop = 0;
  for (const f of screens.findAll((n) => n.type === 'FRAME' && n.name === 'Frame 12')) { const inst = popover.createInstance(); sameSpot(f, inst); inst.name = 'Tag Popover'; nPop++; }
  log.push(`Tag Popover: экземпляров ${nPop}`);

  // 3) Menus/Card Menu — настроенное меню «…» с экрана редактора.
  let cardMenu = comps.findOne((n) => n.type === 'COMPONENT' && n.name === 'Menus/Card Menu');
  const menuFrame = screens.children.find((f) => f.name.startsWith('S2 · Меню'));
  const libMenus = [];
  if (menuFrame) for (const i of menuFrame.findAll((n) => n.type === 'INSTANCE' && n.name === 'Menu')) {
    const m = await i.getMainComponentAsync(); if (m && m.remote) libMenus.push(i);
  }
  if (!cardMenu && libMenus.length) {
    cardMenu = figma.createComponent(); cardMenu.name = 'Menus/Card Menu'; cardMenu.fills = []; comps.appendChild(cardMenu);
    const c = libMenus[0].clone(); cardMenu.appendChild(c); c.x = 0; c.y = 0;
    cardMenu.resize(c.width, c.height); cardMenu.clipsContent = false;
    cardMenu.x = place.x; cardMenu.y = place.y + 260;
  }
  for (const i of libMenus) { const inst = cardMenu.createInstance(); sameSpot(i, inst); inst.name = 'Card Menu'; }
  log.push(`Card Menu: экземпляров ${libMenus.length}`);

  // 4) Menus/More Menu — меню «…» ленты: пока только Settings.
  let more = comps.findOne((n) => n.type === 'COMPONENT' && n.name === 'Menus/More Menu');
  if (!more) {
    more = figma.createComponent(); more.name = 'Menus/More Menu'; comps.appendChild(more);
    more.layoutMode = 'VERTICAL'; more.paddingTop = more.paddingBottom = 8;
    more.resize(220, 40); more.primaryAxisSizingMode = 'AUTO'; more.counterAxisSizingMode = 'FIXED'; more.fills = []; more.clipsContent = false;
    const row = autoFrame('Settings', 'HORIZONTAL', { padX: 18, padY: 11 }); row.primaryAxisAlignItems = 'SPACE_BETWEEN'; row.counterAxisAlignItems = 'CENTER';
    more.appendChild(row); row.layoutSizingHorizontal = 'FILL';
    row.appendChild(await label('Settings', 'Thoughts/Card Body'));
    row.appendChild(iconC('Settings').createInstance());
    const g = await glass(KIT, 'Liquid Glass - Regular - Medium', 'Mode=Dark', 220, more.height, 26);
    more.insertChild(0, g); g.layoutPositioning = 'ABSOLUTE'; g.x = 0; g.y = 0; g.resize(more.width, more.height);
    g.constraints = { horizontal: 'STRETCH', vertical: 'STRETCH' };
    more.x = place.x + 420; more.y = place.y + 260;
  }

  for (const name of ['S2 · Выбор тега', 'S2 · Меню «…»', 'S2 · Карта Халф']) {
    const f = screens.children.find((x) => x.name === name);
    if (f) await snap(f, `ed-${name.includes('тега') ? 'tag' : name.includes('Меню') ? 'menu' : 'half'}`, 1);
  }
  await snap(popover, 'ed-popover', 2);
  await snap(more, 'ed-more', 2);
  return 'шаг 3 готов';
});
