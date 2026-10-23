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
/** Кейсы: сначала те, что на главной, затем первые из списка /cases/. */
const MAX_CASES = 40;
const SEO_LIMIT = 600;
const MAX_TOTAL_BYTES = 20 * 1024 * 1024;

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
  't.me', 'vk.com', 'api.whatsapp.com', 'wa.me', 'max.ru',
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
  for (const id of detailIds) {
    const d = readJson(`products/${id}.json`);
    for (const s of [...(d.similar ?? []), ...(d.masterclass?.related ?? [])]) add(s.id);
  }

  // 5) Полная карточка у КАЖДОГО товара набора: что видно в листинге — то открывается.
  //    Товары без карточки в снапшоте в набор не попадают.
  const details = new Map();
  for (const id of picked) {
    const d = readOptional(`products/${id}.json`);
    if (d) details.set(id, d); else picked.delete(id);
  }
  // Ссылки только внутри набора: «Похожие» и связанные МК не ведут на отсутствующие товары.
  const inSet = (s) => picked.has(s.id);
  // Ава листинга — в карточку (для избранного/«Вы смотрели») и в «Похожие», как делает API.
  const listImage = new Map(products.map((p) => [p.id, p.image]));
  const withAva = (s) => (listImage.get(s.id) ? { ...s, image: listImage.get(s.id) } : s);
  for (const [id, d] of details) {
    details.set(id, {
      ...d,
      ...(listImage.get(id) ? { image: listImage.get(id) } : {}),
      similar: (d.similar ?? []).filter(inSet).map(withAva),
      // Допы без id (так бывает на сайте) не выбрать и не посчитать — как и в API, отбрасываем.
      ...(d.extras ? { extras: d.extras.filter((e) => e.id != null) } : {}),
      ...(d.masterclass ? { masterclass: { ...d.masterclass, related: (d.masterclass.related ?? []).filter(inSet).map(withAva) } } : {}),
    });
  }

  const productList = products.filter((p) => picked.has(p.id)).sort(byPopular);

  // ── Категории: все, SEO-текст обрезан ──
  const categoryList = categories.map((c) => ({ ...c, seoHtml: trimSeoHtml(c.seoHtml) }));

  // ── Площадки: топ по популярности, карточки — для первых ──
  // Каждая площадка списка открывается: без карточки в снапшоте — не берём; «Похожие» — внутри набора.
  const venueDetails = new Map();
  for (const v of [...venues].sort(byPopular)) {
    if (venueDetails.size >= MAX_VENUES) break;
    const d = readOptional(`venues/${v.id}.json`);
    if (d) venueDetails.set(v.id, d);
  }
  const venueList = [...venues].filter((v) => venueDetails.has(v.id)).sort(byPopular);
  for (const [id, d] of venueDetails) {
    venueDetails.set(id, { ...d, similar: (d.similar ?? []).filter((s) => venueDetails.has(s.id)) });
  }

  // ── Кейсы и «Акции» ──
  const { list: caseList, details: caseDetails } = pickCases(home, picked);
  const sale = readOptional('sale.json');

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
  if (sale) put('sale.json', sale, true);
  if (caseList) {
    put('cases.json', caseList, true);
    for (const d of caseDetails) put(`cases/${d.slug}.json`, d);
  }
  put('manifest.json', {
    note: 'Демо-набор для CI-скриншотов iOS. Собран tools/demo-dataset/build.mjs из публичного каталога сайта.',
    counts: {
      categories: categoryList.length,
      products: productList.length,
      productFiles: details.size,
      venues: venueList.length,
      venueFiles: venueDetails.size,
      cases: caseDetails.length,
      saleOffers: sale?.items?.length ?? 0,
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

/**
 * Кейсы набора: кейсы главной + первые из списка (до MAX_CASES), только с файлом-карточкой.
 * Товары кейса и «Похожие кейсы» — только внутри набора: что видно, то открывается.
 */
function pickCases(home, picked) {
  const list = readOptional('cases.json');
  if (!list) return { list: null, details: [] };
  const slugOfUrl = (url) => (String(url ?? '').match(/\/cases\/([a-z0-9_-]+)\/?$/i) ?? [])[1]?.toLowerCase();
  const homeSlugs = (home.sections ?? []).filter((s) => s.type === 'cases').flatMap((s) => s.items ?? []).map((it) => slugOfUrl(it.url));
  const order = [...new Set([...homeSlugs, ...(list.items ?? []).map((s) => s.slug)])].filter(Boolean);

  const raw = new Map();
  for (const slug of order) {
    if (raw.size >= MAX_CASES) break;
    const d = readOptional(`cases/${slug}.json`);
    if (d) raw.set(slug, d);
  }
  const details = [...raw.values()].map((d) => ({
    ...d,
    productIds: (d.productIds ?? []).filter((id) => picked.has(id)),
    similar: (d.similar ?? []).filter((s) => raw.has(s.slug)),
  }));
  const items = (list.items ?? []).filter((s) => raw.has(s.slug));
  const counts = new Map();
  for (const s of items) if (s.categoryId != null) counts.set(s.categoryId, (counts.get(s.categoryId) ?? 0) + 1);
  const categories = (list.categories ?? [])
    .map((c) => ({ ...c, count: counts.get(c.id) ?? 0 }))
    .filter((c) => c.count > 0);
  return { list: { ...list, categories, items }, details };
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
