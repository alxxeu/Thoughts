// Реорганизация компонентов, шаг 1 (план 2026-10-16):
// - рабочий Card (52:4595, висел вне страниц) — обратно на страницу, Feed/Card,
//   свойство Kind: Text / Long / Spoiler / Lock; старый неиспользуемый набор (52:5008) удаляется;
// - Controls/Tag: Selected=False/True (у 7 цветов — белый кружок по центру), порядок … Blue, Indigo, Purple;
// - имена с категориями: Feed/Composer, Feed/Spaces Bar, Feed/Space Capsule, Editor/Markdown Toolbar;
// - Controls/Icon/… и единая Controls/Button (Style × Size; Icon, Label, Show Label).
// Повторный запуск не дублирует: всё ищется по имени/метке.
const SYMBOLS = __JSON_symbols.json__;
const KIT = __JSON_kit.json__;

run(async (log) => {
  await figma.loadAllPagesAsync();
  const comps = pageNamed('iOS — Components');
  const screens = pageNamed('iOS — Screens');
  const setNamed = (...names) => comps.findOne((n) => n.type === 'COMPONENT_SET' && names.includes(n.name));
  const staging = { x: 2600, y: 0 }; // новые компоненты — правее, раскладка — следующим шагом

  // ---- Card
  const card = await figma.getNodeByIdAsync('52:4595');
  if (card && !card.parent) { comps.appendChild(card); card.x = staging.x; card.y = staging.y; log.push('Card 52:4595 возвращён на страницу'); }
  if (card) {
    const varKey = Object.keys(card.componentPropertyDefinitions).find((k) => card.componentPropertyDefinitions[k].type === 'VARIANT');
    if (varKey !== 'Kind') card.editComponentProperty(varKey, { name: 'Kind' });
    const rename = { Standart: 'Text', Spoiler: 'Spoiler', Lock: 'Lock', Long: 'Long' };
    for (const c of card.children) {
      const v = c.name.split('=')[1];
      if (rename[v]) c.name = `Kind=${rename[v]}`;
    }
    card.name = 'Feed/Card';
    mark(card, 'cmp2:card');
  }
  const oldCard = await figma.getNodeByIdAsync('52:5008');
  if (oldCard && !oldCard.removed) { oldCard.remove(); log.push('старый набор Card (52:5008) удалён'); }

  // ---- Tag
  const tags = setNamed('Tags', 'Controls/Tag');
  if (tags) {
    const COLORS = ['Default', 'Red', 'Orange', 'Yellow', 'Green', 'Blue', 'Indigo', 'Purple', 'Remove'];
    const colorOf = (c) => /Color=([A-Za-z]+)/.exec(c.name)[1];
    for (const c of [...tags.children]) if (!/Selected=/.test(c.name)) c.name = `Color=${colorOf(c)}, Selected=False`;
    for (const col of COLORS.slice(1, 8)) {
      if (tags.children.some((c) => c.name === `Color=${col}, Selected=True`)) continue;
      const base = tags.children.find((c) => c.name === `Color=${col}, Selected=False`);
      const sel = base.clone(); tags.appendChild(sel);
      sel.name = `Color=${col}, Selected=True`;
      const dot = figma.createEllipse(); dot.name = 'Selected'; dot.resize(8, 8);
      dot.fills = [{ type: 'SOLID', color: { r: 1, g: 1, b: 1 } }];
      sel.appendChild(dot);
      if (sel.layoutMode && sel.layoutMode !== 'NONE') dot.layoutPositioning = 'ABSOLUTE';
      dot.x = (sel.width - 8) / 2; dot.y = (sel.height - 8) / 2;
      dot.constraints = { horizontal: 'CENTER', vertical: 'CENTER' };
    }
    // Порядок и сетка: строка — цвет, столбцы — Selected False / True.
    COLORS.forEach((col, row) => {
      for (const [k, sel] of [['False', 0], ['True', 1]]) {
        const c = tags.children.find((x) => x.name === `Color=${col}, Selected=${k}`);
        if (!c) continue;
        tags.appendChild(c); c.x = 20 + sel * 64; c.y = 20 + row * 64;
      }
    });
    tags.resizeWithoutConstraints(20 + 2 * 64, 20 + COLORS.length * 64);
    tags.name = 'Controls/Tag';
    mark(tags, 'cmp2:tag');
    log.push(`Tag: ${tags.children.length} вариантов`);
  }

  // ---- Имена с категориями
  const renames = [
    [['Composer', 'Feed/Composer'], 'Feed/Composer', 'State'],
    [['Spaces', 'Feed/Spaces Bar'], 'Feed/Spaces Bar', 'State'],
    [['Space Capsule', 'Feed/Space Capsule'], 'Feed/Space Capsule', null],
  ];
  for (const [names, to, prop] of renames) {
    const s = setNamed(...names);
    if (!s) { log.push(`нет набора ${names[0]}`); continue; }
    const k = Object.keys(s.componentPropertyDefinitions).find((x) => s.componentPropertyDefinitions[x].type === 'VARIANT');
    if (prop && k !== prop) s.editComponentProperty(k, { name: prop });
    s.name = to;
  }
  const md = comps.findOne((n) => n.type === 'COMPONENT' && (n.name === 'Markdown Toolbar' || n.name === 'Editor/Markdown Toolbar'));
  if (md) md.name = 'Editor/Markdown Toolbar';

  // ---- Иконки: твои глифы SF Pro там, где они уже есть; векторы — где нет.
  const glyphFont = { family: 'SF Pro', style: 'Medium' };
  await figma.loadFontAsync(glyphFont);
  // Глиф кнопки «Aa» в редакторе — берём с экрана (абсолютная кнопка в шторке).
  let aaGlyph = null;
  for (const i of screens.findAll((n) => n.type === 'INSTANCE' && n.name === 'Buttons' && n.layoutPositioning === 'ABSOLUTE')) {
    const t = i.findOne((x) => x.type === 'TEXT'); if (t) { aaGlyph = t.characters; break; }
  }
  const ICONS = [
    ['Ellipsis', { glyph: '􀍠' }],
    ['Textformat', aaGlyph ? { glyph: aaGlyph } : { symbol: 'textformat' }],
    ['Spoiler', { glyph: '􀰙' }],
    ['Lock', { glyph: '􀎡' }],
    ['Copy', { glyph: '􀉁' }],
    ['Share', { glyph: '􀈂' }],
    ['Delete', { glyph: '􀈑' }],
    ['Settings', { symbol: 'gearshape' }],
    ['Arrow Up', { symbol: 'arrow.up' }],
    ['Expand', { symbol: 'arrow.up.left.and.arrow.down.right' }],
  ];
  const icons = {};
  let ix = staging.x;
  for (const [name, src] of ICONS) {
    const full = `Controls/Icon/${name}`;
    let c = comps.findOne((n) => n.type === 'COMPONENT' && n.name === full);
    if (!c) {
      c = figma.createComponent(); c.name = full; comps.appendChild(c);
      c.resize(24, 24); c.fills = [];
      c.layoutMode = 'HORIZONTAL'; c.primaryAxisAlignItems = 'CENTER'; c.counterAxisAlignItems = 'CENTER';
      c.primaryAxisSizingMode = 'FIXED'; c.counterAxisSizingMode = 'FIXED'; c.clipsContent = false;
      if (src.glyph) {
        const t = figma.createText(); t.fontName = glyphFont; t.fontSize = 17; t.characters = src.glyph;
        t.fills = [{ type: 'SOLID', color: { r: 1, g: 1, b: 1 } }]; t.textAlignHorizontal = 'CENTER';
        c.appendChild(t);
      } else {
        const v = await icon(SYMBOLS, src.symbol, 18);
        v.findAll((n) => n.type === 'VECTOR').forEach((n) => { n.fills = [{ type: 'SOLID', color: { r: 1, g: 1, b: 1 } }]; });
        c.appendChild(v);
      }
      c.x = ix; c.y = staging.y + 700; ix += 40;
    }
    icons[name] = c;
  }
  log.push(`иконок: ${Object.keys(icons).length}${aaGlyph ? '' : ' (глиф «Aa» не найден — вектор textformat)'}`);

  // ---- Controls/Button
  let button = setNamed('Controls/Button');
  if (!button) {
    // Акцент — цвет кнопки отправки из твоего Composer.
    let accent = { r: 0.42, g: 0.36, b: 0.96 };
    const send = comps.findOne((n) => n.name === 'Send' && 'fills' in n && Array.isArray(n.fills) && n.fills[0] && n.fills[0].type === 'SOLID');
    if (send) accent = send.fills[0].color;
    const variants = [];
    for (const style of ['Glass', 'Accent', 'Plain']) {
      for (const size of [32, 44]) {
        const b = figma.createComponent();
        b.name = `Style=${style}, Size=${size}`;
        b.layoutMode = 'VERTICAL'; b.itemSpacing = 2;
        b.primaryAxisAlignItems = 'CENTER'; b.counterAxisAlignItems = 'CENTER';
        b.resize(size, size); b.primaryAxisSizingMode = 'AUTO'; b.counterAxisSizingMode = 'AUTO';
        b.minWidth = size; b.minHeight = size; b.fills = []; b.clipsContent = false;
        b.paddingTop = b.paddingBottom = (size - 24) / 2; b.paddingLeft = b.paddingRight = (size - 24) / 2;
        const ic = icons.Ellipsis.createInstance(); ic.name = 'Icon'; b.appendChild(ic);
        const l = figma.createText(); l.name = 'Label'; l.fontName = glyphFont; l.fontSize = 12; l.characters = 'Label';
        l.fills = [{ type: 'SOLID', color: { r: 1, g: 1, b: 1 } }]; b.appendChild(l);
        if (style === 'Glass') {
          const g = await glass(KIT, 'Liquid Glass - Regular - Small', 'Mode=Dark, Active=False, Prominent=False', size, size);
          b.insertChild(0, g); g.layoutPositioning = 'ABSOLUTE'; g.x = 0; g.y = 0; g.resize(b.width, b.height);
          g.constraints = { horizontal: 'STRETCH', vertical: 'STRETCH' };
        } else if (style === 'Accent') {
          b.fills = [{ type: 'SOLID', color: accent }]; b.cornerRadius = size / 2;
        }
        variants.push(b);
      }
    }
    button = figma.combineAsVariants(variants, comps);
    button.name = 'Controls/Button';
    button.layoutMode = 'HORIZONTAL'; button.itemSpacing = 16; button.layoutWrap = 'WRAP';
    button.paddingLeft = button.paddingRight = button.paddingTop = button.paddingBottom = 16;
    button.resize(260, 100); button.primaryAxisSizingMode = 'FIXED'; button.counterAxisSizingMode = 'AUTO';
    button.counterAxisSpacing = 16; button.fills = []; button.clipsContent = false;
    const iconProp = button.addComponentProperty('Icon', 'INSTANCE_SWAP', icons.Ellipsis.id);
    const labelProp = button.addComponentProperty('Label', 'TEXT', 'Label');
    const showProp = button.addComponentProperty('Show Label', 'BOOLEAN', false);
    for (const v of button.children) {
      v.findOne((n) => n.name === 'Icon').componentPropertyReferences = { mainComponent: iconProp };
      v.findOne((n) => n.name === 'Label').componentPropertyReferences = { characters: labelProp, visible: showProp };
    }
    button.x = staging.x; button.y = staging.y + 420;
    mark(button, 'cmp2:button');
    log.push('Controls/Button собран');
  }
  return 'шаг 1 готов';
});
