// Дамп страницы «iOS — References»: что автор положил в каждую секцию
// (картинки, тексты-комментарии, фреймы) + PNG секций с содержимым.
run(async (log) => {
  const page = pageNamed('iOS — References');
  await page.loadAsync();
  // Автор мог превратить секцию во фрейм — берём и то, и другое.
  const sections = page.children.filter((n) => n.type === 'SECTION' || n.type === 'FRAME');
  for (const section of sections) {
    const own = section.children.filter((n) => !n.getPluginData(MARK));
    log.push(`\n# ${section.name} — своих слоёв: ${own.length}`);
    for (const n of own) {
      const texts = n.type === 'TEXT' ? [n] : ('findAll' in n ? n.findAll((c) => c.type === 'TEXT') : []);
      log.push(`  ${n.type} "${n.name}" ${n.id} ${Math.round(n.width)}×${Math.round(n.height)} @ ${Math.round(n.x)},${Math.round(n.y)}`);
      for (const t of texts.slice(0, 20)) log.push(`    » ${t.characters.replace(/\n/g, ' ⏎ ')}`);
    }
    if (own.length) await snap(section, `refs-${section.name.split(' ')[0]}`, 0.5);
  }
  // Верхние слои вне секций — тоже могли положить.
  const loose = page.children.filter((n) => !sections.includes(n));
  if (loose.length) {
    log.push(`\n# Вне секций: ${loose.length}`);
    for (const n of loose) log.push(`  ${n.type} "${n.name}" ${n.id}` + (n.type === 'TEXT' ? ` » ${n.characters.replace(/\n/g, ' ⏎ ')}` : ''));
  }
  return `Секций: ${sections.length}`;
});
