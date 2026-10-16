// Реорганизация, шаг 2: всё, что было кнопкой, — экземпляры Controls/Button.
// - Composer: «Send» → Accent 32 (Arrow Up); верхний «Send» в 4+ lines / Max — это расширитель → Plain 32 (Expand);
// - экраны: старый набор Buttons (глиф) → Plain 44 с иконкой по глифу (… или Aa);
// - «…» в ленте (библиотечная _Buttons - 44pt) → Glass 44 (Ellipsis).
// Позиция и место в авто-лейауте сохраняются. Старый набор Buttons удаляется, когда экземпляров не осталось.
run(async (log) => {
  await figma.loadAllPagesAsync();
  const comps = pageNamed('iOS — Components');
  const screens = pageNamed('iOS — Screens');
  const button = comps.findOne((n) => n.type === 'COMPONENT_SET' && n.name === 'Controls/Button');
  const icon = (name) => comps.findOne((n) => n.type === 'COMPONENT' && n.name === `Controls/Icon/${name}`);
  const variant = (style, size) => button.children.find((c) => c.name === `Style=${style}, Size=${size}`);
  const iconKey = Object.keys(button.componentPropertyDefinitions).find((k) => k.startsWith('Icon'));
  const aa = icon('Textformat');
  const aaGlyph = aa && aa.findOne((n) => n.type === 'TEXT') ? aa.findOne((n) => n.type === 'TEXT').characters : null;

  // Заменить узел экземпляром кнопки на том же месте.
  const replace = (old, style, size, iconName) => {
    const inst = variant(style, size).createInstance();
    inst.setProperties({ [iconKey]: icon(iconName).id });
    const parent = old.parent;
    const index = parent.children.indexOf(old);
    parent.insertChild(index, inst);
    if (old.layoutPositioning === 'ABSOLUTE' || !('layoutMode' in parent) || parent.layoutMode === 'NONE') {
      if ('layoutMode' in parent && parent.layoutMode !== 'NONE') inst.layoutPositioning = 'ABSOLUTE';
      inst.x = old.x + (old.width - inst.width) / 2; inst.y = old.y + (old.height - inst.height) / 2;
      if ('constraints' in old) inst.constraints = old.constraints;
    }
    inst.name = iconName === 'Arrow Up' ? 'Send' : iconName === 'Expand' ? 'Expand' : iconName === 'Textformat' ? 'Aa' : 'More';
    old.remove();
    return inst;
  };

  // 1) Composer.
  const composer = comps.findOne((n) => n.type === 'COMPONENT_SET' && n.name === 'Feed/Composer');
  let nSend = 0, nExpand = 0;
  for (const v of composer.children) {
    const sends = v.findAll((n) => n.type === 'FRAME' && n.name === 'Send');
    if (!sends.length) continue;
    const column = sends.length === 2 ? sends[0].parent : null; // 4+ lines / Max: колонка [расширитель, отправка]
    for (const s of sends) {
      const isExpand = column && column.children[0] === s;
      replace(s, isExpand ? 'Plain' : 'Accent', 32, isExpand ? 'Expand' : 'Arrow Up');
      isExpand ? nExpand++ : nSend++;
    }
  }
  log.push(`Composer: отправка ×${nSend}, расширитель ×${nExpand}`);

  // 2) Экраны: старый набор Buttons → Plain 44.
  let nOld = 0;
  for (const i of screens.findAll((n) => n.type === 'INSTANCE')) {
    if (i.removed) continue;
    const m = await i.getMainComponentAsync();
    if (!m || !m.parent || m.parent.type !== 'COMPONENT_SET' || m.parent.name !== 'Buttons') continue;
    const glyph = i.findOne((n) => n.type === 'TEXT');
    const isAa = glyph && aaGlyph && glyph.characters === aaGlyph;
    replace(i, 'Plain', 44, isAa ? 'Textformat' : 'Ellipsis');
    nOld++;
  }
  log.push(`экраны: старые Buttons → Button ×${nOld}`);

  // 3) «…» в ленте: библиотечная кнопка → Glass 44.
  let nLib = 0;
  for (const i of screens.findAll((n) => n.type === 'INSTANCE' && n.name === 'Button Group')) {
    if (i.removed) continue;
    const m = await i.getMainComponentAsync();
    if (!m || !m.remote || !/_Buttons - 44pt/.test(m.parent && m.parent.name || '')) continue;
    replace(i, 'Glass', 44, 'Ellipsis');
    nLib++;
  }
  log.push(`экраны: «…» ленты → Button Glass ×${nLib}`);

  // 4) Старый набор Buttons — удалить, если не используется.
  const old = comps.findOne((n) => n.type === 'COMPONENT_SET' && n.name === 'Buttons');
  if (old) {
    const used = (await Promise.all(old.children.map((c) => c.getInstancesAsync()))).flat().length;
    if (!used) { old.remove(); log.push('старый набор Buttons удалён'); } else log.push(`старый Buttons ещё используется ×${used} — оставлен`);
  }

  for (const name of ['S1 · Лента', 'S1 · Длинный ввод (иконка-расширитель)', 'S2 · Карта выделенный текст + кнопка MD']) {
    const f = screens.children.find((x) => x.name === name);
    if (f) await snap(f, `btn-${screens.children.indexOf(f)}`, 1);
  }
  await snap(button, 'btn-set', 2);
  return 'шаг 2 готов';
});
