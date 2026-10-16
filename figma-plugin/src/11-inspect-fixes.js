// Перед точечными правками: где живут точка тега карточки, порядок цветов
// (набор Tags и поповеры), пункт «Label» в меню, длинный текст карточек.
// Только чтение.
run(async (log) => {
  const comps = pageNamed('iOS — Components'); await comps.loadAsync();
  const screens = pageNamed('iOS — Screens'); await screens.loadAsync();
  const fill = (n) => {
    if (!('fills' in n) || !Array.isArray(n.fills) || !n.fills.length) return '';
    const p = n.fills[0];
    const bound = p.boundVariables && p.boundVariables.color ? ` var:${p.boundVariables.color.id}` : '';
    return p.type === 'SOLID' ? ` #${[p.color.r, p.color.g, p.color.b].map((x) => Math.round(x * 255).toString(16).padStart(2, '0')).join('')}${bound}` : ` ${p.type}`;
  };
  const tree = (n, d, max = 3) => {
    if (d > max) return;
    const t = n.type === 'TEXT' ? ` » ${n.characters.slice(0, 50).replace(/\n/g, '⏎')}` : '';
    log.push(`${'  '.repeat(d)}${n.type} "${n.name}" ${n.id} ${Math.round(n.x)},${Math.round(n.y)} ${Math.round(n.width)}×${Math.round(n.height)}${n.visible === false ? ' hidden' : ''}${fill(n)}${t}`);
    if ('children' in n && (n.type !== 'INSTANCE' || d === 0)) n.children.forEach((c) => tree(c, d + 1, max));
  };

  const vars = await figma.variables.getLocalVariablesAsync();
  log.push('# переменные: ' + vars.map((x) => `${x.name}=${x.id}`).join(', '));

  const card = findMarked('cmp:card', comps) || comps.findOne((x) => x.type === 'COMPONENT_SET' && x.name === 'Card');
  log.push('\n# Card'); if (card) tree(card, 0, 3); else log.push('нет cmp:card');
  if (card) log.push('props: ' + JSON.stringify(card.componentPropertyDefinitions));

  for (const name of ['Tags', 'Buttons']) {
    const n = comps.findOne((x) => x.name === name && x.type === 'COMPONENT_SET');
    log.push(`\n# ${name}`); if (n) tree(n, 0, 2);
  }
  for (const n of comps.children.filter((x) => ['Menu', 'Frame 11', 'Frame 12'].includes(x.name))) { log.push(`\n# ${n.name}`); tree(n, 0, 4); }

  // Все тексты «Label» в обеих страницах — где именно.
  for (const page of [comps, screens]) {
    const labels = page.findAll((x) => x.type === 'TEXT' && x.characters === 'Label');
    log.push(`\n# «Label» на ${page.name}: ${labels.length}`);
    for (const t of labels) {
      const path = []; let p = t; while (p && p.type !== 'PAGE') { path.unshift(p.name); p = p.parent; }
      log.push('  ' + path.join(' › '));
    }
  }
  // Ряды цветов: какой вариант Tags в каком порядке.
  const rowsOf = async (root) => {
    const rows = root.findAll((x) => x.type === 'FRAME' && x.name === 'Frame 9');
    for (const r of rows) {
      const names = [];
      for (const i of r.children.filter((c) => c.type === 'INSTANCE')) { const m = await i.getMainComponentAsync(); names.push(m ? m.name.replace('Color=', '') : '?'); }
      const path = []; let p = r; while (p && p.type !== 'PAGE') { path.unshift(p.name); p = p.parent; }
      log.push(`  ${path.join(' › ')}: ${names.join(', ')}`);
    }
  };
  log.push('\n# ряды цветов'); await rowsOf(comps); await rowsOf(screens);
  // Экземпляры карточек на экранах.
  log.push('\n# экземпляры Card на экранах');
  for (const f of screens.children) {
    for (const i of f.findAll((x) => x.type === 'INSTANCE')) {
      const m = await i.getMainComponentAsync();
      if (!m || !m.parent || m.parent.name !== 'Card') continue;
      const t = i.findAll((x) => x.type === 'TEXT').map((x) => x.characters.length);
      const props = Object.fromEntries(Object.entries(i.componentProperties || {}).map(([k, v]) => [k.split('#')[0], v.value]));
      log.push(`  ${f.name} › ${m.name} h${Math.round(i.height)} ${JSON.stringify(props)} text=${t.join('/')}`);
    }
  }
  return 'ok';
});
