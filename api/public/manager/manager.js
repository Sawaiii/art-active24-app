/*
 * Панель менеджера заявок Арт-Актив — точка входа (ES-модуль, ES2020, без зависимостей).
 * api.js — HTTP и сессия; ui.js — форматирование и отрисовка. innerHTML не используется.
 */
import { ApiError, apiBaseFromLocation, createApi, errorText, sessionStore } from './api.js';
import {
  STATUSES, digits, extractLocalPhone, formatLocalPhone, h, markPickedStatus, orderCard,
  orderDetailNodes, prettyPhone, str, timeFmt,
} from './ui.js';

const PAGE_LIMIT = 20;
const REFRESH_MS = 60000;
const SEARCH_DEBOUNCE_MS = 300;
const SEARCH_MAX = 50;
const RESEND_FALLBACK_S = 60;
const DEFAULT_CODE_LENGTH = 6; // фактическая длина приходит в ответе /v1/auth/code (codeLength)
const MOBILE_MAX = 900;
const TOAST_MS = 3500;
const BASE_TITLE = 'Заявки — Арт-Актив';

const $ = (id) => document.getElementById(id);

const state = {
  session: null,
  status: '',
  query: '',
  page: 1,
  total: 0,
  orders: [],
  selected: null,
  processingTotal: null,
  newestProcessingId: null,
  loadSeq: 0,
  openSeq: 0,
  lastLoadAt: 0,
  refreshTimer: null,
  searchTimer: null,
  form: { status: null, dirty: false },
  login: { phone: '', resendTimer: null, codeLength: DEFAULT_CODE_LENGTH },
};

const api = createApi({
  base: apiBaseFromLocation(location),
  getSession: () => state.session,
  setSession: (s) => { state.session = s; },
  onAuthLost: () => endSession('Сессия истекла — войдите снова'),
  onForbidden: () => showDenied(),
});

// ---------- Экраны ----------
function showScreen(name) {
  $('screen-login').hidden = name !== 'login';
  $('screen-denied').hidden = name !== 'denied';
  $('screen-app').hidden = name !== 'app';
  $('topbar').hidden = name !== 'app';
}

function dropSession() {
  stopAutoRefresh();
  const token = state.session && state.session.accessToken;
  state.session = null;
  sessionStore.clear();
  resetAppState();
  return token;
}

function showDenied() {
  const token = dropSession();
  if (token) api.raw('POST', 'v1/auth/logout', { token }).catch(() => {});
  showScreen('denied');
  $('denied-back').focus();
}

function endSession(message) {
  dropSession();
  showLogin(message);
}

function logout() {
  const token = dropSession();
  showLogin('Вы вышли из панели.');
  if (token) api.raw('POST', 'v1/auth/logout', { token }).catch(() => {});
}

function resetAppState() {
  clearTimeout(state.searchTimer);
  Object.assign(state, {
    status: '', query: '', page: 1, total: 0, orders: [], selected: null,
    processingTotal: null, newestProcessingId: null, form: { status: null, dirty: false },
  });
  $('search-input').value = '';
  document.title = BASE_TITLE;
  if (location.hash) history.replaceState(null, '', location.pathname + location.search);
}

function toast(text) {
  const el = $('toast');
  el.textContent = text;
  el.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { el.hidden = true; }, TOAST_MS);
}

// ---------- Вход ----------
function setFieldError(input, errorEl, message) {
  errorEl.textContent = message;
  if (message) input.setAttribute('aria-invalid', 'true');
  else input.removeAttribute('aria-invalid');
}

function setBusy(button, busy, busyText) {
  if (busy) {
    button.dataset.label = button.textContent;
    button.textContent = busyText;
    button.disabled = true;
    return;
  }
  if (button.dataset.label) button.textContent = button.dataset.label;
  button.disabled = false;
}

function onPhoneInput(e) {
  const input = e.target;
  const prevLocal = input.dataset.local || '';
  let local = extractLocalPhone(input.value);
  // Стёрли символ маски («)», «-», пробел) — убираем и цифру перед ним, иначе маска «залипает».
  if (e.inputType && e.inputType.startsWith('delete') && local === prevLocal) local = local.slice(0, -1);
  input.dataset.local = local;
  input.value = formatLocalPhone(local);
  setFieldError(input, $('phone-error'), '');
}

function showLogin(message) {
  clearInterval(state.login.resendTimer);
  showScreen('login');
  $('phone-form').hidden = false;
  $('code-form').hidden = true;
  $('login-lead').textContent = message || 'Войдите по номеру телефона — пришлём код в SMS.';
  const input = $('phone-input');
  input.dataset.local = state.login.phone ? state.login.phone.slice(2) : '';
  input.value = formatLocalPhone(input.dataset.local);
  input.focus();
}

