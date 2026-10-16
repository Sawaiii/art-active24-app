#!/usr/bin/env node
// Демо-датасет для CI-скриншотов iOS: из ПОЛНОГО локального снапшота (api/data/snapshot,
// в git не входит) собирает компактный набор в api/tests/fixtures/demo (коммитится).
//
//   node tools/demo-dataset/build.mjs [--src api/data/snapshot] [--out api/tests/fixtures/demo]
//
// Только публичный контент каталога: названия, цены, тексты, ссылки на картинки/видео сайта.
// Перед записью всё проверяется (хосты, отсутствие внутренних эндпоинтов /_*.php и т.п.) —
// при нарушении скрипт падает и ничего не пишет. Без зависимостей (Node 18+).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

// ── Параметры отбора ─────────────────────────────────────────────────────
const MAX_PRODUCTS = 400;
const MAX_PRODUCT_FILES = 60;
const MAX_VENUES = 40;
const MAX_VENUE_FILES = 10;
const SEO_LIMIT = 600;
const MAX_TOTAL_BYTES = 5 * 1024 * 1024;

/** Разделы, чьи листинги показываем на скриншотах: [id, сколько товаров самого раздела, сколько из каждого подраздела]. */
const SECTIONS = [
  [225, 72, 12], // Мебель → Столы (сетка, фильтр, сортировка)
  [81, 48, 5],   // Кейтеринг
  [91, 48, 5],   // Мастер-классы
  [92, 24, 0],   // Аттракционы (батуты)
];

/** Карточки, которые UI-тест открывает напрямую (все шаблоны и режимы). */
const REQUIRED_SLUGS = [
  'stol-viktoriya-180',           // configurator / standard, комплекты + дни
  'plov',                         // configurator / standard, варианты + допы
  'poymay-moment',                // configurator / standard
  'batut-korabl-bolshoj',         // configurator / trampoline
  'akvagrim-sharzh',              // configurator / masterclass
  'furshetnyy-boks-burgery',      // configurator / cateringMenu
  'chajnaya-stanciya',            // simple
  'avtomat-gaz-vody',             // showcase
  'hostes-na-meropriyatie',       // staff
  'timbilding-novaya-versiya-12', // program
];

const SEARCH_WORD = 'батут';
const SEARCH_LIMIT = 24;

