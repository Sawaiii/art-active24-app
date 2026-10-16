// Собирает локализуемые строки из Swift-исходников в ArtActive/Resources/Localizable.xcstrings
// (ru — язык разработки, en — из tools/strings-en.json). Xcode делает то же при сборке в IDE,
// но в CI каталог не обновляется — поэтому держим его в git полным.
//
// Ищет: Text("…"), Button("…"), Label("…", …), Toggle("…"), Tab("…", …), Section("…"),
//       Menu("…"), Link("…"), String(localized: "…"). Интерполяции \(expr) → %lld / %@.
// Запуск: node extract-strings.mjs [--check]   (--check: код 1, если нет перевода en)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const appDir = path.resolve(here, '..', 'ArtActive');
const catalogPath = path.join(appDir, 'Resources', 'Localizable.xcstrings');
const enPath = path.join(here, 'strings-en.json');
const check = process.argv.includes('--check');

const swiftFiles = [];
(function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (entry.name.endsWith('.swift')) swiftFiles.push(full);
  }
})(appDir);

// Интерполяции, которые точно строки или числа (остальные — по эвристике).
const STRING_HINTS = /Money\.rub|\.name|title|label|Label|number|address|phone|Phone|DateText|\bunit\b|qtyUnit|corrected|\bart\b|String\(/;
const INT_HINTS = /count|Count|value|minimum|minHours|area|capacity|distance|reviews|extraUnits|minQty|defaultValue|resendIn|total|current|index|\$0|qty/i;

function specifier(expr) {
  if (/extraUnits|minQty|defaultValue|resendIn|itemsCount|\.count\b/.test(expr)) return '%lld';
  if (STRING_HINTS.test(expr)) return '%@';
  if (INT_HINTS.test(expr)) return '%lld';
  return '%@';
}

/** Читает Swift-строковый литерал с позиции открывающей кавычки; возвращает {key, end} или null. */
function readLiteral(src, start) {
  if (src[start] !== '"' || src.startsWith('"""', start)) return null;
  let i = start + 1;
  let key = '';
  let interpolated = false;
  while (i < src.length) {
    const ch = src[i];
    if (ch === '"') return { key: interpolated ? key : key.replaceAll('%%', '%'), end: i + 1 };
    if (ch === '\n') return null;
    if (ch === '\\') {
      const next = src[i + 1];
      if (next === '(') {
        // интерполяция: ищем парную скобку с учётом вложенных строк
        let depth = 1;
        let j = i + 2;
        let expr = '';
        while (j < src.length && depth > 0) {
          const c = src[j];
          if (c === '"') {
            const inner = readLiteral(src, j);
            if (!inner) return null;
            expr += src.slice(j, inner.end);
            j = inner.end;
            continue;
          }
          if (c === '(') depth++;
          if (c === ')') depth--;
          if (depth > 0) expr += c;
          j++;
        }
        interpolated = true;
        key += specifier(expr.trim());
        i = j;
        continue;
      }
      const map = { n: '\n', t: '\t', '"': '"', '\\': '\\', u: null };
      if (next === 'u') {
        const close = src.indexOf('}', i);
        const code = src.slice(i + 3, close);
        key += String.fromCodePoint(parseInt(code, 16));
        i = close + 1;
        continue;
      }
      key += map[next] ?? next;
      i += 2;
      continue;
    }
    if (ch === '%') { key += '%%'; i++; continue; }
    key += ch;
    i++;
  }
  return null;
}

const patterns = [
  /\b(?:Text|Button|Label|Toggle|Tab|Section|Menu|Link)\(\s*(?=")/g,
  /String\(localized:\s*(?=")/g,
];

const found = new Map(); // key -> files
for (const file of swiftFiles) {
  const src = fs.readFileSync(file, 'utf8');
  for (const re of patterns) {
    re.lastIndex = 0;
    let m;
    while ((m = re.exec(src))) {
      const lit = readLiteral(src, re.lastIndex);
      if (!lit) continue;
      const key = lit.key;
      if (!key.trim() || /^[%@lld\s/·×—–\-+0-9.,:()]*$/.test(key)) continue; // только форматы/символы
      if (!found.has(key)) found.set(key, new Set());
      found.get(key).add(path.relative(appDir, file).replaceAll('\\', '/'));
    }
  }
}

const catalog = fs.existsSync(catalogPath)
  ? JSON.parse(fs.readFileSync(catalogPath, 'utf8'))
  : { sourceLanguage: 'ru', strings: {}, version: '1.0' };
const en = fs.existsSync(enPath) ? JSON.parse(fs.readFileSync(enPath, 'utf8')) : {};

const strings = {};
const missing = [];
for (const key of [...found.keys()].sort((a, b) => a.localeCompare(b, 'ru'))) {
  const existing = catalog.strings[key] ?? {};
  const entry = { ...existing };
  entry.localizations = { ...(existing.localizations ?? {}) };
  const translation = en[key];
  if (translation === undefined) {
    missing.push(key);
  } else if (typeof translation === 'string') {
    entry.localizations.en = { stringUnit: { state: 'translated', value: translation } };
  } else {
    // плюралы: { one, other }
    entry.localizations.en = {
      variations: {
        plural: Object.fromEntries(Object.entries(translation).map(([k, v]) => [k, { stringUnit: { state: 'translated', value: v } }])),
      },
    };
  }
  if (Object.keys(entry.localizations).length === 0) delete entry.localizations;
  strings[key] = entry;
}

catalog.strings = strings;
fs.writeFileSync(catalogPath, JSON.stringify(catalog, null, 2) + '\n');
console.log(`Ключей: ${found.size}, без en: ${missing.length}`);
if (missing.length) {
  fs.writeFileSync(path.join(here, 'strings-missing.json'), JSON.stringify(Object.fromEntries(missing.map((k) => [k, ''])), null, 2) + '\n');
  console.log('Список без перевода → tools/strings-missing.json');
  if (check) process.exit(1);
}