async function requestCode(phone, button) {
  setBusy(button, true, 'Отправляем…');
  try {
    const { data } = await api.raw('POST', 'v1/auth/code', { body: { phone } });
    state.login.phone = phone;
    const len = Number(data && data.codeLength);
    state.login.codeLength = Number.isInteger(len) && len >= 3 && len <= 10 ? len : DEFAULT_CODE_LENGTH;
    openCodeStep(Number(data && data.resendIn) || RESEND_FALLBACK_S);
  } catch (e) {
    if (e instanceof ApiError && e.status === 429 && e.retryAfter && !$('code-form').hidden) startResendTimer(e.retryAfter);
    throw e;
  } finally {
    setBusy(button, false);
  }
}

async function onPhoneSubmit(e) {
  e.preventDefault();
  const input = $('phone-input');
  const local = extractLocalPhone(input.value);
  if (local.length !== 10 || local[0] !== '9') {
    setFieldError(input, $('phone-error'), 'Введите мобильный номер в формате +7 (999) 999-99-99');
    input.focus();
    return;
  }
  try {
    await requestCode(`+7${local}`, $('phone-submit'));
  } catch (err) {
    setFieldError(input, $('phone-error'), errorText(err));
  }
}

function openCodeStep(resendIn) {
  $('phone-form').hidden = true;
  $('code-form').hidden = false;
  $('code-sent').replaceChildren('Код отправлен на ', h('strong', { text: prettyPhone(state.login.phone) }));
  const code = $('code-input');
  code.value = '';
  code.maxLength = state.login.codeLength;
  code.placeholder = '•'.repeat(state.login.codeLength);
  setFieldError(code, $('code-error'), '');
  startResendTimer(resendIn);
  code.focus();
}

function startResendTimer(seconds) {
  clearInterval(state.login.resendTimer);
  const until = Date.now() + seconds * 1000;
  const tick = () => {
    const left = Math.ceil((until - Date.now()) / 1000);
    if (left <= 0) {
      clearInterval(state.login.resendTimer);
      $('resend-btn').disabled = false;
      $('resend-timer').textContent = '';
      return;
    }
    $('resend-btn').disabled = true;
    $('resend-timer').textContent = `Повторная отправка через ${Math.floor(left / 60)}:${String(left % 60).padStart(2, '0')}`;
  };
  tick();
  state.login.resendTimer = setInterval(tick, 1000);
}

function onCodeInput(e) {
  const input = e.target;
  input.value = digits(input.value).slice(0, state.login.codeLength);
  setFieldError(input, $('code-error'), '');
  if (input.value.length === state.login.codeLength) $('code-form').requestSubmit();
}

async function onCodeSubmit(e) {
  e.preventDefault();
  const input = $('code-input');
  const button = $('code-submit');
  if (button.disabled) return;
  if (input.value.length !== state.login.codeLength) {
    setFieldError(input, $('code-error'), `Введите код из SMS — ${state.login.codeLength} цифр`);
    input.focus();
    return;
  }
  setBusy(button, true, 'Проверяем…');
  try {
    const { data } = await api.raw('POST', 'v1/auth/verify', { body: { phone: state.login.phone, code: input.value } });
    clearInterval(state.login.resendTimer);
    state.session = sessionStore.save(data);
    if (state.session.user.role !== 'manager') showDenied();
    else startApp();
  } catch (err) {
    setFieldError(input, $('code-error'), errorText(err));
    input.select();
  } finally {
    setBusy(button, false);
  }
}

async function onResend() {
  try {
    await requestCode(state.login.phone, $('resend-btn'));
    toast('Код отправлен повторно');
  } catch (err) {
    setFieldError($('code-input'), $('code-error'), errorText(err));
  }
}

// ---------- Список ----------
function startApp(initialOrderId = null) {
  resetAppState();
  showScreen('app');
  $('user-phone').textContent = prettyPhone(state.session.user.phone);
  renderTabs();
  renderListSkeleton();
  renderDetail();
  loadList();
  startAutoRefresh();
  $('main').focus();
  if (initialOrderId !== null) openOrder(initialOrderId);
}

function listPath() {
  const query = new URLSearchParams({ page: String(state.page), limit: String(PAGE_LIMIT) });
  if (state.status) query.set('status', state.status);
  if (state.query) query.set('q', state.query);
  return `v1/manager/orders?${query}`;
}

