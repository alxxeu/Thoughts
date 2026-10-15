// Как устроены материалы и элементы библиотеки (Liquid Glass, Text Field, кнопки):
// дерево слоёв, заливки, эффекты, радиусы, варианты Mode. Только чтение.
run(async (log) => {
  const page = pageNamed('iOS — Kit');
  await page.loadAsync();
  const want = ['Liquid Glass - Regular - Medium', 'Liquid Glass - Clear', 'Liquid Glass - Regular - Small',
    'Text Field', 'Button - Liquid Glass - Symbol', 'Grabber', 'Keyboard', 'Status bar - iPhone 17 Pro', 'Menu'];
  const fmtPaint = (p) => p.type === 'SOLID'
    ? `SOLID ${[p.color.r, p.color.g, p.color.b].map((x) => Math.round(x * 255)).join(',')} a${(p.opacity ?? 1).toFixed(2)}${p.blendMode && p.blendMode !== 'NORMAL' ? ' ' + p.blendMode : ''}`
    : p.type;
  const fmtFx = (e) => `${e.type}${e.radius !== undefined ? ' r' + e.radius : ''}${e.refraction !== undefined ? ' refr' + e.refraction : ''}${e.depth !== undefined ? ' depth' + e.depth : ''}`;
  for (const inst of page.children.filter((n) => n.type === 'INSTANCE' && want.includes(n.name))) {
    const main = await inst.getMainComponentAsync();
    const set = main.parent && main.parent.type === 'COMPONENT_SET' ? main.parent : null;
    log.push(`\n# ${inst.name}  variants: ${set ? set.children.map((c) => c.name).join(' | ') : '—'}`);
    const walk = (n, depth) => {
      if (depth > 3) return;
      const fills = 'fills' in n && Array.isArray(n.fills) ? n.fills.map(fmtPaint).join('; ') : '';
      const fx = 'effects' in n ? n.effects.map(fmtFx).join('; ') : '';
      const rad = 'cornerRadius' in n && typeof n.cornerRadius === 'number' ? ` rad${n.cornerRadius}` : '';
      log.push(`${'  '.repeat(depth)}${n.type} "${n.name}" ${Math.round(n.width)}×${Math.round(n.height)}${rad}${fills ? ' fills[' + fills + ']' : ''}${fx ? ' fx[' + fx + ']' : ''}`);
      if ('children' in n) n.children.slice(0, 8).forEach((c) => walk(c, depth + 1));
    };
    walk(inst, 0);
  }
  return 'ok';
});
