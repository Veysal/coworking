/* Общие утилиты: REST-клиент, авторизация, навигация, уведомления */
const API = '/api';

const store = {
  get token() { return localStorage.getItem('token'); },
  get user() { try { return JSON.parse(localStorage.getItem('user')); } catch { return null; } },
  set(token, user) { localStorage.setItem('token', token); localStorage.setItem('user', JSON.stringify(user)); },
  clear() { localStorage.removeItem('token'); localStorage.removeItem('user'); },
};

async function api(path, { method = 'GET', body, params } = {}) {
  const url = new URL(API + path, location.origin);
  for (const [k, v] of Object.entries(params || {})) if (v !== '' && v != null) url.searchParams.set(k, v);
  const headers = {};
  if (body) headers['Content-Type'] = 'application/json';
  if (store.token) headers['Authorization'] = 'Bearer ' + store.token;
  const res = await fetch(url, { method, headers, body: body ? JSON.stringify(body) : undefined });
  if (res.status === 204) return null;
  let data = null;
  try { data = await res.json(); } catch { /* пустое тело */ }
  if (!res.ok) {
    let msg = data?.detail ?? res.statusText;
    if (Array.isArray(msg)) msg = msg.map(e => e.msg).join('; ');
    if (res.status === 401 && store.token) store.clear();
    throw Object.assign(new Error(msg), { status: res.status });
  }
  return data;
}

const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
const fmtTime = iso => new Date(iso).toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit' });
const fmtDate = iso => new Date(iso).toLocaleDateString('ru-RU', { day: 'numeric', month: 'short', year: 'numeric' });
const fmtDateTime = iso => `${fmtDate(iso)}, ${fmtTime(iso)}`;
const todayStr = (d = new Date()) => new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
const STATUS = { pending: 'Ожидает', confirmed: 'Подтверждена', cancelled: 'Отменена' };
const debounce = (fn, ms = 300) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };

function toast(msg, type = 'ok') {
  let box = document.getElementById('toasts');
  if (!box) { box = document.createElement('div'); box.id = 'toasts'; document.body.append(box); }
  const el = document.createElement('div');
  el.className = 'toast ' + (type === 'err' ? 'err' : '');
  el.textContent = msg;
  box.append(el);
  setTimeout(() => el.remove(), 4500);
}

function renderNav(active) {
  const u = store.user;
  const link = (href, text, key) => `<a href="${href}" class="${active === key ? 'active' : ''}">${text}</a>`;
  document.getElementById('nav').innerHTML = `
    <header class="top"><div class="wrap">
      <a class="brand" href="index.html">Коворкинг</a>
      <nav>
        ${link('index.html', 'Комнаты', 'rooms')}
        ${u ? link('my.html', u.role === 'admin' ? 'Все брони' : 'Мои брони', 'my') : ''}
        ${u?.role === 'admin' ? link('admin.html', 'Админка', 'admin') : ''}
        ${u ? `<span class="who">${esc(u.name)}</span><a href="#" id="logout">Выйти</a>` : link('login.html', 'Войти', 'login')}
      </nav>
    </div></header>`;
  document.getElementById('logout')?.addEventListener('click', async e => {
    e.preventDefault();
    try { await api('/auth/logout', { method: 'POST' }); } catch { /* токен уже недействителен */ }
    store.clear(); location.href = 'index.html';
  });
}

function requireLogin() {
  if (!store.token) { location.href = 'login.html?next=' + encodeURIComponent(location.pathname.split('/').pop() + location.search); return false; }
  return true;
}
