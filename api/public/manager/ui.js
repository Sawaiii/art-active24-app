/*
 * Справочники, форматирование и безопасная отрисовка заявок.
 * Данные выводятся только через textContent / createElement — innerHTML не используется.
 */

export const COMMENT_MAX = 1000;
const TZ = 'Europe/Moscow';

export const STATUSES = [
  { id: 'processing', label: 'В обработке' },
  { id: 'confirmed', label: 'Подтверждён' },
  { id: 'preparing', label: 'Комплектуется' },
  { id: 'delivering', label: 'В пути' },
  { id: 'in_progress', label: 'Мероприятие идёт' },
  { id: 'completed', label: 'Завершён' },
  { id: 'cancelled', label: 'Отменён' },
];
export const STATUS_LABEL = Object.fromEntries(STATUSES.map((s) => [s.id, s.label]));
// Зеркало OrderStatus::allowedNext() в api/src/Orders/OrderStatus.php
export const TRANSITIONS = {
  processing: ['confirmed', 'cancelled'],
  confirmed: ['preparing', 'delivering', 'in_progress', 'completed', 'cancelled'],
  preparing: ['delivering', 'in_progress', 'cancelled'],
  delivering: ['in_progress', 'completed', 'cancelled'],
  in_progress: ['completed'],
  cancelled: ['processing'],
  completed: [],
};
const KIND_LABEL = { cart: 'Корзина', product: 'Товар / услуга', venue: 'Площадка', callback: 'Обратный звонок' };
const PRICE_TYPE_LABEL = { rent: 'Аренда', buy: 'Покупка' };

// ---------- Утилиты ----------
/** Безопасное создание элемента: текст только через textContent / append(string). */
export function h(tag, props = {}, children = []) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (value === null || value === undefined || value === false) continue;
    if (key === 'class') el.className = value;
    else if (key === 'text') el.textContent = String(value);
    else if (key.startsWith('on') && typeof value === 'function') el.addEventListener(key.slice(2), value);
    else el.setAttribute(key, value === true ? '' : String(value));
  }
  for (const child of [].concat(children)) {
    if (child !== null && child !== undefined && child !== false) el.append(child);
  }
  return el;
}

export const str = (v) => (typeof v === 'string' ? v : v === null || v === undefined ? '' : String(v));
export const digits = (v) => str(v).replace(/\D/g, '');
export const moneyFmt = new Intl.NumberFormat('ru-RU');
export const money = (n) => `${moneyFmt.format(Number(n) || 0)} ₽`;
const dateTimeFmt = new Intl.DateTimeFormat('ru-RU', { timeZone: TZ, day: 'numeric', month: 'long', year: 'numeric', hour: '2-digit', minute: '2-digit' });
export const shortFmt = new Intl.DateTimeFormat('ru-RU', { timeZone: TZ, day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
export const timeFmt = new Intl.DateTimeFormat('ru-RU', { timeZone: TZ, hour: '2-digit', minute: '2-digit' });
const dayFmt = new Intl.DateTimeFormat('ru-RU', { timeZone: 'UTC', day: 'numeric', month: 'long', year: 'numeric' });

export function fmtDateTime(value, fmt = dateTimeFmt) {
  const d = new Date(str(value));
  return Number.isNaN(d.getTime()) ? '—' : fmt.format(d);
}
/** 'YYYY-MM-DD' → «1 ноября 2026 г.» без сдвига часового пояса. */
function fmtDay(ymd) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(str(ymd));
  return m ? dayFmt.format(new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]))) : null;
}
export function fmtEventDates(order) {
  const from = fmtDay(order.eventDate);
  const to = fmtDay(order.eventDateTo);
  if (!from) return null;
  return to && to !== from ? `${from} — ${to}` : from;
}
export function prettyPhone(phone) {
  const d = digits(phone);
  if (d.length !== 11) return str(phone);
  return `+7 (${d.slice(1, 4)}) ${d.slice(4, 7)}-${d.slice(7, 9)}-${d.slice(9, 11)}`;
}
const telHref = (phone) => `tel:${str(phone).replace(/[^\d+]/g, '')}`;
export const kindLabel = (kind) => KIND_LABEL[kind] || str(kind);