async function loadList({ silent = false } = {}) {
  const seq = ++state.loadSeq;
  const btn = $('refresh-btn');
  btn.classList.add('is-spinning');
  const sameAsProcessing = state.status === 'processing' && !state.query;
  try {
    const [list, newest] = await Promise.all([
      api.authed('GET', listPath()),
      sameAsProcessing ? null : api.authed('GET', 'v1/manager/orders?status=processing&limit=1'),
    ]);
    if (seq !== state.loadSeq) return;
    applyList(list, newest || list, silent);
  } catch (e) {
    if (seq !== state.loadSeq || e.handled) return;
    showListError(errorText(e));
  } finally {
    if (seq === state.loadSeq) btn.classList.remove('is-spinning');
  }
}

function applyList(list, processing, silent) {
  const orders = Array.isArray(list.data) ? list.data : [];
  const total = Number(list.meta && list.meta.total) || 0;
  const pages = Math.max(1, Math.ceil(total / PAGE_LIMIT));
  if (!orders.length && state.page > pages) {
    state.page = pages;
    loadList({ silent });
    return;
  }
  state.orders = orders;
  state.total = total;
  state.lastLoadAt = Date.now();
  trackProcessing(processing);
  showListError('');
  syncSelected();
  renderTabs();
  renderList();
}

/** Бейдж «новых» = заявки в processing; тост, если появилась свежая. */
function trackProcessing(result) {
  const items = Array.isArray(result.data) ? result.data : [];
  const total = Number(result.meta && result.meta.total) || 0;
  const newest = items.find((o) => o.status === 'processing');
  const newestId = newest ? Number(newest.id) : 0;
  if (state.newestProcessingId !== null && newestId > state.newestProcessingId) toast(`Новая заявка ${str(newest.number)}`);
  state.newestProcessingId = Math.max(state.newestProcessingId || 0, newestId);
  state.processingTotal = total;
  $('new-pill').hidden = total === 0;
  $('new-pill').textContent = `Новых: ${total}`;
  document.title = total > 0 ? `(${total}) ${BASE_TITLE}` : BASE_TITLE;
}

function syncSelected() {
  if (!state.selected) return;
  const fresh = state.orders.find((o) => o.id === state.selected.id);
  if (fresh && fresh.updatedAt !== state.selected.updatedAt && !state.form.dirty) {
    state.selected = fresh;
    renderDetail();
  }
}

function showListError(message) {
  $('list-error').textContent = message;
  $('list-error').hidden = !message;
}

function renderTabs() {
  const tabs = [{ id: '', label: 'Все' }, ...STATUSES];
  const nodes = tabs.map((t) => {
    const selected = state.status === t.id;
    const count = t.id === 'processing' && state.processingTotal
      ? h('span', { class: 'tab__count', text: state.processingTotal, 'aria-label': `новых: ${state.processingTotal}` })
      : null;
    return h('button', {
      type: 'button', role: 'tab', class: `tab${t.id ? ` s-${t.id}` : ''}`,
      'aria-selected': selected ? 'true' : 'false', 'aria-controls': 'order-list',
      tabindex: selected ? '0' : '-1', 'data-status': t.id,
      onclick: () => selectStatus(t.id),
    }, [t.id ? h('span', { class: 'tab__dot', 'aria-hidden': 'true' }) : null, t.label, count]);
  });
  const strip = $('status-tabs');
  const scrollLeft = strip.scrollLeft;
  strip.replaceChildren(...nodes);
  strip.scrollLeft = scrollLeft;
  const active = strip.querySelector('[aria-selected="true"]');
  if (active && (active.offsetLeft < strip.scrollLeft || active.offsetLeft + active.offsetWidth > strip.scrollLeft + strip.clientWidth)) {
    strip.scrollLeft = active.offsetLeft - 12;
  }
}

function onTabsKeydown(e) {
  if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(e.key)) return;
  const tabs = [...$('status-tabs').querySelectorAll('[role="tab"]')];
  const i = tabs.indexOf(document.activeElement);
  if (i < 0) return;
  e.preventDefault();
  const step = e.key === 'ArrowRight' ? 1 : -1;
  const next = e.key === 'Home' ? 0 : e.key === 'End' ? tabs.length - 1 : (i + step + tabs.length) % tabs.length;
  const status = tabs[next].dataset.status;
  selectStatus(status);
  $('status-tabs').querySelector(`[data-status="${status}"]`).focus();
}

