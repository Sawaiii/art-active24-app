// Генерирует ресурсы iOS-приложения из research/brand/assets:
//  - шрифты Golos Text и Inter (статические TTF 400/500/600/700, те же OFL-семейства,
//    что сайт отдаёт woff2-сабсетами; полные TTF нужны, т.к. сабсеты нельзя
//    зарегистрировать в iOS под одним PostScript-именем);
//  - иконки таб-бара/шапки → imageset (SVG, preserves-vector-representation, template);
//  - логотипы → imageset (SVG, цвет оригинала);
//  - AppIcon 1024×1024 из favicon.svg (без альфа-канала).
// Запуск: node build-assets.mjs   (из ios/tools; нужен @resvg/resvg-js и доступ к fonts.gstatic.com)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Resvg } from '@resvg/resvg-js';

const here = path.dirname(fileURLToPath(import.meta.url));
const iosRoot = path.resolve(here, '..');
const brand = path.resolve(iosRoot, '..', 'research', 'brand', 'assets');
const res = path.join(iosRoot, 'ArtActive', 'Resources');
const xcassets = path.join(res, 'Assets.xcassets');
const fontsDir = path.join(res, 'Fonts');

const info = { author: 'xcode', version: 1 };
const writeJson = (p, obj) => { fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, JSON.stringify(obj, null, 2) + '\n'); };

function imageset(name, svg, { template }) {
  const dir = path.join(xcassets, `${name}.imageset`);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, `${name}.svg`), svg);
  const props = { 'preserves-vector-representation': true };
  if (template) props['template-rendering-intent'] = 'template';
  writeJson(path.join(dir, 'Contents.json'), {
    images: [{ filename: `${name}.svg`, idiom: 'universal' }],
    info,
    properties: props,
  });
}

function colorset(name, hex) {
  const r = parseInt(hex.slice(1, 3), 16), g = parseInt(hex.slice(3, 5), 16), b = parseInt(hex.slice(5, 7), 16);
  const comp = (v) => '0x' + v.toString(16).toUpperCase().padStart(2, '0');
  writeJson(path.join(xcassets, `${name}.colorset`, 'Contents.json'), {
    colors: [{ color: { 'color-space': 'srgb', components: { alpha: '1.000', red: comp(r), green: comp(g), blue: comp(b) } }, idiom: 'universal' }],
    info,
  });
}

// --- xcassets root
writeJson(path.join(xcassets, 'Contents.json'), { info });
colorset('AccentColor', '#705ABF');

// --- иконки (stroke → чёрный, рендер как template)
const icons = {
  'tab-services': 'TabServices', 'tab-about': 'TabAbout', 'tab-sale': 'TabSale',
  'tab-contacts': 'TabContacts', 'tab-cart': 'TabCart',
  'header-search': 'HeaderSearch', 'header-phone': 'HeaderPhone', 'header-chat': 'HeaderChat',
};
for (const [file, name] of Object.entries(icons)) {
  let svg = fs.readFileSync(path.join(brand, 'icons', `${file}.svg`), 'utf8');
  svg = svg.replace(/stroke="(white|#3B3B3B|#FFFFFF)"/gi, 'stroke="#000000"').trim() + '\n';
  imageset(`Icon${name}`, svg, { template: true });
}

// --- логотипы
imageset('LogoDark', fs.readFileSync(path.join(brand, 'logo', 'logo-dark.svg'), 'utf8'), { template: false });
imageset('LogoWhite', fs.readFileSync(path.join(brand, 'logo', 'logo-white.svg'), 'utf8'), { template: false });
// CoreSVG плохо понимает <style>-классы и не-ASCII id → инлайним заливки.
const markSvg = fs.readFileSync(path.join(brand, 'favicon', 'favicon.svg'), 'utf8')
  .replace(/<\?xml[^>]*>\s*/, '')
  .replace(/<style>[\s\S]*?<\/style>/, '')
  .replace(/id="_Безымянный_градиент" data-name="[^"]*"/, 'id="markGradient"')
  .replace(/ id="_Слой_1" data-name="[^"]*"/, '')
  .replace(/width="90.79mm" height="90.79mm"/, 'width="257.37" height="257.37"')
  .replace(/class="cls-1"/g, 'fill="url(#markGradient)"')
  .replace(/class="cls-2"/g, 'fill="#6d0ff2"')
  .replace(/class="cls-3"/g, 'fill="#f2b807"');