// ---------- Маска телефона ----------
/** Десять цифр номера без кода страны (+7 / 8 в начале отбрасываются). */
export function extractLocalPhone(value) {
  const v = str(value).trim();
  let d;
  if (v.startsWith('+7')) d = digits(v.slice(2));
  else {
    d = digits(v);
    if (d[0] === '7' || d[0] === '8') d = d.slice(1);
  }
  return d.slice(0, 10);
}
export function formatLocalPhone(local) {
  if (!local) return '';
  let out = `+7 (${local.slice(0, 3)}`;
  if (local.length >= 3) out += ')';
  if (local.length > 3) out += ` ${local.slice(3, 6)}`;
  if (local.length > 6) out += `-${local.slice(6, 8)}`;
  if (local.length > 8) out += `-${local.slice(8, 10)}`;
  return out;
}

// ---------- Список ----------
export function statusChip(status, label, large = false) {
  return h('span', { class: `chip s-${status}${large ? ' chip--lg' : ''}`, text: label || STATUS_LABEL[status] || status });
}

export function orderCard(o, { current, onOpen }) {
  const hasLines = Array.isArray(o.lines) && o.lines.length > 0;
  const totalNode = hasLines && Number(o.total) > 0
    ? h('span', { class: 'order-card__total', text: money(o.total) })
    : h('span', { class: 'order-card__total order-card__total--muted', text: o.hasOnRequest ? 'по запросу' : '—' });
  const who = str(o.contactName) || prettyPhone(o.contactPhone);
  const sub = [kindLabel(o.kind), who, str(o.subject)].filter(Boolean).join(' · ');
  const event = fmtEventDates(o);
  return h('button', {
    type: 'button', class: 'order-card', 'data-id': o.id,
    'aria-current': current ? 'true' : null,
    onclick: () => onOpen(o.id),
  }, [
    h('span', { class: 'order-card__num', text: str(o.number) }),
    totalNode,
    h('span', { class: 'order-card__sub', text: sub }),
    h('span', { class: 'order-card__meta' }, [
      statusChip(o.status, str(o.statusLabel)),
      h('span', { text: fmtDateTime(o.createdAt, shortFmt) }),
      event ? h('span', { text: `мероприятие ${event}` }) : null,
    ]),
  ]);
}

// ---------- Карточка заявки ----------
const fact = (label, value) => h('div', { class: 'fact' }, [
  h('div', { class: 'fact__label', text: label }),
  h('div', { class: 'fact__value' }, value),
]);

function detailFacts(o) {
  const facts = [fact('Мероприятие', fmtEventDates(o) || 'не указана')];
  const d = o.details && typeof o.details === 'object' ? o.details : {};
  if (str(d.eventType)) facts.push(fact('Тип мероприятия', str(d.eventType)));
  if (Number(d.guests) > 0) facts.push(fact('Гостей', moneyFmt.format(Number(d.guests))));
  if (Number(d.venueId) > 0) facts.push(fact('Площадка', `Площадка #${Number(d.venueId)}`));
  if (Number(d.productId) > 0) {
    const complect = Number(d.complectId) > 0 ? `, комплект #${Number(d.complectId)}` : '';
    facts.push(fact('Товар', `Товар #${Number(d.productId)}${complect}`));
  }
  if (o.delivery && o.delivery.method) {
    const isPickup = o.delivery.method === 'pickup';
    facts.push(fact(isPickup ? 'Самовывоз' : 'Доставка', isPickup ? 'Самовывоз со склада' : str(o.delivery.address) || 'адрес не указан'));
  }
  const phone = str(o.contactPhone);
  facts.push(fact('Контакт', [
    str(o.contactName) ? h('div', { text: str(o.contactName) }) : null,
    phone ? h('a', { href: telHref(phone), text: prettyPhone(phone) }) : '—',
  ]));
  facts.push(fact('Сумма', Number(o.total) > 0 ? money(o.total) : (o.hasOnRequest ? 'по запросу' : '—')));
  return facts;
}

function headPanel(o, onBack) {
  const changed = o.updatedAt && o.updatedAt !== o.createdAt ? ` · изменена ${fmtDateTime(o.updatedAt)}` : '';
  return h('section', { class: 'panel', 'aria-labelledby': 'detail-num' }, [
    h('button', { type: 'button', class: 'btn btn--ghost btn--sm detail__back', onclick: onBack }, '← Все заявки'),
    h('div', { class: 'detail__head' }, [
      h('h2', { class: 'detail__num', id: 'detail-num', tabindex: '-1', text: str(o.number) }),
      statusChip(o.status, str(o.statusLabel), true),
      h('span', { class: 'detail__kind', text: kindLabel(o.kind) }),
      h('p', { class: 'detail__created', text: `Создана ${fmtDateTime(o.createdAt)}${changed}` }),
    ]),
    str(o.subject) ? h('p', { class: 'detail__subject', text: str(o.subject) }) : null,
    h('div', { class: 'facts' }, detailFacts(o)),
    str(o.comment) ? h('p', { class: 'note' }, [h('span', { class: 'note__label', text: 'Комментарий клиента' }), str(o.comment)]) : null,
  ]);
}

