// Устройство того, что будем пересобирать: набор Buttons, Composer, Spaces,
// где живёт рабочий Card, шторка редактора на экране. Только чтение.
run(async (log) => {
  await figma.loadAllPagesAsync();
  const comps = pageNamed('iOS — Components');
  const screens = pageNamed('iOS — Screens');
  const where = (n) => { const p = []; let q = n.parent; while (q && q.type !== 'DOCUMENT') { p.unshift(q.name); q = q.parent; } return p.join(' › '); };
  const tree = async (n, d, max) => {
    if (d > max) return;
    let extra = '';
    if (n.type === 'INSTANCE') { const m = await n.getMainComponentAsync(); extra = m ? ` ⇢ ${m.parent && m.parent.type === 'COMPONENT_SET' ? m.parent.name + ' / ' : ''}${m.name}${m.remote ? ' [lib]' : ''}` : ''; }
    const t = n.type === 'TEXT' ? ` » ${n.characters.slice(0, 40).replace(/\n/g, '⏎')} (${n.fontName.family} ${n.fontName.style} ${n.fontSize})` : '';
    const al = 'layoutMode' in n && n.layoutMode !== 'NONE' ? ` AL:${n.layoutMode}` : '';
    const abs = 'layoutPositioning' in n && n.layoutPositioning === 'ABSOLUTE' ? ' abs' : '';
    log.push(`${'  '.repeat(d)}${n.type} "${n.name}" ${n.id} ${Math.round(n.x)},${Math.round(n.y)} ${Math.round(n.width)}×${Math.round(n.height)}${al}${abs}${n.visible === false ? ' hidden' : ''}${extra}${t}`);
    if ('children' in n && n.type !== 'INSTANCE') for (const c of n.children) await tree(c, d + 1, max);
  };

  // Рабочий Card — через экземпляр на экране.
  for (const i of screens.findAll((x) => x.type === 'INSTANCE')) {
    const m = await i.getMainComponentAsync();
    if (m && m.parent && m.parent.name === 'Card') { log.push(`# рабочий Card: ${m.parent.id} — ${where(m.parent)}`); break; }
  }
  for (const name of ['Buttons', 'Composer', 'Spaces', 'Space Capsule', 'Tags']) {
    const s = comps.findOne((x) => x.type === 'COMPONENT_SET' && x.name === name);
    log.push(`\n# ${name} — ${s ? where(s) : 'нет'}`);
    if (s) await tree(s, 0, name === 'Tags' ? 2 : 4);
  }
  for (const fname of ['S2 · Карта Халф', 'S2 · Выбор тега', 'S1 · Длинный ввод (иконка-расширитель)', 'S2 · Карта выделенный текст + кнопка MD']) {
    const f = screens.children.find((x) => x.name === fname);
    log.push(`\n# ${fname}`);
    if (f) await tree(f, 0, 5);
  }
  return 'ok';
});