const ALLOWED_HOSTS = new Set([
  'www.art-active24.ru', 'art-active24.ru', 'storage.yandexcloud.net',
  'www.youtube.com', 'youtube.com', 'youtu.be', 'rutube.ru',
  't.me', 'vk.com', 'api.whatsapp.com', 'wa.me',
]);
const FORBIDDEN_PATTERNS = [
  [/\.php\b/i, 'ссылка на PHP-скрипт'],
  [/art-active24\.ru\/_/i, 'внутренний путь сайта /_…'],
  [/["'(\s]\/_[a-z0-9]/i, 'относительный внутренний путь /_…'],
  [/\b(api[_-]?key|access[_-]?token|secret|password|passwd|bearer)\b/i, 'похоже на секрет'],
  [/\b(localhost|127\.0\.0\.1|192\.168\.|10\.\d+\.\d+\.\d+)\b/, 'локальный адрес'],
];

// ── CLI ──────────────────────────────────────────────────────────────────
function arg(name, fallback) {
  const i = process.argv.indexOf(name);
  return i > 0 && process.argv[i + 1] ? path.resolve(process.argv[i + 1]) : fallback;
}
const SRC = arg('--src', path.join(ROOT, 'api', 'data', 'snapshot'));
const OUT = arg('--out', path.join(ROOT, 'api', 'tests', 'fixtures', 'demo'));

function readJson(rel) {
  const file = path.join(SRC, rel);
  if (!fs.existsSync(file)) throw new Error(`Нет файла снапшота: ${file}`);
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}
function readOptional(rel) {
  const file = path.join(SRC, rel);
  return fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : null;
}

// ── Обрезка SEO-текста по границе блока ──────────────────────────────────
export function trimSeoHtml(html, limit = SEO_LIMIT) {
  if (typeof html !== 'string' || html.length <= limit) return html ?? null;
  const closers = /<\/(p|ul|ol|h[1-6]|blockquote|div)>/gi;
  let cut = -1;
  let match;
  while ((match = closers.exec(html)) !== null) {
    const end = match.index + match[0].length;
    if (end > limit * 1.6) break;
    cut = end;
    if (end >= limit) break;
  }
  if (cut > 0) return html.slice(0, cut);
  // Нет закрывающего блока рядом — режем по тексту, убираем недописанный тег.
  return html.slice(0, limit).replace(/<[^>]*$/, '').trimEnd() + '…';
}

// ── Отбор ────────────────────────────────────────────────────────────────
function byPopular(a, b) {
  return (a.sortPopular ?? Number.MAX_SAFE_INTEGER) - (b.sortPopular ?? Number.MAX_SAFE_INTEGER);
}

function main() {
  const categories = readJson('categories.json');
  const products = readJson('products.json');
  const venues = readJson('venues.json');
  const venueFilters = readJson('venue-filters.json');
  const home = readJson('home.json');
  const info = readJson('info.json');

  const productById = new Map(products.map((p) => [p.id, p]));
  const productBySlug = new Map(products.map((p) => [p.slug, p]));
  const childrenOf = (id) => categories.filter((c) => c.parentId === id).map((c) => c.id);
  const inCategory = (id) => products.filter((p) => (p.categoryIds ?? []).includes(id)).sort(byPopular);

  // Приоритетная очередь: чем раньше добавлен, тем важнее (лимит режет хвост).
  const picked = new Set();
  const add = (id) => { if (productById.has(id) && picked.size < MAX_PRODUCTS) picked.add(id); };

  // 1) Карточки (products/{id}.json) — сначала обязательные, затем лидеры листингов и «Новинки».
  const detailIds = [];
  const addDetail = (id) => {
    if (productById.has(id) && !detailIds.includes(id) && detailIds.length < MAX_PRODUCT_FILES && readOptional(`products/${id}.json`)) {
      detailIds.push(id);
    }
  };
  for (const slug of REQUIRED_SLUGS) {
    const p = productBySlug.get(slug);
    if (!p) throw new Error(`Обязательный товар «${slug}» не найден в снапшоте`);
    addDetail(p.id);
  }
  const homeIds = (home.sections ?? []).filter((s) => s.type === 'products').flatMap((s) => s.productIds ?? []);
  homeIds.forEach(addDetail);
  for (const [id] of SECTIONS) inCategory(id).slice(0, 8).forEach((p) => addDetail(p.id));
  // По 2–3 лидера подразделов «Столов» — открываются из чипсов раздела.
  for (const kid of childrenOf(225)) inCategory(kid).slice(0, 3).forEach((p) => addDetail(p.id));
  // Добор: хотя бы по 2 карточки каждого шаблона.
  for (const template of ['simple', 'showcase', 'staff', 'program']) {
    products.filter((p) => p.template === template).sort(byPopular).slice(0, 2).forEach((p) => addDetail(p.id));
  }
  detailIds.forEach(add);

  // 2) Листинги разделов (первые страницы по популярности) и подразделы.
  for (const [id, own, perChild] of SECTIONS) {
    inCategory(id).slice(0, own).forEach((p) => add(p.id));
    if (perChild > 0) for (const kid of childrenOf(id)) inCategory(kid).slice(0, perChild).forEach((p) => add(p.id));
  }
  // 3) «Новинки» главной и поиск «батут».
  homeIds.forEach(add);
  products.filter((p) => p.name.toLowerCase().includes(SEARCH_WORD)).sort(byPopular).slice(0, SEARCH_LIMIT).forEach((p) => add(p.id));

  // 4) Похожие у карточек — пока есть место.
  const details = new Map(detailIds.map((id) => [id, readJson(`products/${id}.json`)]));
  for (const d of details.values()) {
    for (const s of [...(d.similar ?? []), ...(d.masterclass?.related ?? [])]) add(s.id);
  }

  const productList = products.filter((p) => picked.has(p.id)).sort(byPopular);

  // ── Категории: все, SEO-текст обрезан ──
  const categoryList = categories.map((c) => ({ ...c, seoHtml: trimSeoHtml(c.seoHtml) }));

  // ── Площадки: топ по популярности, карточки — для первых ──
  const venueList = [...venues].sort(byPopular).slice(0, MAX_VENUES);
  const venueDetails = new Map();
  for (const v of venueList) {
    if (venueDetails.size >= MAX_VENUE_FILES) break;
    const d = readOptional(`venues/${v.id}.json`);
    if (d) venueDetails.set(v.id, d);
  }

  // ── Сборка и проверка ──
  const files = new Map();
  const put = (rel, data, pretty = false) => {
    let text;
    if (Array.isArray(data) && !pretty) {
      text = '[\n' + data.map((item) => JSON.stringify(item)).join(',\n') + '\n]\n';
    } else {
      text = JSON.stringify(data, null, pretty ? 1 : 0) + '\n';
    }
    files.set(rel, text);
  };
  put('categories.json', categoryList);
  put('products.json', productList);
  for (const [id, d] of details) put(`products/${id}.json`, d);
  put('venues.json', venueList);
  for (const [id, d] of venueDetails) put(`venues/${id}.json`, d);
  put('venue-filters.json', venueFilters, true);
  put('home.json', home, true);
  put('info.json', info, true);
  put('manifest.json', {
    note: 'Демо-набор для CI-скриншотов iOS. Собран tools/demo-dataset/build.mjs из публичного каталога сайта.',
    counts: {
      categories: categoryList.length,
      products: productList.length,
      productFiles: details.size,
      venues: venueList.length,
      venueFiles: venueDetails.size,
    },
    productFiles: [...details.values()].map((d) => `${d.id} ${d.slug} ${d.template}${d.configuratorMode ? '/' + d.configuratorMode : ''}`),
  }, true);

  verify(files);

  const total = [...files.values()].reduce((sum, t) => sum + Buffer.byteLength(t), 0);
  if (total > MAX_TOTAL_BYTES) throw new Error(`Датасет ${(total / 1048576).toFixed(2)} МБ > лимита ${MAX_TOTAL_BYTES / 1048576} МБ`);

  fs.rmSync(OUT, { recursive: true, force: true });
  for (const [rel, text] of files) {
    const file = path.join(OUT, rel);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, text);
  }

  const missingHome = homeIds.filter((id) => !picked.has(id));
  console.log(`Готово: ${path.relative(ROOT, OUT)} — ${(total / 1048576).toFixed(2)} МБ`);
  console.log(`  категорий ${categoryList.length}, товаров ${productList.length}, карточек ${details.size}, площадок ${venueList.length} (карточек ${venueDetails.size})`);
  console.log(`  «${SEARCH_WORD}» в названии: ${productList.filter((p) => p.name.toLowerCase().includes(SEARCH_WORD)).length}`);
  for (const [id] of SECTIONS) console.log(`  раздел ${id}: ${productList.filter((p) => p.categoryIds.includes(id)).length} товаров`);
  if (missingHome.length) console.warn(`  ВНИМАНИЕ: нет товаров «Новинок»: ${missingHome.join(', ')}`);
}

/** Публичный контент: только разрешённые хосты, без внутренних эндпоинтов и похожего на секреты. */
function verify(files) {
  const problems = [];
  for (const [rel, text] of files) {
    for (const [re, why] of FORBIDDEN_PATTERNS) {
      const m = text.match(re);
      if (m) problems.push(`${rel}: ${why} — «${text.slice(Math.max(0, m.index - 40), m.index + 40)}»`);
    }
    for (const m of text.matchAll(/(?:https?:)?\/\/([a-z0-9.-]+\.[a-z]{2,})(?=[/"'?:#\s]|$)/gi)) {
      const host = m[1].toLowerCase();
      if (!ALLOWED_HOSTS.has(host)) problems.push(`${rel}: посторонний хост ${host}`);
    }
  }
  if (problems.length) {
    const unique = [...new Set(problems)];
    throw new Error('Проверка датасета не пройдена:\n  ' + unique.slice(0, 30).join('\n  ') + (unique.length > 30 ? `\n  … и ещё ${unique.length - 30}` : ''));
  }
}

try {
  main();
} catch (e) {
  console.error(e.message);
  process.exit(1);
}