const linesSum = (lines) => lines.reduce((sum, l) => sum + (l.onRequest ? 0 : Number(l.total) || 0), 0);

function linesPanel(o, lines) {
  const sum = linesSum(lines);
  return h('section', { class: 'panel', 'aria-labelledby': 'lines-title' }, [
    h('h3', { class: 'panel__title', id: 'lines-title', text: `Позиции (${lines.length})` }),
    h('ul', { class: 'lines' }, lines.map(lineRow)),
    h('div', { class: 'summary' }, [
      h('span', { class: 'summary__label', text: 'Итого' }),
      h('span', { class: 'summary__value', text: money(o.total) }),
      o.hasOnRequest ? h('span', { class: 'summary__hint', text: 'Есть позиции «по запросу» — они не входят в итог' }) : null,
      sum !== Number(o.total) ? h('span', { class: 'summary__hint', text: `Сумма позиций ${money(sum)} — итог согласован менеджером` }) : null,
    ]),
  ]);
}

function lineImage(line) {
  const src = str(line.image);
  const placeholder = () => h('span', { class: 'line__img', 'aria-hidden': 'true', text: str(line.art).slice(-4) || '—' });
  if (!/^https:\/\//.test(src)) return placeholder();
  const img = h('img', { class: 'line__img', src, alt: '', width: '56', height: '56', loading: 'lazy', referrerpolicy: 'no-referrer' });
  img.addEventListener('error', () => img.replaceWith(placeholder()), { once: true });
  return img;
}

function lineRow(line) {
  const input = line.input && typeof line.input === 'object' ? line.input : {};
  const tags = [
    str(line.complectTitle) ? h('span', { class: 'tag tag--accent', text: `Комплект: ${str(line.complectTitle)}` }) : null,
    str(line.subTitle) ? h('span', { class: 'tag', text: `Вариант: ${str(line.subTitle)}` }) : null,
    str(line.timeLabel) ? h('span', { class: 'tag', text: `Срок: ${str(line.timeLabel)}` }) : null,
    PRICE_TYPE_LABEL[input.priceType] ? h('span', { class: 'tag', text: PRICE_TYPE_LABEL[input.priceType] }) : null,
  ].filter(Boolean);
  const unit = str(line.qtyUnit) || 'шт';
  const qty = Number(line.qty) || 0;
  const qtyText = line.onRequest || !line.unitPrice ? `${qty} ${unit}` : `${qty} ${unit} × ${money(line.unitPrice)}`;
  const extras = Array.isArray(line.extras) ? line.extras : [];
  return h('li', { class: 'line' }, [
    lineImage(line),
    h('div', { class: 'line__name' }, [str(line.productName) || 'Позиция', str(line.art) ? h('span', { class: 'line__art', text: `арт. ${str(line.art)}` }) : null]),
    h('div', { class: 'line__total', text: line.onRequest ? 'по запросу' : money(line.total) }),
    tags.length ? h('div', { class: 'line__props' }, tags) : null,
    h('div', { class: 'line__qty', text: qtyText }),
    extras.length ? h('ul', { class: 'line__extras', 'aria-label': 'Дополнительно' }, extras.map((x) => h('li', {
      text: `${str(x.name)}${Number(x.qty) > 1 ? ` × ${Number(x.qty)}` : ''}${Number(x.price) > 0 ? ` — ${money(x.price)}` : ''}`,
    }))) : null,
  ]);
}

function historyPanel(o) {
  const events = Array.isArray(o.history) ? o.history : [];
  const item = (ev) => h('li', { class: `tl s-${str(ev.status)}` }, [
    h('div', { class: 'tl__head' }, [
      h('span', { class: 'tl__label', text: str(ev.label) || STATUS_LABEL[ev.status] || str(ev.status) }),
      h('time', { class: 'tl__at', datetime: str(ev.at), text: fmtDateTime(ev.at) }),
    ]),
    str(ev.comment) ? h('p', { class: 'tl__comment', text: str(ev.comment) }) : null,
  ]);
  return h('section', { class: 'panel', 'aria-labelledby': 'history-title' }, [
    h('h3', { class: 'panel__title', id: 'history-title', text: 'История' }),
    events.length ? h('ol', { class: 'timeline' }, events.map(item)) : h('p', { class: 'final-note', text: 'История пуста' }),
  ]);
}

// ---------- Форма смены статуса ----------
export const submitLabel = (status) => (status ? `Перевести в «${STATUS_LABEL[status]}»` : 'Выберите статус');

function statusForm(o, next, form, handlers) {
  const choices = next.map((s) => h('button', {
    type: 'button', class: `choice s-${s}${s === 'cancelled' ? ' choice--danger' : ''}`,
    'aria-pressed': form.status === s ? 'true' : 'false', 'data-status': s,
    onclick: () => handlers.onPick(s),
  }, STATUS_LABEL[s]));

  const comment = h('textarea', { class: 'field__input', id: 'f-comment', name: 'comment', maxlength: String(COMMENT_MAX), rows: '3', 'aria-describedby': 'f-comment-hint', placeholder: 'Например: ждём вас 1 ноября, доставка с 9 до 12' });
  const counter = h('p', { class: 'field__hint', id: 'f-comment-hint', text: `0 / ${COMMENT_MAX} · необязательно` });
  comment.addEventListener('input', () => {
    handlers.onDirty();
    counter.textContent = `${comment.value.length} / ${COMMENT_MAX} · необязательно`;
  });
  const total = h('input', { class: 'field__input', id: 'f-total', name: 'total', type: 'text', inputmode: 'numeric', autocomplete: 'off', placeholder: moneyFmt.format(Number(o.total) || 0), 'aria-describedby': 'f-total-hint' });
  total.addEventListener('input', () => {
    handlers.onDirty();
    const local = digits(total.value).slice(0, 9);
    total.value = local ? moneyFmt.format(Number(local)) : '';
    total.removeAttribute('aria-invalid');
  });

  return h('form', { novalidate: true, onsubmit: (e) => { e.preventDefault(); handlers.onSubmit(o); } }, [
    h('fieldset', { class: 'status-choices' }, [h('legend', { text: 'Перевести в статус' }), ...choices]),
    h('div', { class: 'actions__grid' }, [
      h('div', {}, [h('label', { class: 'field__label', for: 'f-comment', text: 'Комментарий для клиента' }), comment, counter]),
      h('div', {}, [
        h('label', { class: 'field__label', for: 'f-total', text: 'Согласованный итог' }),
        h('div', { class: 'money-input' }, [total, h('span', { class: 'money-input__cur', 'aria-hidden': 'true', text: '₽' })]),
        h('p', { class: 'field__hint', id: 'f-total-hint', text: `Необязательно. Сейчас: ${Number(o.total) > 0 ? money(o.total) : '—'}` }),
      ]),
    ]),
    h('div', { class: 'actions__footer' }, [
      h('button', { type: 'submit', class: 'btn btn--primary', id: 'f-submit', disabled: !form.status }, submitLabel(form.status)),
      h('p', { class: 'actions__error', id: 'f-error', role: 'alert' }),
    ]),
  ]);
}

function actionsPanel(o, form, handlers) {
  const next = TRANSITIONS[o.status] || [];
  const panel = h('section', { class: 'panel', 'aria-labelledby': 'actions-title' }, [
    h('h3', { class: 'panel__title', id: 'actions-title', text: 'Действия' }),
  ]);
  if (!next.length) {
    panel.append(h('p', { class: 'final-note', text: 'Заявка завершена — статус больше не меняется.' }));
    return panel;
  }
  panel.append(
    h('p', { class: 'actions__hint', text: 'Клиент получит push-уведомление и увидит комментарий в истории заявки.' }),
    statusForm(o, next, form, handlers),
  );
  return panel;
}

/** Отметить выбранный статус в уже отрисованной форме. */
export function markPickedStatus(root, status) {
  for (const btn of root.querySelectorAll('.choice')) {
    btn.setAttribute('aria-pressed', btn.dataset.status === status ? 'true' : 'false');
  }
  const submit = root.querySelector('#f-submit');
  if (submit) {
    submit.disabled = !status;
    submit.textContent = submitLabel(status);
  }
  const error = root.querySelector('#f-error');
  if (error) error.textContent = '';
}

/**
 * Узлы карточки заявки.
 * @param handlers {{ onBack, onPick, onDirty, onSubmit }}
 */
export function orderDetailNodes(o, form, handlers) {
  const lines = Array.isArray(o.lines) ? o.lines : [];
  return [
    headPanel(o, handlers.onBack),
    lines.length ? linesPanel(o, lines) : null,
    actionsPanel(o, form, handlers),
    historyPanel(o),
  ].filter(Boolean);
}
