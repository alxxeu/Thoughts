// Foundations: локальная коллекция переменных «Thoughts» (режимы Dark / Light)
// и текстовые стили карточки. Значения — из кода Mac (docs/ios/DESIGN-SYSTEM.md).
// Повторный запуск обновляет значения, не создаёт копий.

const rgba = (h, a = 1) => ({ r: parseInt(h.slice(1, 3), 16) / 255, g: parseInt(h.slice(3, 5), 16) / 255, b: parseInt(h.slice(5, 7), 16) / 255, a });

// [имя, тип, Dark, Light]
const VARS = [
  // Цвета тегов — системные цвета iOS (тёмная / светлая версии).
  ['tag/red', 'COLOR', rgba('#FF453A'), rgba('#FF3B30')],
  ['tag/orange', 'COLOR', rgba('#FF9F0A'), rgba('#FF9500')],
  ['tag/yellow', 'COLOR', rgba('#FFD60A'), rgba('#FFCC00')],
  ['tag/green', 'COLOR', rgba('#30D158'), rgba('#34C759')],
  ['tag/blue', 'COLOR', rgba('#0A84FF'), rgba('#007AFF')],
  ['tag/indigo', 'COLOR', rgba('#5E5CE6'), rgba('#5856D6')],
  ['tag/purple', 'COLOR', rgba('#BF5AF2'), rgba('#AF52DE')],
  // Карточка: текст белый 88 % (CardTypography.defaultTextColor); светлая — уточним вторым проходом.
  ['card/text', 'COLOR', rgba('#FFFFFF', 0.88), rgba('#1C1C1E', 0.88)],
  ['card/text-secondary', 'COLOR', rgba('#FFFFFF', 0.55), rgba('#1C1C1E', 0.5)],
  ['card/tint', 'COLOR', rgba('#000000', 0.05), rgba('#000000', 0.2)],
  ['card/privacy-tint', 'COLOR', rgba('#000000', 0.2), rgba('#000000', 0.2)],
  ['card/star', 'COLOR', rgba('#FFFFFF', 0.7), rgba('#FFFFFF', 0.8)],
  ['markdown/highlight', 'COLOR', rgba('#FFD60A', 0.35), rgba('#FFCC00', 0.35)],
  ['markdown/code', 'COLOR', rgba('#FF9F0A', 0.9), rgba('#C93400', 0.9)],
  // Фон под стеклом — мягкий градиент Thoughts.
  ['bg/top', 'COLOR', rgba('#191B2E'), rgba('#E9ECF7')],
  ['bg/bottom', 'COLOR', rgba('#2A1D33'), rgba('#F5ECF2')],
  // Размеры.
  ['radius/card', 'FLOAT', 16, 16],
  ['radius/sheet', 'FLOAT', 28, 28],
  ['radius/capsule', 'FLOAT', 18, 18],
  ['space/margin', 'FLOAT', 16, 16],
  ['space/card-padding', 'FLOAT', 16, 16],
  ['space/feed-gap', 'FLOAT', 10, 10],
  ['type/body', 'FLOAT', 15, 15],
];

async function font(family, style, fallback) {
  try { await figma.loadFontAsync({ family, style }); return { family, style }; } catch (e) {
    await figma.loadFontAsync(fallback); return fallback;
  }
}

run(async (log) => {
  const collections = await figma.variables.getLocalVariableCollectionsAsync();
  let col = collections.find((c) => c.name === 'Thoughts');
  if (!col) col = figma.variables.createVariableCollection('Thoughts');
  // Бесплатный план Figma — один режим на коллекцию: пока только Dark.
  // shortcut: светлые значения (4-я колонка VARS) ждут прохода светлой темы — тогда
  // либо платный план и режим Light, либо отдельная коллекция «Thoughts Light».
  col.renameMode(col.modes[0].modeId, 'Dark');
  const dark = col.modes[0].modeId;

  const existing = await figma.variables.getLocalVariablesAsync();
  for (const [name, type, d, l] of VARS) {
    let v = existing.find((x) => x.name === name && x.variableCollectionId === col.id);
    if (!v) v = figma.variables.createVariable(name, col, type);
    v.setValueForMode(dark, d);
  }
  log.push(`Переменных: ${VARS.length} в «Thoughts» (Dark)`);

  // Текстовые стили карточки.
  const regular = await font('SF Pro', 'Regular', { family: 'Inter', style: 'Regular' });
  const semibold = await font('SF Pro', 'Semibold', { family: 'Inter', style: 'Semi Bold' });
  const mono = await font('SF Mono', 'Regular', { family: 'Roboto Mono', style: 'Regular' });
  const STYLES = [
    ['Thoughts/Card Body', regular, 15, 20],
    ['Thoughts/Card Body S', regular, 13, 18],
    ['Thoughts/Card Body L', regular, 18, 24],
    ['Thoughts/Card Body XL', regular, 22, 28],
    ['Thoughts/Card Heading', semibold, 17, 22],
    ['Thoughts/Card Code', mono, 14, 20],
  ];
  const textStyles = await figma.getLocalTextStylesAsync();
  for (const [name, fontName, size, lh] of STYLES) {
    const st = textStyles.find((s) => s.name === name) || figma.createTextStyle();
    st.name = name; st.fontName = fontName; st.fontSize = size;
    st.lineHeight = { value: lh, unit: 'PIXELS' };
  }
  log.push(`Текстовых стилей: ${STYLES.length}; шрифты: ${regular.family}, ${mono.family}`);

  // Что даёт библиотека: коллекции переменных (для тёмного режима её компонентов).
  try {
    const libs = await figma.teamLibrary.getAvailableLibraryVariableCollectionsAsync();
    for (const c of libs) log.push(`Библиотека: ${c.libraryName} / ${c.name} (${c.key})`);
    if (!libs.length) log.push('Коллекций переменных в библиотеках нет');
  } catch (e) { log.push(`teamLibrary: ${e.message}`); }
  return 'Foundations готовы';
});
