// Убрать случайный экземпляр Card Menu из Drafts; проверить, где черновики Menu / Frame 11.
run(async (log) => {
  const comps = pageNamed('iOS — Components'); await comps.loadAsync();
  const stray = await figma.getNodeByIdAsync('92:20673');
  if (stray && !stray.removed && stray.type === 'INSTANCE' && stray.parent && stray.parent.name === 'Drafts') { stray.remove(); log.push('случайный экземпляр Card Menu убран'); }
  for (const id of ['77:15266', '77:15277', '77:15294', '50:9388']) {
    const n = await figma.getNodeByIdAsync(id);
    log.push(`${id}: ${n ? `${n.type} "${n.name}" removed=${n.removed} parent=${n.parent ? n.parent.name : '—'}` : 'нет'}`);
  }
  return 'ok';
});