imageset('LogoMark', markSvg, { template: false });

// --- AppIcon: знак на белом, поля ~18%
const mark = fs.readFileSync(path.join(brand, 'favicon', 'favicon.svg'), 'utf8');
const inner = mark.replace(/^[\s\S]*?<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '');
const iconSvg = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1024" height="1024" viewBox="0 0 1024 1024">
<rect width="1024" height="1024" fill="#FFFFFF"/>
<g transform="translate(192 192) scale(${(640 / 257.37).toFixed(5)})">${inner}</g>
</svg>`;
const png = new Resvg(iconSvg, { background: '#FFFFFF', fitTo: { mode: 'width', value: 1024 } }).render().asPng();
const appIconDir = path.join(xcassets, 'AppIcon.appiconset');
fs.mkdirSync(appIconDir, { recursive: true });
fs.writeFileSync(path.join(appIconDir, 'AppIcon-1024.png'), png);
writeJson(path.join(appIconDir, 'Contents.json'), {
  images: [{ filename: 'AppIcon-1024.png', idiom: 'universal', platform: 'ios', size: '1024x1024' }],
  info,
});

// --- шрифты
const fontUrls = {
  'GolosText-Regular.ttf': 'https://fonts.gstatic.com/s/golostext/v7/q5uXsoe9Lv5t7Meb31EcOR9UdVTNs822plVRRQ5c.ttf',
  'GolosText-Medium.ttf': 'https://fonts.gstatic.com/s/golostext/v7/q5uXsoe9Lv5t7Meb31EcOR9UdVTNs822plVjRQ5c.ttf',
  'GolosText-SemiBold.ttf': 'https://fonts.gstatic.com/s/golostext/v7/q5uXsoe9Lv5t7Meb31EcOR9UdVTNs822plWPQg5c.ttf',
  'GolosText-Bold.ttf': 'https://fonts.gstatic.com/s/golostext/v7/q5uXsoe9Lv5t7Meb31EcOR9UdVTNs822plW2Qg5c.ttf',
  'Inter-Regular.ttf': 'https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuLyfMZg.ttf',
  'Inter-Medium.ttf': 'https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuI6fMZg.ttf',
  'Inter-SemiBold.ttf': 'https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuGKYMZg.ttf',
  'Inter-Bold.ttf': 'https://fonts.gstatic.com/s/inter/v20/UcCO3FwrK3iLTeHuS_nVMrMxCp50SjIw2boKoduKmMEVuFuYMZg.ttf',
};
fs.mkdirSync(fontsDir, { recursive: true });

function postScriptName(buf) {
  const numTables = buf.readUInt16BE(4);
  for (let i = 0; i < numTables; i++) {
    const rec = 12 + i * 16;
    if (buf.toString('ascii', rec, rec + 4) !== 'name') continue;
    const off = buf.readUInt32BE(rec + 8);
    const count = buf.readUInt16BE(off + 2), strOff = off + buf.readUInt16BE(off + 4);
    for (let j = 0; j < count; j++) {
      const r = off + 6 + j * 12;
      const platform = buf.readUInt16BE(r), nameId = buf.readUInt16BE(r + 6);
      const len = buf.readUInt16BE(r + 8), o = buf.readUInt16BE(r + 10);
      if (nameId !== 6) continue;
      const raw = buf.subarray(strOff + o, strOff + o + len);
      if (platform === 3 || platform === 0) { let s = ''; for (let k = 0; k < raw.length; k += 2) s += String.fromCharCode(raw.readUInt16BE(k)); return s; }
      return raw.toString('latin1');
    }
  }
  return null;
}

for (const [file, url] of Object.entries(fontUrls)) {
  const target = path.join(fontsDir, file);
  if (!fs.existsSync(target)) {
    const r = await fetch(url);
    if (!r.ok) throw new Error(`Не скачался ${url}: ${r.status}`);
    fs.writeFileSync(target, Buffer.from(await r.arrayBuffer()));
  }
  console.log(file.padEnd(24), '→ PostScript:', postScriptName(fs.readFileSync(target)));
}
console.log('Готово:', xcassets);
