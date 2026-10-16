// Точечные правки после ручной доводки (решения Р19–Р22):
// 1) точка тега в карточке — слева сверху, свойство «Tag» (как было, но слева);
// 2) порядок цветов: … Blue, Indigo, Purple (как CardTagColor);
// 3) «Label» → «Share» в меню «…» редактора;
// 4) мягкое затухание длинного превью, как на Mac: вариант Long — до 10 строк,
//    последние ~15 pt текста гаснут; длинные карточки на экранах → Long.
// Повторный запуск ничего не дублирует. Остальные слои не трогает.
run(async (log) => {
  const comps = pageNamed('iOS — Components'); await comps.loadAsync();
  const screens = pageNamed('iOS — Screens'); await screens.loadAsync();

  // Набор Card, которым пользуются экраны.
  let cardSet = null;
  for (const i of screens.findAll((x) => x.type === 'INSTANCE')) {
    const m = await i.getMainComponentAsync();
    if (m && m.parent && m.parent.type === 'COMPONENT_SET' && m.parent.name === 'Card') { cardSet = m.parent; break; }
  }
  if (!cardSet) throw new Error('не нашёл набор Card, используемый экранами');
  const where = []; let p = cardSet; while (p && p.type !== 'PAGE') { where.unshift(p.name); p = p.parent; }
  log.push(`Card: ${where.join(' › ')} (${cardSet.id}); варианты: ${cardSet.children.map((c) => c.name).join(', ')}`);
  const variantKey = Object.keys(cardSet.componentPropertyDefinitions).find((k) => cardSet.componentPropertyDefinitions[k].type === 'VARIANT');

  // 4) Вариант Long — клон Standart: имена слоёв те же, тексты экземпляров сохранятся.
  const standart = cardSet.children.find((c) => /Standart/.test(c.name));
  let long = cardSet.children.find((c) => /=Long$/.test(c.name));
  if (!long) {
    long = standart.clone();
    cardSet.appendChild(long);
    long.name = `${variantKey}=Long`;
    log.push('создан вариант Long');
  }
  const LINE = 20, MAX_LINES = 10, FADE = 15;
  const text = long.findOne((n) => n.type === 'TEXT');
  await figma.loadFontAsync(text.fontName);
  text.textAutoResize = 'NONE';
  text.resize(text.width, LINE * MAX_LINES);
  const base = text.fills[0] && text.fills[0].type === 'SOLID' ? text.fills[0] : { color: { r: 1, g: 1, b: 1 }, opacity: 0.88 };
  const a = base.opacity ?? 0.88;
  text.fills = [{ type: 'GRADIENT_LINEAR', gradientTransform: [[0, 1, 0], [-1, 0, 1]],
    gradientStops: [{ position: 0, color: { ...base.color, a } }, { position: 1 - FADE / (LINE * MAX_LINES), color: { ...base.color, a } }, { position: 1, color: { ...base.color, a: 0 } }] }];
  long.clipsContent = true;
  // Вариант Long — под остальными вариантами набора, не поверх.
  const others = cardSet.children.filter((c) => c !== long);
  long.x = Math.min(...others.map((c) => c.x));
  long.y = Math.max(...others.map((c) => c.y + c.height)) + 20;
  if (cardSet.layoutMode === 'NONE' || !cardSet.layoutMode) cardSet.resizeWithoutConstraints(cardSet.width, Math.max(cardSet.height, long.y + long.height + 20));

  // 1) Точка тега слева сверху во всех вариантах + булево свойство Tag (по умолчанию выкл).
  let tagProp = Object.keys(cardSet.componentPropertyDefinitions).find((k) => k.startsWith('Tag'));
  if (!tagProp) tagProp = cardSet.addComponentProperty('Tag', 'BOOLEAN', false);
  const blue = (await figma.variables.getLocalVariablesAsync()).find((x) => x.name === 'tag/blue');
  for (const variant of cardSet.children) {
    let dot = variant.findOne((n) => n.name === 'Tag' && n.type === 'ELLIPSE');
    if (!dot) {
      dot = figma.createEllipse(); dot.name = 'Tag';
      const val = Object.values(blue.valuesByMode)[0];
      dot.fills = [figma.variables.setBoundVariableForPaint({ type: 'SOLID', color: { r: val.r, g: val.g, b: val.b } }, 'color', blue)];
      variant.appendChild(dot);
      if (variant.layoutMode && variant.layoutMode !== 'NONE') dot.layoutPositioning = 'ABSOLUTE';
    }
    // В углу, в отступе карточки: 8 pt, до текста (отступ 20) остаётся 4 pt.
    dot.resize(8, 8); dot.x = 8; dot.y = 8; dot.constraints = { horizontal: 'MIN', vertical: 'MIN' };
    dot.componentPropertyReferences = { visible: tagProp };
  }
  log.push(`точка тега слева: ${cardSet.children.length} вариантов`);

  // Длинные карточки на экранах → Long, с тегом (как было на ленте).
  let switched = 0;
  for (const i of screens.findAll((x) => x.type === 'INSTANCE')) {
    const m = await i.getMainComponentAsync();
    if (!m || m.parent !== cardSet || !/Standart|Long/.test(m.name)) continue;
    const t = i.findOne((n) => n.type === 'TEXT');
    if (!t || t.characters.length < 200) continue;
    i.setProperties({ [variantKey]: 'Long', [tagProp]: true });
    switched++;
  }
  log.push(`длинных карточек → Long + тег: ${switched}`);

  // 2) Порядок цветов: 7-й — Indigo, 8-й — Purple.
  let rows = 0;
  for (const page of [comps, screens]) {
    for (const row of page.findAll((x) => x.type === 'FRAME' && x.name === 'Frame 9')) {
      const items = row.children.filter((c) => c.type === 'INSTANCE');
      if (items.length !== 8) continue;
      const names = [];
      for (const it of items) { const m = await it.getMainComponentAsync(); names.push(m ? m.name : ''); }
      if (!names.every((n) => n.startsWith('Color='))) continue;
      const key = Object.keys(items[6].componentProperties).find((k) => k.startsWith('Color'));
      items[6].setProperties({ [key]: 'Indigo' });
      items[7].setProperties({ [key]: 'Purple' });
      rows++;
    }
  }
  log.push(`рядов цветов исправлено: ${rows}`);

  // 3) «Label» → «Share» в меню «…» редактора.
  const menuFrame = screens.children.find((f) => f.name.startsWith('S2 · Меню'));
  let renamed = 0;
  if (menuFrame) {
    for (const t of menuFrame.findAll((x) => x.type === 'TEXT' && x.characters === 'Label' && x.visible)) {
      let visible = true; let q = t; while (q && q !== menuFrame) { if (q.visible === false) visible = false; q = q.parent; }
      if (!visible) continue;
      await figma.loadFontAsync(t.fontName);
      t.characters = 'Share';
      renamed++;
    }
  }
  log.push(`«Label» → «Share»: ${renamed}`);

  // Снимки для проверки.
  for (const name of ['S1 · Лента', 'S2 · Выбор тега', 'S2 · Меню «…»']) {
    const f = screens.children.find((x) => x.name === name);
    if (f) await snap(f, `fix-${name.split(' · ')[0]}-${name.includes('тега') ? 'tag' : name.includes('Меню') ? 'menu' : 'feed'}`, 1);
  }
  await snap(cardSet, 'fix-card-set', 1);
  return 'Правки сделаны';
});
