// Дамп после ручной доводки: страницы «iOS — Screens» и «iOS — Components».
// Для каждого верхнего фрейма — дерево (2 уровня), тексты и PNG; отдельно —
// всё, что лежит вне наших фреймов (комментарии, новые фреймы). Только чтение.
run(async (log) => {
  const describe = (n, depth, out) => {
    if (depth > 2) return;
    const own = n.getPluginData(MARK) ? ` [${n.getPluginData(MARK)}]` : '';
    const txt = n.type === 'TEXT' ? ` » ${n.characters.replace(/\n/g, ' ⏎ ').slice(0, 120)}` : '';
    const vis = n.visible === false ? ' (скрыт)' : '';
    out.push(`${'  '.repeat(depth)}${n.type} "${n.name}" ${Math.round(n.x)},${Math.round(n.y)} ${Math.round(n.width)}×${Math.round(n.height)}${vis}${own}${txt}`);
    if ('children' in n && n.type !== 'INSTANCE') n.children.forEach((c) => describe(c, depth + 1, out));
  };
  for (const [pageName, prefix] of [['iOS — Screens', 'after-scr'], ['iOS — Components', 'after-cmp']]) {
    const page = pageNamed(pageName);
    await page.loadAsync();
    log.push(`\n######## ${pageName}: ${page.children.length} верхних слоёв`);
    let i = 0;
    for (const top of page.children) {
      const out = [];
      describe(top, 0, out);
      log.push(...out);
      // Все тексты внутри (включая экземпляры) — чтобы видеть правки копирайта и комментарии.
      if ('findAll' in top) {
        const texts = top.findAll((n) => n.type === 'TEXT').map((t) => t.characters.replace(/\n/g, ' ⏎ ').slice(0, 100));
        if (texts.length) log.push(`  тексты: ${[...new Set(texts)].join(' | ')}`);
      }
      if (top.type === 'FRAME' || top.type === 'SECTION' || top.type === 'COMPONENT_SET' || top.type === 'COMPONENT') {
        await snap(top, `${prefix}-${++i}`, 1);
        log.push(`  → ${prefix}-${i}.png`);
      }
    }
  }
  return 'Дамп готов';
});