function selectStatus(status) {
  if (state.status === status) return;
  state.status = status;
  state.page = 1;
  renderTabs();
  renderListSkeleton();
  loadList();
}

/** Серверный поиск: debounce, фильтр статуса сохраняется, страница — с первой. */
function onSearchInput(e) {
  clearTimeout(state.searchTimer);
  const value = e.target.value.trim().slice(0, SEARCH_MAX);
  state.searchTimer = setTimeout(() => {
    if (value === state.query) return;
    state.query = value;
    state.page = 1;
    renderListSkeleton();
    loadList();
  }, SEARCH_DEBOUNCE_MS);
}

function renderListSkeleton() {
  $('order-list').replaceChildren(...Array.from({ length: 5 }, () => h('li', { class: 'skeleton', 'aria-hidden': 'true' })));
  $('pager').hidden = true;
}

function renderList() {
  const list = $('order-list');
  if (!state.orders.length) {
    const text = state.query ? `По запросу «${state.query}» ничего не найдено` : 'Заявок с таким статусом нет';
    list.replaceChildren(h('li', { class: 'empty-state', text }));
  } else {
    const currentId = state.selected ? state.selected.id : null;
    list.replaceChildren(...state.orders.map((o) => h('li', {}, orderCard(o, { current: o.id === currentId, onOpen: openOrder }))));
  }
  const found = state.query ? `Найдено: ${state.total}` : `Всего: ${state.total}`;
  const updated = state.lastLoadAt ? ` · обновлено в ${timeFmt.format(new Date(state.lastLoadAt))}` : '';
  $('list-meta').textContent = found + updated;
  renderPager();
}

function renderPager() {
  const pages = Math.max(1, Math.ceil(state.total / PAGE_LIMIT));
  $('pager').hidden = pages <= 1;
  $('page-info').textContent = `Стр. ${state.page} из ${pages}`;
  $('prev-page').disabled = state.page <= 1;
  $('next-page').disabled = state.page >= pages;
}

function goPage(delta) {
  state.page = Math.max(1, state.page + delta);
  renderListSkeleton();
  loadList();
  $('order-list').scrollTop = 0;
}

// ---------- Авто-обновление ----------
function startAutoRefresh() {
  stopAutoRefresh();
  state.refreshTimer = setInterval(() => {
    if (document.visibilityState === 'visible') loadList({ silent: true });
  }, REFRESH_MS);
}
function stopAutoRefresh() {
  clearInterval(state.refreshTimer);
  state.refreshTimer = null;
}
function onVisibility() {
  if (document.visibilityState === 'visible' && state.session && Date.now() - state.lastLoadAt > REFRESH_MS) {
    loadList({ silent: true });
  }
}

// ---------- Карточка заявки ----------
/** Открыть заявку: из загруженной страницы или GET /v1/manager/orders/{id}. */
async function openOrder(id) {
  const changing = !state.selected || state.selected.id !== id;
  if (changing && state.form.dirty && !window.confirm('Есть несохранённые изменения. Открыть другую заявку?')) return;
  const seq = ++state.openSeq;
  let order = state.orders.find((o) => o.id === id);
  if (!order) {
    try {
      order = (await api.authed('GET', `v1/manager/orders/${encodeURIComponent(id)}`)).data;
    } catch (e) {
      if (seq !== state.openSeq || e.handled) return;
      toast(e instanceof ApiError && e.status === 404 ? 'Заявка не найдена' : errorText(e));
      if (location.hash === `#order-${id}`) history.replaceState(null, '', location.pathname + location.search);
      return;
    }
    if (seq !== state.openSeq || !state.session) return;
  }
  state.selected = order;
  if (changing) state.form = { status: null, dirty: false };
  if (location.hash !== `#order-${id}`) history.pushState({ id }, '', `#order-${id}`);
  renderDetail();
  renderList();
  const heading = $('detail-num');
  if (heading) heading.focus({ preventScroll: window.innerWidth > MOBILE_MAX });
  if (window.innerWidth <= MOBILE_MAX) window.scrollTo(0, 0);
}

function closeOrder() {
  const id = state.selected ? state.selected.id : null;
  state.openSeq++;
  state.selected = null;
  state.form = { status: null, dirty: false };
  renderDetail();
  renderList();
  const card = id !== null ? $('order-list').querySelector(`[data-id="${id}"]`) : null;
  if (card) card.focus();
}

const hashOrderId = () => {
  const m = /^#order-(\d{1,10})$/.exec(location.hash);
  return m ? Number(m[1]) : null;
};

