// Где рабочий набор Card (52:4595) и чем он отличается от набора на странице (52:5008).
run(async (log) => {
  for (const id of ['52:4595', '52:5008']) {
    const n = await figma.getNodeByIdAsync(id);
    if (!n) { log.push(`${id}: не найден`); continue; }
    const p = []; let q = n.parent; while (q) { p.unshift(`${q.type}:${q.name}`); q = q.parent; }
    log.push(`${id} "${n.name}" removed=${n.removed} parent=${p.join(' › ') || '—'}`);
    if ('children' in n) for (const c of n.children) {
      const t = c.findAll((x) => x.type === 'TEXT').map((x) => `"${x.name.slice(0, 30)}"`);
      log.push(`  ${c.name}: ${c.children.map((x) => x.name).join(', ')} | тексты: ${t.join(', ')}`);
    }
  }
  return 'ok';
});
