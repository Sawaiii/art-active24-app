/*
 * HTTP-клиент API Арт-Актив для панели менеджера: конверт {success,data,error},
 * токены в sessionStorage, один refresh при 401 token_expired.
 */

const STORAGE_KEY = 'aa.manager.session';

const str = (v) => (typeof v === 'string' ? v : v === null || v === undefined ? '' : String(v));

export class ApiError extends Error {
  constructor(status, code, message, fields = {}, retryAfter = null) {
    super(message);
    this.status = status;
    this.code = code;
    this.fields = fields;
    this.retryAfter = retryAfter;
    /** true — ошибку уже обработали (переход на вход / «Нет доступа»), показывать не нужно. */
    this.handled = false;
  }
}

/** Человекочитаемый текст ошибки: сообщения по полям важнее общего. */
export function errorText(e) {
  if (!(e instanceof ApiError)) return 'Что-то пошло не так. Попробуйте ещё раз';
  const fieldMessages = Object.values(e.fields || {}).map(str).filter(Boolean);
  return fieldMessages.length ? fieldMessages.join('. ') : e.message;
}

/** Сессия живёт только в sessionStorage (закрыли вкладку — вышли). */
export const sessionStore = {
  load() {
    try {
      const s = JSON.parse(sessionStorage.getItem(STORAGE_KEY) || 'null');
      return s && typeof s.accessToken === 'string' && typeof s.refreshToken === 'string' && s.user ? s : null;
    } catch {
      return null;
    }
  },
  save(data) {
    const user = (data && data.user) || {};
    const s = {
      accessToken: str(data && data.accessToken),
      refreshToken: str(data && data.refreshToken),
      user: { id: user.id, phone: str(user.phone), role: str(user.role), name: str(user.name) },
    };
    try { sessionStorage.setItem(STORAGE_KEY, JSON.stringify(s)); } catch { /* приватный режим — живём в памяти */ }
    return s;
  },
  clear() {
    try { sessionStorage.removeItem(STORAGE_KEY); } catch { /* хранилище недоступно */ }
  },
};

/** База API = путь до /manager/ (напр. /api/ на сервере, / локально). */
export function apiBaseFromLocation(loc) {
  const m = /^(.*\/)manager(?:\/|$)/.exec(loc.pathname);
  return loc.origin + (m ? m[1] : '/');
}

/**
 * @param {{ base: string, getSession: () => any, setSession: (s: any) => void,
 *           onAuthLost: () => void, onForbidden: () => void }} opts
 */
export function createApi({ base, getSession, setSession, onAuthLost, onForbidden }) {
  async function raw(method, path, { body, token } = {}) {
    const headers = { Accept: 'application/json' };
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    if (token) headers.Authorization = `Bearer ${token}`;
    let res;
    try {
      res = await fetch(base + path, {
        method, headers, credentials: 'omit', cache: 'no-store',
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch {
      throw new ApiError(0, 'network', 'Нет связи с сервером. Проверьте интернет и попробуйте ещё раз');
    }
    if (res.status === 204) return { data: null, meta: null };
    let json = null;
    try { json = await res.json(); } catch { json = null; }
    if (!res.ok || !json || json.success !== true) {
      const err = json && json.error && typeof json.error === 'object' ? json.error : {};
      const fields = err.fields && typeof err.fields === 'object' ? err.fields : {};
      const retryAfter = Number(res.headers.get('Retry-After')) || null;
      throw new ApiError(res.status, str(err.code) || `http_${res.status}`, str(err.message) || `Ошибка сервера (${res.status})`, fields, retryAfter);
    }
    return { data: json.data, meta: json.meta || null };
  }

  const handled = (e) => {
    e.handled = true;
    return e;
  };

  function classify(e) {
    if (!(e instanceof ApiError)) return e;
    if (e.status === 401) {
      onAuthLost();
      return handled(e);
    }
    if (e.status === 403) {
      onForbidden();
      return handled(e);
    }
    return e;
  }

  let refreshing = null;
  function refresh() {
    if (!refreshing) {
      const s = getSession();
      refreshing = raw('POST', 'v1/auth/refresh', { body: { refreshToken: s ? s.refreshToken : '' } })
        .then(({ data }) => setSession(sessionStore.save(data)))
        .finally(() => { refreshing = null; });
    }
    return refreshing;
  }

  async function retryAfterRefresh(method, path, body) {
    try {
      await refresh();
    } catch (e) {
      onAuthLost();
      throw handled(e instanceof ApiError ? e : new ApiError(401, 'unauthorized', 'Сессия истекла'));
    }
    const s = getSession();
    if (!s || s.user.role !== 'manager') {
      onForbidden();
      throw handled(new ApiError(403, 'forbidden', 'Нет доступа'));
    }
    try {
      return await raw(method, path, { body, token: s.accessToken });
    } catch (e) {
      throw classify(e);
    }
  }

  /** Запрос с токеном: при 401 token_expired — один refresh и повтор, иначе на вход. */
  async function authed(method, path, body) {
    const s = getSession();
    if (!s) throw handled(new ApiError(401, 'unauthorized', 'Требуется вход'));
    try {
      return await raw(method, path, { body, token: s.accessToken });
    } catch (e) {
      if (e instanceof ApiError && e.status === 401 && e.code === 'token_expired') return retryAfterRefresh(method, path, body);
      throw classify(e);
    }
  }

  return { raw, authed };
}