function onHashChange() {
  if (!state.session) return;
  const id = hashOrderId();
  if (id === null) {
    if (state.selected) closeOrder();
  } else if (!state.selected || state.selected.id !== id) {
    openOrder(id);
  }
}

const detailHandlers = {
  onBack: () => history.back(),
  onDirty: () => { state.form.dirty = true; },
  onPick: (status) => {
    state.form.status = state.form.status === status ? null : status;
    state.form.dirty = true;
    markPickedStatus($('detail'), state.form.status);
  },
  onSubmit: (order) => submitStatus(order),
};

function renderDetail() {
  const o = state.selected;
  $('screen-app').classList.toggle('is-detail', Boolean(o));
  $('detail-empty').hidden = Boolean(o);
  const detail = $('detail');
  detail.hidden = !o;
  detail.replaceChildren(...(o ? orderDetailNodes(o, state.form, detailHandlers) : []));
}

// ---------- Смена статуса ----------
function readStatusForm() {
  const body = { status: state.form.status };
  const comment = $('f-comment').value.trim();
  if (comment) body.comment = comment;
  const totalRaw = digits($('f-total').value);
  if (totalRaw) {
    const total = Number(totalRaw);
    if (!Number.isSafeInteger(total)) return { error: 'Итог — целое число рублей' };
    body.total = total;
  }
  return { body };
}

async function submitStatus(order) {
  const submit = $('f-submit');
  const error = $('f-error');
  if (!state.form.status || submit.disabled) return;
  const { body, error: invalid } = readStatusForm();
  if (invalid) {
    $('f-total').setAttribute('aria-invalid', 'true');
    error.textContent = invalid;
    return;
  }
  error.textContent = '';
  setBusy(submit, true, 'Сохраняем…');
  try {
    const { data } = await api.authed('PATCH', `v1/manager/orders/${encodeURIComponent(order.id)}`, body);
    applyUpdatedOrder(data);
    toast(`${str(data.number)}: ${str(data.statusLabel)}`);
    loadList({ silent: true });
  } catch (err) {
    if (err.handled) return;
    setBusy(submit, false);
    error.textContent = errorText(err);
    if (err.fields && err.fields.total) $('f-total').setAttribute('aria-invalid', 'true');
    if (err.status === 409) {
      // Статус успели сменить (другой менеджер / клиент отменил) — перечитываем заявку.
      toast(errorText(err));
      state.form.dirty = false;
      refetchSelected(order.id);
    }
  }
}

async function refetchSelected(id) {
  try {
    const { data } = await api.authed('GET', `v1/manager/orders/${encodeURIComponent(id)}`);
    if (state.selected && state.selected.id === id) applyUpdatedOrder(data);
  } catch (e) {
    if (!e.handled) toast(errorText(e));
  }
  loadList({ silent: true });
}

function applyUpdatedOrder(updated) {
  state.orders = state.orders.map((o) => (o.id === updated.id ? updated : o));
  state.selected = updated;
  state.form = { status: null, dirty: false };
  renderDetail();
  renderList();
  const heading = $('detail-num');
  if (heading) heading.focus({ preventScroll: true });
}

// ---------- Инициализация ----------
function bind() {
  $('phone-input').addEventListener('input', onPhoneInput);
  $('phone-form').addEventListener('submit', onPhoneSubmit);
  $('code-input').addEventListener('input', onCodeInput);
  $('code-form').addEventListener('submit', onCodeSubmit);
  $('resend-btn').addEventListener('click', onResend);
  $('change-phone').addEventListener('click', () => showLogin());
  $('denied-back').addEventListener('click', () => { state.login.phone = ''; showLogin(); });
  $('logout-btn').addEventListener('click', logout);
  $('refresh-btn').addEventListener('click', () => loadList());
  $('prev-page').addEventListener('click', () => goPage(-1));
  $('next-page').addEventListener('click', () => goPage(1));
  $('status-tabs').addEventListener('keydown', onTabsKeydown);
  $('search-input').addEventListener('input', onSearchInput);
  window.addEventListener('hashchange', onHashChange);
  window.addEventListener('popstate', onHashChange);
  document.addEventListener('visibilitychange', onVisibility);
  window.addEventListener('beforeunload', (e) => {
    if (state.form.dirty && state.form.status) {
      e.preventDefault();
      e.returnValue = '';
    }
  });
}

function init() {
  bind();
  const initialOrderId = hashOrderId();
  state.session = sessionStore.load();
  if (state.session && state.session.user.role === 'manager') {
    startApp(initialOrderId);
    return;
  }
  sessionStore.clear();
  state.session = null;
  showLogin();
}

init();
