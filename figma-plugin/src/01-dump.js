// Дамп файла перед любыми правками: страницы, верхние слои, компоненты,
// переменные, стили, доступные библиотеки переменных.
run(async (log) => {
  for (const page of figma.root.children) {
    log.push(`# ${page.name} (${page.id}) — ${page.children.length} верхних слоёв`);
    for (const n of page.children) {
      log.push(`  ${n.type} "${n.name}" ${n.id} ${Math.round(n.width)}×${Math.round(n.height)} @ ${Math.round(n.x)},${Math.round(n.y)}`
        + (n.getPluginData(MARK) ? ` [${n.getPluginData(MARK)}]` : ''));
    }
  }
  const comps = figma.root.findAllWithCriteria({ types: ['COMPONENT', 'COMPONENT_SET'] });
  log.push(`\nЛокальные компоненты: ${comps.length}`);
  for (const c of comps.slice(0, 40)) log.push(`  ${c.type} "${c.name}" (${c.parent && c.parent.name})`);
  const collections = await figma.variables.getLocalVariableCollectionsAsync();
  log.push(`\nКоллекции переменных: ${collections.map((c) => `${c.name} (${c.variableIds.length})`).join(', ') || 'нет'}`);
  const texts = await figma.getLocalTextStylesAsync();
  log.push(`Текстовые стили: ${texts.length}`);
  try {
    const libs = await figma.teamLibrary.getAvailableLibraryVariableCollectionsAsync();
    log.push(`Библиотеки переменных: ${[...new Set(libs.map((l) => l.libraryName))].join(', ') || 'нет'}`);
  } catch (e) { log.push(`Библиотеки: ${e.message}`); }
  return `Страниц: ${figma.root.children.length}`;
});
