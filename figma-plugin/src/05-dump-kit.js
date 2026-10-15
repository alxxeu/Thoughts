// Страница «iOS — Kit»: экземпляры элементов библиотеки iOS and iPadOS 27,
// перетащенные из Assets. Шаг создаёт страницу (если нет), делает её текущей
// и записывает ключи компонентов/наборов, варианты, свойства и стили в
// logs/kit.json — дальше шаги берут элементы из библиотеки по ключу.
run(async (log) => {
  const page = pageNamed('iOS — Kit');
  await page.loadAsync();
  await figma.setCurrentPageAsync(page);

  const kit = {};
  const styleInfo = async (id) => {
    if (!id || typeof id !== 'string') return null;
    const st = await figma.getStyleByIdAsync(id);
    return st ? { name: st.name, key: st.key, type: st.type } : null;
  };
  // Только верхний уровень страницы — вложенные части (клавиши и т.п.) не нужны.
  const instances = page.children.filter((n) => n.type === 'INSTANCE');
  for (const inst of instances) {
    const main = await inst.getMainComponentAsync();
    if (!main) continue;
    const set = main.parent && main.parent.type === 'COMPONENT_SET' ? main.parent : null;
    const defs = (set || main).componentPropertyDefinitions || {};
    const entry = {
      component: main.name, key: main.key, remote: main.remote,
      set: set ? set.name : null, setKey: set ? set.key : null,
      variant: inst.variantProperties || null,
      properties: Object.fromEntries(Object.entries(defs).map(([k, d]) => [k, d.type === 'VARIANT' ? d.variantOptions : d.type])),
      size: [Math.round(inst.width), Math.round(inst.height)],
      fillStyle: await styleInfo(inst.fillStyleId),
      effectStyle: await styleInfo(inst.effectStyleId),
    };
    kit[inst.name] = entry;
    log.push(`${inst.name} → ${set ? set.name + ' / ' : ''}${main.name} ${entry.size.join('×')}`);
  }
  // Стили эффектов/заливок библиотеки, встреченные внутри экземпляров (Liquid Glass и т.п.).
  const styles = {};
  for (const inst of instances) {
    for (const n of [inst, ...inst.findAll(() => true)]) {
      for (const id of [n.effectStyleId, n.fillStyleId]) {
        const info = await styleInfo(id);
        if (info) styles[info.name] = info;
      }
    }
  }
  const json = JSON.stringify({ components: kit, styles }, null, 2);
  try { await fetch('http://localhost:8377/file?name=kit.json', { method: 'POST', body: json }); } catch (e) {}
  log.push(`Стилей: ${Object.keys(styles).length}`);
  return `Экземпляров: ${instances.length}`;
});
