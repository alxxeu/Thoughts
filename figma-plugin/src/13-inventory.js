// Инвентаризация перед раскладкой компонентов: все локальные компоненты и
// наборы (где лежат, варианты, свойства) и что из них (и из библиотеки)
// реально стоит на экранах. Только чтение.
run(async (log) => {
  await figma.loadAllPagesAsync();
  const path = (n) => { const p = []; let q = n.parent; while (q && q.type !== 'DOCUMENT') { p.unshift(q.name); q = q.parent; } return p.join(' › '); };

  log.push('# Локальные компоненты и наборы');
  const sets = figma.root.findAllWithCriteria({ types: ['COMPONENT_SET'] });
  for (const s of sets) {
    const defs = Object.entries(s.componentPropertyDefinitions).map(([k, d]) => `${k.split('#')[0]}:${d.type}${d.variantOptions ? '[' + d.variantOptions.join('/') + ']' : ''}`);
    log.push(`SET "${s.name}" ${s.id} — ${path(s)} — ${Math.round(s.width)}×${Math.round(s.height)} — ${defs.join(', ')}`);
  }
  const singles = figma.root.findAllWithCriteria({ types: ['COMPONENT'] }).filter((c) => !c.parent || c.parent.type !== 'COMPONENT_SET');
  for (const c of singles) {
    const defs = Object.entries(c.componentPropertyDefinitions).map(([k, d]) => `${k.split('#')[0]}:${d.type}`);
    log.push(`COMP "${c.name}" ${c.id} — ${path(c)} — ${Math.round(c.width)}×${Math.round(c.height)}${defs.length ? ' — ' + defs.join(', ') : ''}`);
  }

  // Что стоит на экранах: верхние экземпляры (не вложенные в другие экземпляры).
  const screens = pageNamed('iOS — Screens');
  const usage = new Map();
  for (const frame of screens.children) {
    const tops = frame.findAll((n) => {
      if (n.type !== 'INSTANCE') return false;
      let q = n.parent; while (q && q !== frame) { if (q.type === 'INSTANCE') return false; q = q.parent; } return true;
    });
    for (const i of tops) {
      const m = await i.getMainComponentAsync();
      if (!m) continue;
      const set = m.parent && m.parent.type === 'COMPONENT_SET' ? m.parent : null;
      const key = `${m.remote ? 'LIB' : 'LOCAL'} ${set ? set.name + ' / ' : ''}${set ? m.name : m.name}`;
      const u = usage.get(key) || { n: 0, frames: new Set() };
      u.n++; u.frames.add(frame.name); usage.set(key, u);
    }
  }
  log.push('\n# Экземпляры на экранах (верхний уровень)');
  [...usage.entries()].sort().forEach(([k, u]) => log.push(`${k} ×${u.n} — ${[...u.frames].length} экр.`));

  // Не-компонентные «кнопки» на экранах: фреймы с именами, похожими на кнопки.
  log.push('\n# Фреймы-не-компоненты на экранах (возможные кнопки/элементы)');
  const loose = new Map();
  for (const frame of screens.children) {
    for (const n of frame.findAll((x) => (x.type === 'FRAME' || x.type === 'GROUP') && /button|btn|кноп|Aa|More|Settings|Send|Expand|Spaces|Composer|Menu|Frame \d+/i.test(x.name))) {
      let inInst = false; let q = n.parent; while (q && q !== frame) { if (q.type === 'INSTANCE') inInst = true; q = q.parent; }
      if (inInst) continue;
      const k = `${n.type} "${n.name}" ${Math.round(n.width)}×${Math.round(n.height)}`;
      loose.set(k, (loose.get(k) || 0) + 1);
    }
  }
  [...loose.entries()].forEach(([k, c]) => log.push(`${k} ×${c}`));
  return `наборов ${sets.length}, одиночных ${singles.length}`;
});
