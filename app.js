/* ============================================================
   NovaPOS — Invoice & Expense Manager  ·  app.js
   Pure vanilla JS. Local-first (localStorage) + Firebase
   (Firestore) cloud sync. No server of your own needed —
   it even runs on GitHub Pages.
   ============================================================ */
'use strict';

/* ============================================================
   CLOUD SYNC (Firebase Firestore)
   ------------------------------------------------------------
   firebase-init.js is an ES module that sets up Firestore and
   exposes `window.FBSync`. The app uses it to read/write a single
   snapshot doc (appdata/snapshot). Both the web app and a future
   Flutter app will share this doc. If Firebase fails to load,
   the app runs 100% offline (localStorage).
   ============================================================ */
const CLOUD_SYNC = {
  backend: 'firebase',
  auto: true                                  // auto push after every change
};

/* The Firebase module loads lazily; if it is not ready before app.js,
   wait a little (polling), otherwise return null. */
function fbReady(timeout = 8000) {
  return new Promise((resolve) => {
    if (window.FBSync) return resolve(window.FBSync);
    const t0 = Date.now();
    const iv = setInterval(() => {
      if (window.FBSync) { clearInterval(iv); resolve(window.FBSync); }
      else if (Date.now() - t0 > timeout) { clearInterval(iv); resolve(null); }
    }, 60);
  });
}

/* ---------------- utils ---------------- */
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const debounce = (fn, ms) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };
const pad2 = n => String(n).padStart(2, '0');
const todayISO = () => { const d = new Date(); return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`; };
const monthKey = ts => { const d = new Date(ts); return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}`; };
const fmtDate = ts => new Date(ts).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' });
const fmtDateSlash = ts => { const d = new Date(ts); return `${pad2(d.getDate())}/${pad2(d.getMonth() + 1)}/${d.getFullYear()}`; };
const fmtDateTime = ts => new Date(ts).toLocaleString('en-GB', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
const monthLabel = mk => new Date(mk + '-01T00:00:00').toLocaleDateString('en-GB', { month: 'long', year: 'numeric' });

/* ---------------- store ---------------- */
const K = {
  settings: 'nv_settings', invoices: 'nv_invoices', expenses: 'nv_expenses',
  reminders: 'nv_reminders', notes: 'nv_notes', history: 'nv_history',
  board: 'nv_board', notified: 'nv_notified', clients: 'nv_clients'
};
const load = (k, d) => { try { const v = JSON.parse(localStorage.getItem(k)); return v ?? d; } catch { return d; } };
let syncReady = false;
const save = (k, v) => {
  localStorage.setItem(k, JSON.stringify(v));
  if (k !== K.notified) {
    localStorage.setItem('nv_savedAt', String(Date.now()));
    if (syncReady && CLOUD_SYNC.auto) schedulePush();
  }
};

const DEFAULT_SETTINGS = {
  businessName: 'ElectroPowerInt', email: '', phone: '', address: '', website: '',
  currency: 'Rs', prefix: 'INV',
  signName: '', logo: '',
  invoiceRows: 7
};
const DASH = '------';
function invoiceRowCount() {
  const n = Number(settings.invoiceRows);
  return Number.isFinite(n) ? Math.max(7, Math.min(30, Math.round(n))) : 7;
}
function dashCell(v) {
  const s = String(v ?? '').trim();
  return s ? s : DASH;
}
function invoiceTableRows(inv) {
  const items = (inv.items || []).filter(it => String(it.name || '').trim());
  const n = Math.max(invoiceRowCount(), items.length);
  const rows = [];
  for (let i = 0; i < n; i++) {
    const it = items[i];
    if (!it) {
      rows.push({ name: DASH, qty: DASH, price: DASH, total: DASH, empty: true });
      continue;
    }
    const qty = Number(it.qty);
    const price = Number(it.price);
    const hasQty = it.qty !== '' && it.qty != null && Number.isFinite(qty);
    const hasPrice = it.price !== '' && it.price != null && Number.isFinite(price);
    rows.push({
      name: dashCell(it.name),
      qty: hasQty ? String(qty) : DASH,
      price: hasPrice ? money(price) : DASH,
      total: hasQty && hasPrice ? money(qty * price) : DASH,
      empty: false
    });
  }
  return rows;
}
let settings = { ...DEFAULT_SETTINGS, ...load(K.settings, {}) };
const saveSettings = () => save(K.settings, settings);
const money = n => `${settings.currency} ${Number(n || 0).toLocaleString(undefined, { maximumFractionDigits: 2 })}`;
const rs = n => `${settings.currency}.${Math.round(Number(n) || 0).toLocaleString()}/-`;

function invoicePaidInfo(inv) {
  const t = invoiceTotals(inv);
  let paid = Number(inv.paidAmount);
  if (isNaN(paid) || paid === undefined || paid === null) {
    paid = (inv.status === 'paid') ? t.total : 0;
  }
  paid = Math.max(0, Math.min(paid, t.total));
  const isFullyPaid = (paid >= (t.total - 0.01) && t.total > 0) || inv.status === 'paid';
  const isPartiallyPaid = paid > 0.001 && !isFullyPaid;
  const remaining = Math.max(0, t.total - paid);
  const isOverdueOneWeek = !isFullyPaid && (Date.now() - (Number(inv.createdAt) || Date.now())) >= (7 * 86400 * 1000);
  const status = isFullyPaid ? 'paid' : (isPartiallyPaid ? 'partial' : 'unpaid');
  return { paid, remaining, isFullyPaid, isPartiallyPaid, isOverdueOneWeek, status, total: t.total, subtotal: t.subtotal, discount: t.discount };
}

const getInvoices = () => load(K.invoices, []).map(i => {
  const p = invoicePaidInfo(i);
  return { ...i, paidAmount: p.paid, status: p.status };
});
const setInvoices = v => save(K.invoices, v);
const STATUS_RANK = { paid: 0, partial: 1, unpaid: 2 };

function setInvoiceStatus(id, status) {
  const list = load(K.invoices, []);
  const i = list.findIndex(x => x.id === id);
  if (i < 0) return null;
  const t = invoiceTotals(list[i]);
  const next = { ...list[i], status, paidAmount: status === 'paid' ? t.total : 0, updatedAt: Date.now() };
  if (status === 'paid') next.paidAt = Date.now(); else delete next.paidAt;
  list[i] = next;
  setInvoices(list);
  logEvent('invoice', `Invoice ${next.number} marked ${status}`);
  updateReminderPill();
  return next;
}

// Adds to what was already received; the status flips itself once the total is covered.
function applyPayment(id, amt) {
  const list = load(K.invoices, []);
  const i = list.findIndex(x => x.id === id);
  if (i < 0) return null;
  const t = invoiceTotals(list[i]).total;
  const paid = Math.max(0, Math.min(t, (Number(list[i].paidAmount) || 0) + Number(amt)));
  const status = paid >= t - 0.01 && t > 0 ? 'paid' : paid > 0 ? 'partial' : 'unpaid';
  const next = { ...list[i], paidAmount: paid, status, updatedAt: Date.now() };
  if (status === 'paid') next.paidAt = Date.now(); else delete next.paidAt;
  list[i] = next;
  setInvoices(list);
  logEvent('invoice', `${money(amt)} payment recorded for ${next.number} (${status})`);
  updateReminderPill();
  return next;
}

const invoiceStatusBadge = inv => {
  if (inv.status === 'paid') return '<span class="badge b-paid">paid</span>';
  if (inv.status === 'partial') return '<span class="badge b-due">partial</span>';
  return `<span class="badge b-unpaid">${invoicePaidInfo(inv).isOverdueOneWeek ? 'overdue' : 'unpaid'}</span>`;
};

/* Invoices raised a week ago that are still not fully paid — unpaid or partial. */
const OVERDUE_DAYS = 7;
function outstandingInvoices() {
  const cut = Date.now() - OVERDUE_DAYS * 864e5;
  return getInvoices()
    .filter(i => i.status !== 'paid' && Number(i.createdAt) <= cut)
    .map(i => {
      const p = invoicePaidInfo(i);
      return { ...i, due: p.remaining, paid: p.paid, total: p.total, status: p.status, days: Math.floor((Date.now() - Number(i.createdAt)) / 864e5) };
    })
    .sort((a, b) => b.due - a.due);
}
const outstandingTotal = list => list.reduce((s, i) => s + i.due, 0);

function remindOnWhatsApp(inv) {
  const cleanPhone = (inv.clientPhone || '').replace(/[^0-9]/g, '');
  const text = `Dear ${inv.clientName || 'Client'}, this is a gentle reminder for invoice ${inv.number} of ${money(inv.total)}. An amount of ${money(inv.due)} is still outstanding (${inv.days} days). Kindly clear it at your convenience. Thank you.`;
  const url = cleanPhone
    ? `https://wa.me/${cleanPhone}?text=${encodeURIComponent(text)}`
    : `https://wa.me/?text=${encodeURIComponent(text)}`;
  window.open(url, '_blank');
  logEvent('invoice', `Outstanding reminder sent for ${inv.number}`);
  toast('WhatsApp opened with the reminder text — please send it', 'info');
}

function sortInvoices(list, mode) {
  const total = i => invoiceTotals(i).total;
  const byNew = (a, b) => b.createdAt - a.createdAt;
  const cmp = {
    old: (a, b) => a.createdAt - b.createdAt,
    high: (a, b) => total(b) - total(a),
    low: (a, b) => total(a) - total(b),
    paidfirst: (a, b) => STATUS_RANK[a.status] - STATUS_RANK[b.status] || byNew(a, b),
    unpaidfirst: (a, b) => STATUS_RANK[b.status] - STATUS_RANK[a.status] || byNew(a, b),
    new: byNew
  }[mode] || byNew;
  return [...list].sort(cmp);
}

const getExpenses = () => load(K.expenses, []);
const setExpenses = v => save(K.expenses, v);
const getReminders = () => load(K.reminders, []);
const setReminders = v => save(K.reminders, v);
const getNotes = () => load(K.notes, []);
const setNotes = v => save(K.notes, v);
const getClients = () => load(K.clients, []);
const setClients = v => save(K.clients, v);
function upsertClient(d) {
  if (!d.clientName) return;
  const list = getClients();
  const i = list.findIndex(c => (c.name || '').toLowerCase() === d.clientName.toLowerCase());
  const rec = { name: d.clientName, phone: d.clientPhone || '', email: d.clientEmail || '', address: d.clientAddress || '' };
  if (i >= 0) list[i] = { ...list[i], ...rec }; else list.unshift(rec);
  setClients(list.slice(0, 200));
}
const getHistory = () => load(K.history, []);

function logEvent(type, msg) {
  const h = getHistory();
  h.unshift({ id: uid(), type, msg, at: Date.now() });
  save(K.history, h.slice(0, 400));
}

/* ---------------- invoice math ---------------- */
function invoiceTotals(inv) {
  let subtotal = 0;
  (inv.items || []).forEach(it => {
    subtotal += (Number(it.qty) || 0) * (Number(it.price) || 0);
  });
  const raw = Number(inv.discount) || 0;
  const discount = (inv.discountType === 'percent') ? subtotal * raw / 100 : raw;
  return { subtotal, discount, total: Math.max(0, subtotal - discount) };
}
function nextInvoiceNumber() {
  const list = getInvoices();
  const re = new RegExp('^' + settings.prefix.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '-(\\d+)$');
  const max = list.reduce((m, i) => { const mm = re.exec(i.number); return mm ? Math.max(m, +mm[1]) : m; }, 0);
  return `${settings.prefix}-${String(max + 1).padStart(4, '0')}`;
}

/* ---------------- toast + modal ---------------- */
function toast(msg, type = 'ok') {
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.innerHTML = `<span class="tdot"></span><span>${esc(msg)}</span>`;
  $('#toasts').appendChild(el);
  setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 260); }, 3200);
}
let modalResolve = null;
function confirmBox(title, text, okLabel = 'Delete') {
  return new Promise(res => {
    resetModal();
    modalResolve = res;
    $('#modalTitle').textContent = title;
    $('#modalText').textContent = text;
    $('#modalOk').textContent = okLabel;
    $('#modalRoot').hidden = false;
  });
}
function closeModal(v) { $('#modalRoot').hidden = true; if (modalResolve) { modalResolve(v); modalResolve = null; } }
$('#modalOk').addEventListener('click', () => closeModal(true));
$('#modalCancel').addEventListener('click', () => closeModal(false));
$('#modalBackdrop').addEventListener('click', () => closeModal(false));

/* payment picker: full / half / a partial amount instead of a bare number box */
let payResolve = null, payCtx = null;
function openPayModal(inv) {
  return new Promise(res => {
    payResolve = res;
    payCtx = invoicePaidInfo(inv);
    $('#payTitle').textContent = `Payment for ${inv.number}`;
    $('#paySub').innerHTML = `${esc(inv.clientName)} &nbsp;·&nbsp; Total <b>${money(payCtx.total)}</b> &nbsp;·&nbsp; received <b>${money(payCtx.paid)}</b> &nbsp;·&nbsp; remaining <b>${money(payCtx.remaining)}</b>`;
    $('#payOpts').hidden = false;
    $('#payCustom').hidden = true;
    $('#payRoot').hidden = false;
  });
}
function closePay(v) {
  $('#payRoot').hidden = true;
  const r = payResolve; payResolve = null; payCtx = null;
  if (r) r(v);
}
$('#payBackdrop').addEventListener('click', () => closePay(null));
$('#payCancel').addEventListener('click', () => closePay(null));
$('#payOpts').addEventListener('click', e => {
  const b = e.target.closest('[data-kind]');
  if (!b || !payCtx) return;
  if (b.dataset.kind === 'full') return closePay({ kind: 'full', amt: payCtx.remaining });
  if (b.dataset.kind === 'half') return closePay({ kind: 'half', amt: Math.round(payCtx.total / 2) });
  $('#payOpts').hidden = true;
  $('#payCustom').hidden = false;
  $('#payHint').textContent = `Partial must stay below the invoice value of ${money(payCtx.total)}`;
  $('#payAmt').value = '';
  $('#payAmt').focus();
});
$('#payGo').addEventListener('click', () => {
  if (!payCtx) return;
  const v = Number($('#payAmt').value);
  if (!(v > 0)) return toast('Enter the payment amount', 'err');
  if (v >= payCtx.total) return toast('That is not a partial amount — use Full payment', 'err');
  closePay({ kind: 'partial', amt: v });
});
$('#payAmt').addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); $('#payGo').click(); } });

/* ---------------- cloud sync (Firebase Firestore) ---------------- */
let cloudOk = false;
let lastSyncAt = Number(localStorage.getItem('nv_lastSync') || 0);
const markSynced = () => { lastSyncAt = Date.now(); localStorage.setItem('nv_lastSync', String(lastSyncAt)); };
const localSavedAt = () => Number(localStorage.getItem('nv_savedAt') || 0);
function allData() {
  return {
    settings,
    invoices: getInvoices(), expenses: getExpenses(),
    reminders: getReminders(), notes: getNotes(),
    history: getHistory(), board: load(K.board, null), clients: getClients()
  };
}
function applyData(d) {
  if (!d) return;
  if (d.settings) { settings = { ...DEFAULT_SETTINGS, ...d.settings }; saveSettings(); }
  if (d.invoices) save(K.invoices, d.invoices);
  if (d.expenses) save(K.expenses, d.expenses);
  if (d.reminders) save(K.reminders, d.reminders);
  if (d.notes) save(K.notes, d.notes);
  if (d.history) save(K.history, d.history);
  if (d.clients) save(K.clients, d.clients);
  if (d.board != null) save(K.board, d.board);
}
async function pushToCloud(silent) {
  const fb = await fbReady();
  if (!fb) {
    cloudOk = false; refreshSidebarBiz();
    if (!silent) toast('Firebase is not ready yet', 'err');
    return false;
  }
  try {
    // JSON round-trip: Firestore rejects undefined values
    const payload = JSON.parse(JSON.stringify({ savedAt: localSavedAt(), data: allData() }));
    await fb.set(payload);
    cloudOk = true; markSynced(); refreshSidebarBiz();
    if (!silent) toast('Firebase sync complete');
    return true;
  } catch (e) {
    cloudOk = false; refreshSidebarBiz();
    if (!silent) toast('Sync failed: ' + e.message, 'err');
    return false;
  }
}
async function pullFromCloud(silent) {
  const fb = await fbReady();
  if (!fb) { cloudOk = false; refreshSidebarBiz(); return false; }
  try {
    const snap = await fb.get();
    cloudOk = true; markSynced();
    if (snap && snap.data && Number(snap.savedAt || 0) > localSavedAt()) {
      applyData(snap.data);
      localStorage.setItem('nv_savedAt', String(snap.savedAt));
      refreshSidebarBiz(); render();
      if (!silent) toast('Data loaded from cloud');
      return true;
    }
    refreshSidebarBiz();
    return false;
  } catch {
    cloudOk = false; refreshSidebarBiz();
    return false;
  }
}
const schedulePush = debounce(() => pushToCloud(true), 2500);

/* ---------------- icons ---------------- */
const IC = {
  plus: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>',
  trash: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 6h18M8 6V4a1 1 0 011-1h6a1 1 0 011 1v2M19 6l-1 14a2 2 0 01-2 2H8a2 2 0 01-2-2L5 6"/></svg>',
  edit: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 013 3L7 19l-4 1 1-4z"/></svg>',
  copy: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1"/></svg>',
  pdf: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4"/><path d="M7 10l5 5 5-5M12 15V3"/></svg>',
  share: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="M8.6 13.5l6.8 4M15.4 6.5l-6.8 4"/></svg>',
  wa: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2a10 10 0 00-8.6 15.1L2 22l5-1.3A10 10 0 1012 2zm5.4 14.1c-.2.7-1.3 1.3-1.9 1.4-.5.1-1.1.1-1.8-.1-.4-.1-1-.3-1.7-.6-3-1.3-4.9-4.3-5.1-4.5-.1-.2-1.2-1.6-1.2-3.1s.8-2.2 1-2.5c.3-.3.6-.4.8-.4h.6c.2 0 .4 0 .6.5s.8 1.9.8 2c.1.1.1.3 0 .5-.3.6-.7.9-.5 1.2.7 1.2 1.6 2 2.8 2.6.3.2.5.1.7-.1l.9-1.1c.2-.3.4-.2.7-.1l2 1c.3.1.5.2.6.4 0 .1 0 .7-.3 1.3z"/></svg>',
  mail: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="2" y="4" width="20" height="16" rx="2"/><path d="M22 6l-10 7L2 6"/></svg>',
  home: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 10l9-7 9 7v10a1 1 0 01-1 1h-5v-7h-6v7H4a1 1 0 01-1-1z"/></svg>',
  globe: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a15 15 0 010 18M12 3a15 15 0 000 18"/></svg>',
  phone: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M22 16.9v3a2 2 0 01-2.2 2 19.8 19.8 0 01-8.6-3.1 19.5 19.5 0 01-6-6A19.8 19.8 0 012.1 4.2 2 2 0 014.1 2h3a2 2 0 012 1.7c.1 1 .4 2 .7 2.9a2 2 0 01-.5 2.1L8 10a16 16 0 006 6l1.3-1.3a2 2 0 012.1-.5c.9.3 1.9.6 2.9.7a2 2 0 011.7 2z"/></svg>',
  check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M20 6L9 17l-5-5"/></svg>',
  search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>',
  cash: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="2" y="6" width="20" height="12" rx="2"/><circle cx="12" cy="12" r="3"/></svg>',
  clock: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
  trend: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 3v18h18"/><path d="M19 9l-5 5-4-4-3 3"/></svg>',
  wallet: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M20 7H4a2 2 0 00-2 2v9a2 2 0 002 2h16a2 2 0 002-2V9a2 2 0 00-2-2z"/><path d="M16 7V5a2 2 0 00-2-2H6a2 2 0 00-2 2v2M16 13h3"/></svg>',
  doc: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 2h12a1 1 0 011 1v19l-3-2-3 2-3-2-3 2V3a1 1 0 011-1z"/><path d="M9 7h6M9 11h6"/></svg>'
};

/* ---------------- charts (pure SVG/HTML) ---------------- */
function barsChart(days) {
  const cols = days.map(d => `
    <div class="col">
      <div class="bar ${d.hi ? 'hi' : ''}" style="height:${d.pct}%" data-val="${esc(d.val)}"></div>
      <small>${esc(d.label)}</small>
    </div>`).join('');
  return `<div class="chart-bars">${cols}</div>`;
}
function donutChart(parts, size = 150) {
  const total = parts.reduce((s, p) => s + p.value, 0);
  if (!total) return `<div class="empty small muted" style="padding:1rem">No data yet</div>`;
  const R = 42, C = 2 * Math.PI * R;
  let off = 0;
  const circles = parts.map(p => {
    const frac = p.value / total;
    const seg = `<circle cx="50" cy="50" r="${R}" fill="none" stroke="${p.color}" stroke-width="16"
      stroke-dasharray="${(frac * C).toFixed(2)} ${C.toFixed(2)}" stroke-dashoffset="${(-off * C).toFixed(2)}"
      transform="rotate(-90 50 50)"/>`;
    off += frac;
    return seg;
  }).join('');
  return `<svg width="${size}" height="${size}" viewBox="0 0 100 100">${circles}
    <text x="50" y="47" text-anchor="middle" font-size="11" font-weight="800" fill="#0f172a" font-family="Sora,sans-serif">${parts.length}</text>
    <text x="50" y="60" text-anchor="middle" font-size="7" fill="#64748b">categories</text></svg>`;
}

/* ---------------- PDF ---------------- */
/* ---------- New invoice paper (shared by on-screen preview + live preview) ---------- */
function invoicePaperHTML(inv) {
  const t = invoiceTotals(inv);
  const biz = settings;
  const clLines = [inv.clientName, inv.clientPhone, ...(inv.clientAddress || '').split('\n').filter(Boolean), inv.clientEmail].filter(Boolean);
  const fromLines = [biz.businessName, ...(biz.address || '').split('\n').filter(Boolean), biz.phone, biz.email].filter(Boolean);
  const rows = invoiceTableRows(inv).map(it => `<tr class="${it.empty ? 'p2-empty' : ''}">
      <td class="col-item">${esc(it.name)}</td>
      <td class="col-qty">${esc(it.qty)}</td>
      <td class="col-price">${esc(it.price)}</td>
      <td class="col-total">${esc(it.total)}</td>
    </tr>`);
  return `
  <div class="paper2"><div class="p2-sheet">
    <div class="p2-header-row">
      <div class="p2-logo-box">
        ${biz.logo ? `<img src="${biz.logo}" alt="Logo" class="p2-user-logo" />` : `
        <div class="p2-hexagon-logo">
          <svg viewBox="0 0 100 115" width="46" height="52">
            <polygon points="50,2 96,28 96,87 50,113 4,87 4,28" fill="#181818" />
            <text x="36" y="52" fill="#fff" font-family="'Playfair Display', serif" font-size="28" font-style="italic">J</text>
            <line x1="42" y1="58" x2="62" y2="40" stroke="#fff" stroke-width="3" />
            <text x="56" y="80" fill="#fff" font-family="'Playfair Display', serif" font-size="24">S</text>
          </svg>
        </div>`}
      </div>
      <div class="p2-title-serif">Invoice</div>
    </div>

    <div class="p2-info-row">
      <div class="p2-billed-col">
        <div class="p2-col-label">Billed to:</div>
        <div class="p2-billed-info">
          ${clLines.length ? clLines.map((l, i) => i === 0 ? `<div class="p2-client-name">${esc(l)}</div>` : `<div class="p2-client-line">${esc(l)}</div>`).join('') : '<div class="p2-dim">Client name…</div>'}
        </div>
      </div>
      <div class="p2-meta-col">
        <div class="p2-inv-num">Invoice No. ${esc(inv.number || '12345')}</div>
        <div class="p2-inv-date">${fmtDateSlash(inv.createdAt || Date.now())}</div>
      </div>
    </div>

    <table class="p2-tbl">
      <thead>
        <tr>
          <th class="col-item">Item</th>
          <th class="col-qty">Quantity</th>
          <th class="col-price">Unit Price</th>
          <th class="col-total">Total</th>
        </tr>
      </thead>
      <tbody>${rows.join('')}</tbody>
    </table>

    <div class="p2-summary-wrap">
      <div class="p2-subtotal-block">
        <div class="p2-sum-row">
          <span class="p2-sum-lbl">Subtotal</span>
          <span class="p2-sum-val">${money(t.subtotal)}</span>
        </div>
        ${t.discount ? `<div class="p2-sum-row"><span class="p2-sum-lbl">Discount</span><span class="p2-sum-val">- ${money(t.discount)}</span></div>` : ''}
        <div class="p2-total-badge">
          <span class="p2-badge-lbl">Total</span>
          <span class="p2-badge-val">${money(t.total)}</span>
        </div>
      </div>
    </div>

    <div class="p2-bottom-area">
      <div class="p2-thankyou-script">Thank You!</div>
      
      <div class="p2-bottom-grid">
        <div class="p2-pay-info">
          <div class="p2-pay-lbl">Other Information:</div>
          ${inv.notes ? `<div class="p2-pay-detail">${esc(inv.notes)}</div>` : `
          <div class="p2-pay-detail">${esc(biz.businessName || 'Business')}</div>
          ${biz.phone ? `<div class="p2-pay-detail">Contact: ${esc(biz.phone)}</div>` : ''}
          ${biz.email ? `<div class="p2-pay-detail">Email: ${esc(biz.email)}</div>` : ''}
          `}
        </div>
        <div class="p2-biz-signature-col">
          <div class="p2-biz-title-serif">${esc(biz.signName || biz.businessName || 'Juliana Silva')}</div>
          <div class="p2-biz-address">Proprietor</div>
        </div>
      </div>
    </div>
  </div></div>`;
}

function fitPaperSheets(root = document) {
  root.querySelectorAll('.paper2').forEach(paper => {
    const sheet = paper.firstElementChild;
    if (!sheet || !sheet.classList.contains('p2-sheet')) return;
    if (!paper.closest('.p2-preview-wrap')) {
      // In full invoice detail view, ensure complete natural visibility without cutting bottom
      sheet.style.cssText = '';
      paper.style.aspectRatio = 'auto';
      paper.style.overflow = 'visible';
      return;
    }
    sheet.style.cssText = '';
    paper.style.cssText = '';
    paper.classList.remove('multi');
    const ph = paper.clientHeight;
    if (!ph) return;
    // the miniature live preview is already drawn below print size, so it may
    // squish further before spilling; a full-size sheet stops at print legibility
    const FLOOR = paper.closest('.p2-preview-wrap') ? 0.28 : 0.55;
    let s = 1, e = 0;
    const base = sheet.scrollHeight;
    if (!base) return;
    if (base <= ph) {
      // light invoice: spread the spare height over the 5 section gaps
      e = Math.min(ph * 0.045, (ph - base) / 5 * 0.85);
    }
    const apply = () => {
      sheet.style.width = s < 1 ? (100 / s).toFixed(3) + '%' : '';
      sheet.style.transform = s < 1 ? `scale(${s.toFixed(5)})` : '';
      sheet.style.setProperty('--e', e.toFixed(2) + 'px');
    };
    apply();
    // a shrink widens the sheet, which re-wraps text and changes the height,
    // so re-measure and settle instead of trusting the first pass
    for (let pass = 0; pass < 3; pass++) {
      const sh = sheet.scrollHeight;
      const ns = sh * FLOOR > ph ? FLOOR : Math.min(1, ph / sh);
      if (Math.abs(ns - s) < 0.002) break;
      s = ns;
      apply();
    }
    if (s <= FLOOR) {
      // too much for one A4 at legible sizes: show stacked pages like the PDF
      const pages = Math.max(2, Math.ceil(sheet.scrollHeight * s / ph));
      paper.classList.add('multi');
      paper.style.setProperty('--pages', pages);
      paper.style.aspectRatio = 'auto';
      paper.style.height = (ph * pages) + 'px';
    }
  });
}

function buildInvoicePDF(inv, k, e = 0) {
  const { jsPDF } = window.jspdf;
  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  const W = doc.internal.pageSize.getWidth();
  const M = 42, L = M, R = W - M;
  const t = invoiceTotals(inv);

  // Top header: Logo (left) and 'Invoice' in serif (right)
  const topY = M + 10 * k;
  let logoH = 46 * k;
  if (settings.logo) {
    try {
      const pr = doc.getImageProperties(settings.logo);
      const sc = Math.min((60 * k) / pr.width, logoH / pr.height);
      doc.addImage(settings.logo, pr.fileType === 'JPEG' ? 'JPEG' : 'PNG', L, topY, pr.width * sc, pr.height * sc);
    } catch (err) {
      // Fallback text if logo fails
      doc.setFont('times', 'bold');
      doc.setFontSize(18 * k);
      doc.setTextColor(20, 20, 20);
      doc.text(settings.businessName || 'Business', L, topY + 24 * k);
    }
  } else {
    // Draw modern dark hexagon emblem with J/S like the template
    const hx = L + 20 * k, hy = topY + 22 * k, hr = 20 * k;
    doc.setFillColor(24, 24, 24);
    // Draw hexagon polygon
    const pts = [];
    for (let i = 0; i < 6; i++) {
      const angle = (Math.PI / 3) * i + Math.PI / 6;
      pts.push([hx + hr * Math.cos(angle), hy + hr * Math.sin(angle)]);
    }
    doc.polygon(pts, 'F');
    doc.setTextColor(255, 255, 255);
    doc.setFont('times', 'italic');
    doc.setFontSize(13 * k);
    doc.text('J', hx - 5 * k, hy - 1 * k);
    doc.setDrawColor(255, 255, 255);
    doc.setLineWidth(1 * k);
    doc.line(hx - 2 * k, hy + 2 * k, hx + 5 * k, hy - 4 * k);
    doc.setFont('times', 'normal');
    doc.setFontSize(11 * k);
    doc.text('S', hx + 1 * k, hy + 9 * k);
  }

  // "Invoice" serif title
  doc.setFont('times', 'normal');
  doc.setFontSize(36 * k);
  doc.setTextColor(20, 20, 20);
  doc.text('Invoice', R, topY + 30 * k, { align: 'right' });

  // Billed to (left) and Invoice No / Date (right)
  let infoY = topY + 58 * k + e;
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(9.5 * k);
  doc.setTextColor(20, 20, 20);
  doc.text('Billed to:', L, infoY);

  doc.setFont('helvetica', 'normal');
  doc.setFontSize(9 * k);
  doc.text(`Invoice No. ${inv.number || '12345'}`, R, infoY, { align: 'right' });
  doc.setTextColor(90, 90, 90);
  doc.text(fmtDateSlash(inv.createdAt || Date.now()), R, infoY + 14 * k, { align: 'right' });

  const clLines = [inv.clientName, inv.clientPhone, ...(inv.clientAddress || '').split('\n').filter(Boolean), inv.clientEmail].filter(Boolean);
  let by = infoY + 15 * k;
  clLines.forEach((ln, i) => {
    if (i === 0) {
      doc.setFont('helvetica', 'bold');
      doc.setTextColor(24, 24, 24);
      doc.setFontSize(9 * k);
    } else {
      doc.setFont('helvetica', 'normal');
      doc.setTextColor(60, 60, 60);
      doc.setFontSize(8.5 * k);
    }
    doc.text(ln, L, by);
    by += 12 * k;
  });

  const body = invoiceTableRows(inv).map(it => [it.name, it.qty, it.price, it.total]);
  const footerH = 175 * k + e;
  doc.autoTable({
    startY: Math.max(by, infoY + 36 * k) + 16 * k + e,
    head: [['Item', 'Quantity', 'Unit Price', 'Total']],
    body,
    theme: 'plain',
    styles: {
      font: 'helvetica',
      fontSize: 9 * k,
      textColor: 30,
      halign: 'left',
      cellPadding: { top: 8 * k, bottom: 8 * k, left: 4, right: 4 },
      lineWidth: { bottom: 0.6 },
      lineColor: [200, 200, 200]
    },
    headStyles: {
      font: 'helvetica',
      fontStyle: 'bold',
      fontSize: 9.5 * k,
      textColor: 16,
      halign: 'left',
      lineWidth: { bottom: 1.8 },
      lineColor: [24, 24, 24]
    },
    columnStyles: {
      1: { cellWidth: 78, halign: 'center' },
      2: { cellWidth: 90, halign: 'right' },
      3: { cellWidth: 90, halign: 'right' }
    },
    didParseCell: (data) => {
      if (data.section === 'body' && String(data.cell.raw) === DASH) data.cell.styles.textColor = [160, 160, 160];
    },
    margin: { left: L, right: M, bottom: footerH }
  });
  const tableEnd = doc.lastAutoTable.finalY;

  // Summary / Subtotal / Total block
  const tw = 220, tx = R - tw;
  let ty = tableEnd + 16 * k + e;
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(9 * k);
  doc.setTextColor(24, 24, 24);
  doc.text('Subtotal', tx + 8 * k, ty);
  doc.text(money(t.subtotal), R - 8 * k, ty, { align: 'right' });
  ty += 16 * k;

  if (t.discount) {
    doc.text('Discount', tx + 8 * k, ty);
    doc.text('- ' + money(t.discount), R - 8 * k, ty, { align: 'right' });
    ty += 16 * k;
  }

  // Dark Total banner
  const badgeH = 24 * k;
  doc.setFillColor(24, 24, 24);
  doc.rect(tx, ty - 3 * k, tw, badgeH, 'F');
  doc.setTextColor(255, 255, 255);
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(11 * k);
  doc.text('Total', tx + 12 * k, ty + 13 * k);
  doc.text(money(t.total), R - 12 * k, ty + 13 * k, { align: 'right' });
  ty += badgeH + 20 * k;

  // Bottom Area: "Thank You!" script + Payment Info + Business signature
  let py = ty + 10 * k + e;
  doc.setFont('times', 'italic');
  doc.setFontSize(26 * k);
  doc.setTextColor(24, 24, 24);
  doc.text('Thank You!', L, py);

  let fy = py + 26 * k;
  // Left: Payment Information
  doc.setFont('helvetica', 'bold');
  doc.setFontSize(9 * k);
  doc.setTextColor(24, 24, 24);
  doc.text('Payment Information', L, fy);
  let pfy = fy + 13 * k;
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8 * k);
  doc.setTextColor(70, 70, 70);
  if (inv.notes) {
    const lines = doc.splitTextToSize(inv.notes, (R - L) * 0.48);
    doc.text(lines, L, pfy);
    pfy += lines.length * 10 * k;
  } else {
    doc.text(settings.businessName || 'Business', L, pfy); pfy += 11 * k;
    if (settings.phone) { doc.text(`Contact: ${settings.phone}`, L, pfy); pfy += 11 * k; }
    if (settings.email) { doc.text(`Email: ${settings.email}`, L, pfy); pfy += 11 * k; }
  }

  // Right: Business name / Authorized Signatory + Address
  doc.setFont('times', 'normal');
  doc.setFontSize(15 * k);
  doc.setTextColor(20, 20, 20);
  doc.text(settings.signName || settings.businessName || 'Juliana Silva', R, fy + 8 * k, { align: 'right' });
  doc.setFont('helvetica', 'normal');
  doc.setFontSize(8 * k);
  doc.setTextColor(80, 80, 80);
  doc.text('Proprietor', R, fy + 22 * k, { align: 'right' });

  return { doc, bottom: Math.max(pfy, fy + 35 * k), pages: doc.internal.getNumberOfPages() };
}

// Single A4 page: shrink for heavy data, scale up slightly and spread
// the leftover as section spacing for light data, so it never looks
// crammed or empty.
function invoicePDF(inv) {
  const M = 42, H = 841.89;
  const fits = r => r.pages === 1 && r.bottom <= H - M;

  let r = null, k = 1;
  for (const kk of [1, 0.94, 0.88, 0.82, 0.76, 0.7, 0.64, 0.58, 0.55]) {
    r = buildInvoicePDF(inv, kk, 0);
    if (fits(r)) { k = kk; break; }
  }
  if (!fits(r)) return r.doc;

  if (H - M - r.bottom > 150) {
    const grown = buildInvoicePDF(inv, 1.12, 0);
    if (fits(grown)) { r = grown; k = 1.12; }
  }

  const e = Math.min(45, Math.max(0, (H - M - r.bottom) / 5 * 0.85));
  return buildInvoicePDF(inv, k, e).doc;
}

function reportPDF(r, data) {
  const { jsPDF } = window.jspdf;
  const doc = new jsPDF({ unit: 'pt', format: 'a4' });
  const W = doc.internal.pageSize.getWidth();
  doc.setFillColor(37, 99, 235); doc.rect(0, 0, W, 90, 'F');
  doc.setTextColor(255, 255, 255); doc.setFont('helvetica', 'bold'); doc.setFontSize(20);
  doc.text('Summary Report', 40, 42);
  doc.setFontSize(11); doc.setFont('helvetica', 'normal'); doc.setTextColor(219, 234, 254);
  doc.text(`${r.label}  ·  ${settings.businessName}`, 40, 62);

  doc.autoTable({
    startY: 120,
    head: [['Metric', 'Value']],
    body: [
      ['Revenue (amounts received)', money(data.sales)],
      ['Total invoiced in period', money(data.invoiced)],
      ['Invoices in period', String(data.invCount)],
      ['Fully paid invoices', String(data.count)],
      ['Unpaid / partial invoices', String(data.openCount)],
      ['Outstanding (not yet received)', money(data.outstanding)],
      ['Total expenses', money(data.expenses)],
      ['Net profit (revenue - expenses)', money(data.profit)],
      ['Expenses recorded', String(data.expCount)]
    ],
    styles: { fontSize: 10, cellPadding: 8 },
    headStyles: { fillColor: [239, 246, 255], textColor: [29, 78, 216], fontStyle: 'bold' },
    alternateRowStyles: { fillColor: [248, 250, 253] },
    margin: { left: 40, right: 40 }
  });
  let y = doc.lastAutoTable.finalY + 30;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(12); doc.setTextColor(15, 23, 42);
  doc.text('Top clients', 40, y);
  doc.autoTable({
    startY: y + 12,
    head: [['Client', 'Invoices', 'Received']],
    body: data.topClients.map(c => [c.name || 'Walk-in Client', String(c.n), money(c.v)]),
    styles: { fontSize: 9.5, cellPadding: 7 },
    headStyles: { fillColor: [239, 246, 255], textColor: [29, 78, 216], fontStyle: 'bold' },
    margin: { left: 40, right: 40 }
  });
  y = doc.lastAutoTable.finalY + 30;
  doc.setFont('helvetica', 'bold'); doc.setFontSize(12);
  doc.text('Expenses by category', 40, y);
  doc.autoTable({
    startY: y + 12,
    head: [['Category', 'Amount']],
    body: data.cats.map(c => [c.name, money(c.value)]),
    styles: { fontSize: 9.5, cellPadding: 7 },
    headStyles: { fillColor: [255, 251, 235], textColor: [180, 83, 9], fontStyle: 'bold' },
    margin: { left: 40, right: 40 }
  });
  const H = doc.internal.pageSize.getHeight();
  doc.setFontSize(8.5); doc.setTextColor(148, 163, 184); doc.setFont('helvetica', 'normal');
  doc.text(`Generated with ElectroPowerInt · ${fmtDate(Date.now())}`, 40, H - 36);
  return doc;
}

/* ---------------- sharing ---------------- */
function invoiceSummaryText(inv) {
  const t = invoiceTotals(inv);
  return `Invoice ${inv.number} — Total: ${money(t.total)}`;
}
async function shareWhatsApp(inv) {
  const doc = invoicePDF(inv);
  const file = new File([doc.output('blob')], `${inv.number}.pdf`, { type: 'application/pdf' });
  // Mobile / Web Share API: share PDF file only (no text message)
  if (navigator.canShare && navigator.canShare({ files: [file] })) {
    try {
      await navigator.share({ files: [file] });
      logEvent('invoice', `Invoice ${inv.number} shared on WhatsApp (PDF)`);
      toast('Shared');
      return;
    } catch (e) {
      if (e && e.name === 'AbortError') return;   // user cancelled
    }
  }
  // Desktop / fallback: PDF download + WhatsApp without text
  doc.save(`${inv.number}.pdf`);
  const cleanPhone = (inv.clientPhone || '').replace(/[^0-9]/g, '');
  const waUrl = cleanPhone ? `https://wa.me/${cleanPhone}` : `https://web.whatsapp.com/`;
  window.open(waUrl, '_blank');
  logEvent('invoice', `Invoice ${inv.number} — WhatsApp opened + PDF downloaded`);
  toast('PDF downloaded and WhatsApp opened — please attach the PDF', 'info');
}
function openEmail(inv) {
  const t = invoiceTotals(inv);
  const subject = `Invoice ${inv.number} from ${settings.businessName}`;
  const body = `Dear ${inv.clientName || 'Client'},\n\nPlease find attached invoice ${inv.number} for ${money(t.total)}.\n\nThank you,\n${settings.businessName}`;
  const url = `mailto:${encodeURIComponent(inv.clientEmail || '')}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
  location.href = url;
  logEvent('invoice', `Invoice ${inv.number} sent by email`);
}
async function sharePDFFile(inv) {
  const doc = invoicePDF(inv);
  const blob = doc.output('blob');
  const file = new File([blob], `${inv.number}.pdf`, { type: 'application/pdf' });
  if (navigator.canShare && navigator.canShare({ files: [file] })) {
    try {
      await navigator.share({ files: [file] });
      logEvent('invoice', `Invoice ${inv.number} PDF shared`);
      toast('PDF shared');
      return;
    } catch { return; }
  }
  doc.save(`${inv.number}.pdf`);
  logEvent('invoice', `Invoice ${inv.number} PDF downloaded`);
  toast('PDF downloaded — please attach to share', 'info');
}
function shareSheet(inv) {
  const html = `
    <div class="share-list">
      <button class="share-btn" data-act="pdf">
        <span class="si" style="background:#e11d48">${IC.pdf}</span>
        <span class="si-text"><b>Download PDF</b><small>Save ${esc(inv.number)}.pdf to device</small></span>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M9 18l6-6-6-6"/></svg>
      </button>
      <button class="share-btn" data-act="share">
        <span class="si" style="background:#2563eb">${IC.share}</span>
        <span class="si-text"><b>Share PDF File</b><small>WhatsApp · Gmail · Drive…</small></span>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M9 18l6-6-6-6"/></svg>
      </button>
      <button class="share-btn" data-act="wa">
        <span class="si" style="background:#25d366">${IC.wa}</span>
        <span class="si-text"><b>Send via WhatsApp</b><small>Pick a contact · PDF attached</small></span>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M9 18l6-6-6-6"/></svg>
      </button>
      <button class="share-btn" data-act="mail">
        <span class="si" style="background:#0284c7">${IC.mail}</span>
        <span class="si-text"><b>Send by Email</b><small>${esc(inv.clientEmail || 'Email client will open')}</small></span>
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M9 18l6-6-6-6"/></svg>
      </button>
    </div>`;
  openSheet('Share / Send — ' + inv.number, html, root => {
    root.querySelectorAll('.share-btn').forEach(b => b.addEventListener('click', () => {
      closeModal(false);
      const act = b.dataset.act;
      if (act === 'pdf') { invoicePDF(inv).save(`${inv.number}.pdf`); logEvent('invoice', `Invoice ${inv.number} PDF downloaded`); toast('PDF downloaded'); }
      if (act === 'share') sharePDFFile(inv);
      if (act === 'wa') shareWhatsApp(inv);
      if (act === 'mail') openEmail(inv);
    }));
  });
}
function openSheet(title, html, mount) {
  $('#modalTitle').textContent = title;
  $('#modalText').innerHTML = html;
  $('#modalOk').classList.add('hide');
  $('#modalCancel').textContent = 'Close';
  $('#modalRoot').hidden = false;
  if (mount) mount($('#modalText'));
}
function resetModal() {
  $('#modalOk').classList.remove('hide');
  $('#modalCancel').textContent = 'Cancel';
  $('#modalTitle').textContent = 'Are you sure?';
  $('#modalText').textContent = '';
}

/* ---------------- router ---------------- */
const ROUTES = {
  'dashboard': { title: 'Dashboard', sub: 'Snapshot of today — sales, expenses and reminders', render: viewDashboard },
  'invoices': { title: 'Invoices', sub: 'Create, share and manage invoices', render: viewInvoices },
  'expenses': { title: 'Expenses', sub: 'Track every expense', render: viewExpenses },
  'reports': { title: 'Reports', sub: 'Revenue, expenses and profit for any period', render: viewReports },
  'reminders': { title: 'Reminders', sub: 'Never miss a thing', render: viewReminders },
  'notes': { title: 'Notes', sub: 'Autosaving notes', render: viewNotes },
  'whiteboard': { title: 'Whiteboard', sub: 'Write and draw — autosave', render: viewWhiteboard },
  'history': { title: 'History', sub: 'A record of every action', render: viewHistory },
  'settings': { title: 'Settings', sub: 'Business profile and data', render: viewSettings }
};
function parseHash() {
  const parts = location.hash.replace(/^#\/?/, '').split('/').filter(Boolean);
  return { page: parts[0] || 'dashboard', a: parts[1], b: parts[2] };
}
function render() {
  const { page, a, b } = parseHash();
  resetModal();
  const view = $('#view');
  let title = 'Dashboard', sub = '';

  if (page === 'invoices' && a === 'new') { title = 'New Invoice'; sub = 'Create a new invoice'; view.innerHTML = invoiceFormHTML(null); mountInvoiceForm(null); }
  else if (page === 'invoices' && a && b === 'edit') {
    const inv = getInvoices().find(i => i.id === a);
    if (!inv) { view.innerHTML = notFound(); }
    else if (inv.status === 'paid') { toast(`${inv.number} is fully paid, so it is locked. Mark it unpaid to edit.`, 'err'); location.hash = `#/invoices/${inv.id}`; }
    else { title = 'Edit ' + inv.number; sub = 'Update the invoice'; view.innerHTML = invoiceFormHTML(inv); mountInvoiceForm(inv); }
  }
  else if (page === 'invoices' && a) {
    const inv = getInvoices().find(i => i.id === a);
    if (!inv) { view.innerHTML = notFound(); } else { title = inv.number; sub = 'Invoice detail'; view.innerHTML = invoiceDetailHTML(inv); mountInvoiceDetail(inv); }
  }
  else if (ROUTES[page]) {
    title = ROUTES[page].title; sub = ROUTES[page].sub;
    view.innerHTML = ROUTES[page].render();
    const m = MOUNT[page]; if (m) m();
  }
  else { view.innerHTML = notFound(); }

  $('#pageTitle').textContent = title;
  $('#pageSub').textContent = sub;
  const key = page === 'invoices' ? 'invoices' : page;
  $$('#sideNav a').forEach(l => l.classList.toggle('active', l.dataset.route === key));
  closeSidebar();
  updateReminderPill();
  fitPaperSheets();
  view.focus({ preventScroll: true });
  window.scrollTo(0, 0);
}
const notFound = () => `<div class="empty"><div class="art">${IC.search}</div><h3>Page not found</h3><p>The page you are looking for does not exist.</p><a class="btn btn-primary btn-sm mt-2" href="#/dashboard">Go to dashboard</a></div>`;
window.addEventListener('hashchange', render);
window.addEventListener('resize', () => fitPaperSheets());

/* ---------------- sidebar (mobile) ---------------- */
function openSidebar() { $('#sidebar').classList.add('open'); $('#sidebarBackdrop').classList.add('show'); }
function closeSidebar() { $('#sidebar').classList.remove('open'); $('#sidebarBackdrop').classList.remove('show'); }
$('#hamburger').addEventListener('click', openSidebar);
$('#sidebarBackdrop').addEventListener('click', closeSidebar);

function updateReminderPill() {
  const now = Date.now();
  const due = getReminders().filter(r => !r.done && new Date(r.datetime).getTime() <= now + 864e5).length;
  const od = outstandingInvoices().length;
  const pill = $('#reminderPill');
  pill.hidden = !(due + od); pill.textContent = due + od;
}

/* one nudge per page load, once the real data is in */
let odNoticed = false;
function checkOutstanding() {
  if (odNoticed) return;
  const od = outstandingInvoices();
  if (!od.length) return;
  odNoticed = true;
  toast(`${od.length} invoice(s) outstanding for over ${OVERDUE_DAYS} days · ${money(outstandingTotal(od))} due`, 'info');
  if ('Notification' in window && Notification.permission === 'granted') {
    try { new Notification('Invoices outstanding', { body: `${od.length} invoice(s) · ${money(outstandingTotal(od))} due` }); } catch { }
  }
}

/* ================= VIEWS ================= */

/* ---------- Dashboard ---------- */
function viewDashboard() {
  const invs = getInvoices(), exps = getExpenses();
  const now = Date.now(), today = todayISO(), mk = monthKey(now);
  const paid = invs.reduce((s, i) => s + invoicePaidInfo(i).paid, 0);
  const unpaid = invs.reduce((s, i) => s + invoicePaidInfo(i).remaining, 0);
  const monthExp = exps.filter(e => monthKey(e.date) === mk).reduce((s, e) => s + Number(e.amount), 0);
  const todaySales = invs.filter(i => fmtDate(i.createdAt).replace(/ /g, '-') && new Date(i.createdAt).toDateString() === new Date().toDateString())
    .reduce((s, i) => s + invoicePaidInfo(i).paid, 0);

  const days = [];
  for (let d = 6; d >= 0; d--) {
    const dt = new Date(now - d * 864e5);
    const key = dt.toDateString();
    const val = invs.filter(i => new Date(i.createdAt).toDateString() === key).reduce((s, i) => s + invoicePaidInfo(i).paid, 0);
    days.push({ label: dt.toLocaleDateString('en-GB', { weekday: 'short' }), val: money(val), raw: val, hi: d === 0 });
  }
  const max = Math.max(...days.map(d => d.raw), 1);
  days.forEach(d => d.pct = Math.max(4, Math.round(d.raw / max * 100)));

  const cats = {};
  exps.forEach(e => cats[e.category] = (cats[e.category] || 0) + Number(e.amount));
  const palette = ['#2563eb', '#0ea5e9', '#d97706', '#059669', '#0284c7', '#db2777', '#64748b'];
  const parts = Object.entries(cats).sort((a, b) => b[1] - a[1]).map(([name, value], i) => ({ name, value, color: palette[i % palette.length] }));

  const recent = [...invs].sort((a, b) => b.createdAt - a.createdAt).slice(0, 6);
  const dueRem = getReminders().filter(r => !r.done).sort((a, b) => new Date(a.datetime) - new Date(b.datetime)).slice(0, 4);
  const od = outstandingInvoices();

  return `
  <div class="grid g-4">
    <div class="stat"><span class="ic tone-brand">${IC.cash}</span><div><small>Today's revenue</small><b>${money(todaySales)}</b></div></div>
    <div class="stat"><span class="ic tone-green">${IC.check}</span><div><small>Collected (all time)</small><b>${money(paid)}</b></div></div>
    <div class="stat"><span class="ic tone-red">${IC.clock}</span><div><small>Pending (still to receive)</small><b>${money(unpaid)}</b></div></div>
    <div class="stat"><span class="ic tone-amber">${IC.wallet}</span><div><small>Expenses this month</small><b>${money(monthExp)}</b></div></div>
  </div>

  ${od.length ? `
  <div class="card od-alert mt-3">
    <div class="card-pad row-between">
      <div class="chip-row" style="align-items:center">
        <span class="li-ic tone-red">${IC.clock}</span>
        <div><b>${od.length} invoice(s) outstanding</b>
          <small class="muted" style="display:block">Not fully paid even after ${OVERDUE_DAYS} days · ${money(outstandingTotal(od))} still due</small></div>
      </div>
      <a class="btn btn-primary btn-sm" href="#/reminders">Follow up</a>
    </div>
  </div>` : ''}

  <div class="grid g-2 mt-3">
    <div class="card">
      <div class="card-head"><h3>Last 7 days revenue</h3><small>hover bars for value</small></div>
      <div class="card-pad">${barsChart(days)}</div>
    </div>
    <div class="card">
      <div class="card-head"><h3>Expenses by category</h3><small>all time</small></div>
      <div class="card-pad donut-wrap">
        ${donutChart(parts)}
        <ul class="legend" style="flex:1;min-width:150px">
          ${parts.length ? parts.map(p => `<li><span class="sw" style="background:${p.color}"></span>${esc(p.name)}<b>${money(p.value)}</b></li>`).join('') : '<li class="muted small">No expenses yet</li>'}
        </ul>
      </div>
    </div>
  </div>

  <div class="grid g-2 mt-3">
    <div class="card">
      <div class="card-head"><h3>Recent invoices</h3><a class="btn btn-ghost btn-xs" href="#/invoices">View all</a></div>
      ${recent.length ? `<div class="table-wrap"><table class="tbl"><thead><tr><th>Invoice</th><th>Client</th><th class="num">Total</th></tr></thead><tbody>
        ${recent.map(i => `<tr class="tbl-link" data-open="${i.id}"><td class="cell-main">${esc(i.number)}</td><td>${esc(i.clientName)}</td>
          <td class="num cell-main">${money(invoiceTotals(i).total)}</td></tr>`).join('')}
      </tbody></table></div>` : emptyHTML(IC.doc, 'No invoices yet', 'Create your first invoice — it takes 2 minutes.', '#/invoices/new', 'New Invoice')}
    </div>
    <div class="card">
      <div class="card-head"><h3>Upcoming reminders</h3><a class="btn btn-ghost btn-xs" href="#/reminders">View all</a></div>
      ${dueRem.length ? dueRem.map(r => {
    const overdue = new Date(r.datetime).getTime() < Date.now();
    return `<div class="li-row"><span class="li-ic ${overdue ? 'tone-red' : 'tone-blue'}">${IC.clock}</span>
          <div class="li-main"><b>${esc(r.title)}</b><small>${fmtDateTime(new Date(r.datetime).getTime())}</small></div>
          <span class="badge ${overdue ? 'b-unpaid' : 'b-due'}">${overdue ? 'overdue' : 'upcoming'}</span></div>`;
  }).join('') : `<div class="empty small" style="padding:2.4rem"><p>No reminders set</p></div>`}
    </div>
  </div>`;
}
const MOUNT = {};
MOUNT.dashboard = () => {
  $$('#view [data-open]').forEach(tr => tr.addEventListener('click', () => location.hash = '#/invoices/' + tr.dataset.open));
};

const emptyHTML = (icon, h, p, href, btn) => `
  <div class="empty"><div class="art">${icon}</div><h3>${esc(h)}</h3><p>${esc(p)}</p>
  ${href ? `<a class="btn btn-primary btn-sm mt-2" href="${href}">${esc(btn)}</a>` : ''}</div>`;

/* ---------- Invoices list ---------- */
function viewInvoices() {
  return `
  <div class="toolbar">
    <div class="grow">${IC.search}<input class="input" id="invSearch" placeholder="Search by number or client…" /></div>
    <select class="input" id="invStatus" style="width:auto">
      <option value="">All statuses</option><option value="paid">Paid</option>
      <option value="partial">Partial</option><option value="unpaid">Unpaid</option>
    </select>
    <select class="input" id="invSort" style="width:auto">
      <option value="new">Newest first</option><option value="old">Oldest first</option>
      <option value="high">Amount: high to low</option><option value="low">Amount: low to high</option>
      <option value="paidfirst">Paid first</option><option value="unpaidfirst">Unpaid first</option>
    </select>
    <a class="btn btn-primary btn-sm" href="#/invoices/new">${IC.plus} New Invoice</a>
  </div>
  <div class="grid g-2" id="invSummary"></div>
  <div class="card mt-3" id="invListWrap"></div>`;
}
MOUNT.invoices = () => {
  let q = '', st = '', sort = 'new';
  const draw = () => {
    let list = getInvoices();
    if (q) list = list.filter(i => (i.number + ' ' + i.clientName).toLowerCase().includes(q));
    if (st) list = list.filter(i => i.status === st);
    list = sortInvoices(list, sort);

    // proportional: every invoice splits into what came in and what is still due
    const paidV = list.reduce((a, i) => a + invoicePaidInfo(i).paid, 0);
    const dueV = list.reduce((a, i) => a + invoicePaidInfo(i).remaining, 0);
    $('#invSummary').innerHTML = `
      <div class="stat"><span class="ic tone-green">${IC.check}</span><div><small>Paid</small><b>${money(paidV)}</b></div></div>
      <div class="stat"><span class="ic tone-red">${IC.clock}</span><div><small>Unpaid</small><b>${money(dueV)}</b></div></div>`;

    $('#invListWrap').innerHTML = list.length ? `
      <div class="table-wrap"><table class="tbl">
        <thead><tr><th>Invoice</th><th>Client</th><th>Date</th><th>Status</th><th class="num">Total</th><th></th></tr></thead>
        <tbody>${list.map(i => `
          <tr class="tbl-link" data-open="${i.id}">
            <td class="cell-main">${esc(i.number)}</td>
            <td><div class="cell-main">${esc(i.clientName)}</div><div class="cell-sub">${esc(i.clientPhone || '')}</div></td>
            <td class="nowrap">${fmtDate(i.createdAt)}</td>
            <td>${invoiceStatusBadge(i)}</td>
            <td class="num cell-main">${money(invoiceTotals(i).total)}</td>
            <td><div class="actions">
              <button class="icon-mini" data-pay="${i.id}" title="${i.status === 'paid' ? 'Mark unpaid' : 'Record payment'}">${i.status === 'paid' ? IC.clock : IC.cash}</button>
              <button class="icon-mini" data-share="${i.id}" title="Share">${IC.share}</button>
              <button class="icon-mini" data-pdf="${i.id}" title="PDF">${IC.pdf}</button>
              <button class="icon-mini" data-del="${i.id}" title="Delete">${IC.trash}</button>
            </div></td>
          </tr>`).join('')}</tbody></table></div>`
      : emptyHTML(IC.doc, 'No invoices found', !q && !st ? 'Create your first invoice and send it to a client.' : 'Try changing the search or status filter.', '#/invoices/new', 'New Invoice');
  };
  draw();
  $('#invSearch').addEventListener('input', e => { q = e.target.value.trim().toLowerCase(); draw(); });
  $('#invStatus').addEventListener('change', e => { st = e.target.value; draw(); });
  $('#invSort').addEventListener('change', e => { sort = e.target.value; draw(); });
  $('#invListWrap').addEventListener('click', async e => {
    const open = e.target.closest('[data-open]');
    const pay = e.target.closest('[data-pay]');
    const share = e.target.closest('[data-share]');
    const pdf = e.target.closest('[data-pdf]');
    const del = e.target.closest('[data-del]');
    if (pay) {
      e.stopPropagation();
      const inv = getInvoices().find(i => i.id === pay.dataset.pay);
      if (inv.status === 'paid') {
        setInvoiceStatus(inv.id, 'unpaid');
        toast('Marked unpaid — full amount is due again');
        draw();
        return;
      }
      const pick = await openPayModal(inv);
      if (pick) {
        const n = applyPayment(inv.id, pick.amt);
        toast(`${money(pick.amt)} recorded · ${n.status}`);
      }
      draw();
      return;
    }
    if (share) { e.stopPropagation(); shareSheet(getInvoices().find(i => i.id === share.dataset.share)); return; }
    if (pdf) { e.stopPropagation(); const inv = getInvoices().find(i => i.id === pdf.dataset.pdf); invoicePDF(inv).save(`${inv.number}.pdf`); logEvent('invoice', `Invoice ${inv.number} PDF downloaded`); toast('PDF downloaded'); return; }
    if (del) {
      e.stopPropagation();
      const inv = getInvoices().find(i => i.id === del.dataset.del);
      if (await confirmBox('Delete invoice?', `${inv.number} — ${inv.clientName} will be permanently deleted.`)) {
        setInvoices(getInvoices().filter(i => i.id !== inv.id));
        logEvent('invoice', `Invoice ${inv.number} deleted`); toast('Invoice deleted'); draw();
      }
      return;
    }
    if (open && !e.target.closest('.actions')) location.hash = '#/invoices/' + open.dataset.open;
  });
};

/* ---------- Invoice form ---------- */
function invoiceFormHTML(inv) {
  const clients = getClients();
  return `
  <div class="inv-editor">
  <form id="invForm" autocomplete="off">
    <div class="form-section">
      <h3><span class="step-n">1</span> Client & Invoice details</h3>
      <div class="f-row">
        <div class="field">
          <label>Invoice Number *</label>
          <input class="input" name="invoiceNumber" required value="${esc(inv?.number || nextInvoiceNumber())}" placeholder="e.g. INV-0001" style="font-weight:600" />
        </div>
        <div class="field"><label>Saved client <small>(pick to auto-fill)</small></label>
          <select class="input" id="clientPick">
            <option value="">— New client —</option>
            ${clients.map(c => `<option value="${esc(c.name)}" ${inv?.clientName === c.name ? 'selected' : ''}>${esc(c.name)}</option>`).join('')}
          </select>
        </div>
      </div>
      <div class="f-row">
        <div class="field"><label>Client name *</label><input class="input" name="clientName" required value="${esc(inv?.clientName || '')}" placeholder="e.g. Ahmed Traders" /></div>
        <div class="field"><label>Phone <small>(for WhatsApp)</small></label><input class="input" name="clientPhone" value="${esc(inv?.clientPhone || '')}" placeholder="+92 300 1234567" /></div>
      </div>
      <div class="f-row">
        <div class="field"><label>Email</label><input class="input" type="email" name="clientEmail" value="${esc(inv?.clientEmail || '')}" placeholder="client@email.com" /></div>
        <div class="field"><label>Due date <small>(optional)</small></label><input class="input" type="date" name="dueDate" value="${inv?.dueDate || ''}" /></div>
      </div>
      <div class="field"><label>Client address <small>(in the "Bill To" column)</small></label>
        <textarea class="input" name="clientAddress" style="min-height:56px" placeholder="Area, Town, City">${esc(inv?.clientAddress || '')}</textarea></div>
    </div>

    <div class="form-section">
      <h3><span class="step-n">2</span> Items</h3>
      <div class="item-row" style="margin-bottom:.4rem">
        <small style="font-weight:700;color:var(--ink-3)">ITEM</small>
        <small style="font-weight:700;color:var(--ink-3)">QTY</small>
        <small style="font-weight:700;color:var(--ink-3)">PRICE</small>
        <small style="font-weight:700;color:var(--ink-3);text-align:right">AMOUNT</small>
        <span></span>
      </div>
      <div id="itemRows"></div>
      <p class="muted small" style="margin-top:.4rem">Printed invoice always shows ${invoiceRowCount()} rows. Extra empty rows print as ------. Increase row count in Settings.</p>
      <div class="row-between mt-3" style="align-items:flex-end">
        <div class="f-row" style="gap:.6rem;margin-bottom:0">
          <div class="field" style="max-width:150px;margin-bottom:0">
            <label>Discount <small>(optional)</small></label>
            <input class="input" type="number" min="0" step="any" name="discount" value="${inv?.discount || 0}" />
          </div>
          <div class="field" style="max-width:120px;margin-bottom:0">
            <label>Type</label>
            <select class="input" name="discountType">
              <option value="amount" ${inv?.discountType !== 'percent' ? 'selected' : ''}>Amount</option>
              <option value="percent" ${inv?.discountType === 'percent' ? 'selected' : ''}>%</option>
            </select>
          </div>
        </div>
        <div class="totals-box" id="totalsBox"></div>
      </div>
    </div>

    <div class="form-section">
      
      <div class="field">
        <textarea class="input" name="notes" style="display:none;" placeholder="Payment terms, thank-you note…">${esc(inv?.notes || '')}</textarea></div>
      <div class="row-between">
        <a class="btn btn-ghost" href="#/invoices">Cancel</a>
        <button class="btn btn-primary" type="submit">${IC.check} ${inv ? 'Update invoice' : 'Save invoice'}</button>
      </div>
    </div>
  </form>
  <aside class="p2-preview-wrap">
    <div class="p2-preview-label">Live preview</div>
    <div id="livePreview"></div>
  </aside>
  </div>`;
}
function itemRowHTML(it = {}) {
  return `<div class="item-row">
    <input class="input it-name" placeholder="Item name" value="${esc(it.name || '')}" />
    <input class="input it-qty" type="number" min="0" step="any" placeholder="Qty" value="${it.qty ?? ''}" />
    <input class="input it-price" type="number" min="0" step="any" placeholder="0" value="${it.price ?? ''}" />
    <div class="line-total">0</div>
    <button type="button" class="icon-mini rm-item" title="Remove">${IC.trash}</button>
  </div>`;
}
function mountInvoiceForm(inv) {
  const rows = $('#itemRows');
  const form = $('#invForm');
  const readDraft = () => ({
    number: form.invoiceNumber?.value.trim() || inv?.number || nextInvoiceNumber(),
    clientName: form.clientName.value.trim(),
    clientPhone: form.clientPhone.value.trim(),
    clientEmail: form.clientEmail.value.trim(),
    clientAddress: form.clientAddress.value.trim(),
    dueDate: form.dueDate.value,
    notes: form.notes.value.trim(),
    discount: Number(form.discount.value) || 0,
    discountType: form.discountType.value,
    items: $$('.item-row', rows).map(r => ({
      name: $('.it-name', r).value.trim(),
      qty: $('.it-qty', r).value,
      price: $('.it-price', r).value
    })).filter(i => i.name)
  });
  const updatePreview = () => {
    const lp = $('#livePreview');
    const draft = readDraft();
    if (lp) lp.innerHTML = invoicePaperHTML({ ...draft, number: draft.number, createdAt: inv?.createdAt || Date.now() });
    fitPaperSheets(lp || document);
  };
  const recalc = () => {
    let sub = 0;
    $$('.item-row', rows).forEach(r => {
      const q = Number($('.it-qty', r).value) || 0, p = Number($('.it-price', r).value) || 0;
      const line = q * p; sub += line;
      $('.line-total', r).textContent = money(line);
    });
    const raw = Number(form.discount.value) || 0;
    const disc = form.discountType.value === 'percent' ? sub * raw / 100 : raw;
    $('#totalsBox').innerHTML = `
      <div class="trow"><span>Subtotal</span><b>${money(sub)}</b></div>
      <div class="trow"><span>Discount</span><b>- ${money(disc)}</b></div>
      <div class="trow grand"><span>Total</span><span>${money(Math.max(0, sub - disc))}</span></div>`;
    updatePreview();
  };
  const addRow = (it) => { rows.insertAdjacentHTML('beforeend', itemRowHTML(it)); recalc(); };
  const seed = inv?.items?.length ? [...inv.items] : [];
  while (seed.length < invoiceRowCount()) seed.push({});
  seed.forEach(addRow);
  rows.addEventListener('click', e => {
    if (e.target.closest('.rm-item')) {
      if ($$('.item-row', rows).length > 1) e.target.closest('.item-row').remove();
      recalc();
    }
  });
  $('#clientPick').addEventListener('change', e => {
    const c = getClients().find(x => x.name === e.target.value);
    if (!c) return;
    form.clientName.value = c.name || '';
    form.clientPhone.value = c.phone || '';
    form.clientEmail.value = c.email || '';
    form.clientAddress.value = c.address || '';
    recalc();
  });
  form.addEventListener('input', recalc);
  recalc();

  $('#invForm').addEventListener('submit', e => {
    e.preventDefault();
    const f = new FormData(e.target);
    const items = $$('.item-row', rows).map(r => ({
      name: $('.it-name', r).value.trim(),
      qty: Number($('.it-qty', r).value) || 0,
      price: Number($('.it-price', r).value) || 0
    })).filter(i => i.name && i.qty > 0);
    const invNum = f.get('invoiceNumber')?.trim() || (inv ? inv.number : nextInvoiceNumber());
    if (!invNum) return toast('Invoice number is required', 'err');
    if (!f.get('clientName').trim()) return toast('Client name is required', 'err');
    if (!items.length) return toast('Add at least one item', 'err');
    const data = {
      clientName: f.get('clientName').trim(),
      clientPhone: f.get('clientPhone').trim(),
      clientEmail: f.get('clientEmail').trim(),
      clientAddress: f.get('clientAddress').trim(),
      dueDate: f.get('dueDate') || '',
      discount: Number(f.get('discount')) || 0,
      discountType: f.get('discountType'),
      notes: f.get('notes').trim(), items
    };
    upsertClient(data);
    if (inv) {
      const list = getInvoices();
      const i = list.findIndex(x => x.id === inv.id);
      list[i] = { ...list[i], ...data, number: invNum, updatedAt: Date.now() };
      setInvoices(list);
      logEvent('invoice', `Invoice ${list[i].number} updated`);
      toast('Invoice updated');
      location.hash = '#/invoices/' + inv.id;
    } else {
      const rec = { id: uid(), number: invNum, createdAt: Date.now(), updatedAt: Date.now(), status: 'unpaid', ...data };
      setInvoices([rec, ...getInvoices()]);
      logEvent('invoice', `Invoice ${rec.number} created for ${rec.clientName}`);
      toast(`Invoice ${rec.number} saved`);
      location.hash = '#/invoices/' + rec.id;
    }
  });
}

/* ---------- Invoice detail ---------- */
function invoiceDetailHTML(inv) {
  const p = invoicePaidInfo(inv);
  return `
  <div class="row-between" style="margin-bottom:1.2rem">
    <div class="chip-row">
      <button class="btn btn-ghost btn-sm" id="dBack">← Back</button>
      <button class="btn btn-ghost btn-sm" id="dEdit">${IC.edit} Edit</button>
      <button class="btn btn-danger btn-sm" id="dDel">${IC.trash} Delete</button>
    </div>
    <div class="chip-row">
      <button class="btn btn-primary btn-sm" id="dShare">${IC.share} Share / Send</button>
    </div>
  </div>
  <div class="row-between p2-meta pay-bar" style="margin-bottom:.8rem">
    <span>Invoice <b>${esc(inv.number)}</b> &nbsp;·&nbsp; ${fmtDateSlash(inv.createdAt)} &nbsp;·&nbsp; ${invoiceStatusBadge(inv)}
      ${p.paid > 0 ? `<small class="muted">&nbsp;${money(p.paid)} received${p.remaining > 0 ? `, ${money(p.remaining)} left` : ''}</small>` : ''}</span>
    <div class="chip-row">
      <button class="btn btn-primary btn-sm" id="dPayRec">Record payment</button>
      ${inv.status === 'paid' ? '<button class="btn btn-ghost btn-sm" id="dPayUn">Mark unpaid</button>' : ''}
    </div>
  </div>
  ${invoicePaperHTML(inv)}`;
}
function mountInvoiceDetail(inv) {
  $('#dBack').addEventListener('click', () => location.hash = '#/invoices');
  $('#dEdit').addEventListener('click', () => {
    if (inv.status === 'paid') return toast('Fully paid invoices are locked — mark it unpaid to edit', 'err');
    location.hash = `#/invoices/${inv.id}/edit`;
  });
  $('#dShare').addEventListener('click', () => shareSheet(inv));
  $('#dPayRec').addEventListener('click', async () => {
    const pick = await openPayModal(inv);
    if (pick) {
      const n = applyPayment(inv.id, pick.amt);
      toast(`${money(pick.amt)} recorded · ${n.status}`);
      render();
    }
  });
  const un = $('#dPayUn');
  if (un) un.addEventListener('click', () => {
    setInvoiceStatus(inv.id, 'unpaid');
    toast('Marked unpaid — full amount is due again');
    render();
  });
  $('#dDel').addEventListener('click', async () => {
    if (await confirmBox('Delete invoice?', `${inv.number} will be permanently deleted.`)) {
      setInvoices(getInvoices().filter(i => i.id !== inv.id));
      logEvent('invoice', `Invoice ${inv.number} deleted`);
      toast('Invoice deleted');
      location.hash = '#/invoices';
    }
  });
  fitPaperSheets($('#view'));
}

/* ---------- Expenses ---------- */
const EXP_CATS = ['Rent', 'Salaries', 'Utilities', 'Stock', 'Marketing', 'Transport', 'Other'];
function viewExpenses() {
  return `
  <div class="card card-pad" style="margin-bottom:1.3rem">
    <h3 style="font-size:.95rem;margin-bottom:1rem">Add expense</h3>
    <form id="expForm" class="f-row-3">
      <div class="field" style="margin:0"><label>Title *</label><input class="input" name="title" required placeholder="e.g. Shop rent" /></div>
      <div class="field" style="margin:0"><label>Category</label>
        <select class="input" name="category">${EXP_CATS.map(c => `<option>${c}</option>`).join('')}</select></div>
      <div class="field" style="margin:0"><label>Amount *</label><input class="input" type="number" min="0" step="any" name="amount" required placeholder="0" /></div>
      <div class="field" style="margin:0"><label>Date</label><input class="input" type="date" name="date" value="${todayISO()}" /></div>
      <button class="btn btn-primary" type="submit" style="height:42px">${IC.plus} Add</button>
    </form>
  </div>
  <div class="toolbar">
    <div class="grow">${IC.search}<input class="input" id="expSearch" placeholder="Search expenses…" /></div>
    <select class="input" id="expCat" style="width:auto"><option value="">All categories</option>${EXP_CATS.map(c => `<option>${c}</option>`).join('')}</select>
    <input class="input" type="month" id="expMonth" style="width:auto" />
  </div>
  <div class="card" id="expList"></div>`;
}
MOUNT.expenses = () => {
  let q = '', cat = '', mk = '';
  const draw = () => {
    let list = getExpenses().sort((a, b) => new Date(b.date) - new Date(a.date));
    if (q) list = list.filter(e => (e.title + ' ' + e.category).toLowerCase().includes(q));
    if (cat) list = list.filter(e => e.category === cat);
    if (mk) list = list.filter(e => monthKey(e.date) === mk);
    const total = list.reduce((s, e) => s + Number(e.amount), 0);
    $('#expList').innerHTML = list.length ? `
      <div class="card-head"><h3>${list.length} expenses</h3><b style="font-family:Sora">${money(total)}</b></div>
      ${list.map(e => `<div class="li-row">
        <span class="li-ic tone-amber">${IC.wallet}</span>
        <div class="li-main"><b>${esc(e.title)}</b><small>${esc(e.category)} · ${fmtDate(e.date)}${e.note ? ' · ' + esc(e.note) : ''}</small></div>
        <span class="li-amt">- ${money(e.amount)}</span>
        <div class="li-actions"><button class="icon-mini" data-del="${e.id}">${IC.trash}</button></div>
      </div>`).join('')}`
      : emptyHTML(IC.wallet, 'No expenses yet', 'Record your first expense using the form above.');
  };
  draw();
  $('#expForm').addEventListener('submit', e => {
    e.preventDefault();
    const f = new FormData(e.target);
    const rec = { id: uid(), title: f.get('title').trim(), category: f.get('category'), amount: Number(f.get('amount')) || 0, date: f.get('date') || todayISO(), note: '', createdAt: Date.now() };
    setExpenses([rec, ...getExpenses()]);
    logEvent('expense', `Expense added: ${rec.title} (${money(rec.amount)})`);
    toast('Expense added');
    e.target.reset(); $('[name=date]', e.target).value = todayISO();
    draw();
  });
  $('#expSearch').addEventListener('input', e => { q = e.target.value.trim().toLowerCase(); draw(); });
  $('#expCat').addEventListener('change', e => { cat = e.target.value; draw(); });
  $('#expMonth').addEventListener('change', e => { mk = e.target.value; draw(); });
  $('#expList').addEventListener('click', async e => {
    const b = e.target.closest('[data-del]'); if (!b) return;
    const exp = getExpenses().find(x => x.id === b.dataset.del);
    if (await confirmBox('Delete expense?', `${exp.title} — ${money(exp.amount)}`)) {
      setExpenses(getExpenses().filter(x => x.id !== exp.id));
      logEvent('expense', `Expense deleted: ${exp.title}`);
      toast('Expense deleted'); draw();
    }
  });
};

/* ---------- Reminders ---------- */
function viewReminders() {
  return `
  <div class="card" id="odCard" style="margin-bottom:1.3rem"></div>
  <div class="card card-pad" style="margin-bottom:1.3rem">
    <h3 style="font-size:.95rem;margin-bottom:1rem">Add reminder</h3>
    <form id="remForm" class="f-row-3" style="grid-template-columns:2fr 1.2fr 1fr auto">
      <div class="field" style="margin:0"><label>Title *</label><input class="input" name="title" required placeholder="e.g. Call supplier" /></div>
      <div class="field" style="margin:0"><label>When *</label><input class="input" type="datetime-local" name="datetime" required /></div>
      <div class="field" style="margin:0"><label>Note</label><input class="input" name="note" placeholder="optional" /></div>
      <button class="btn btn-primary" type="submit" style="height:42px">${IC.plus} Add</button>
    </form>
  </div>
  <div class="card" id="remList"></div>`;
}
MOUNT.reminders = () => {
  const drawOutstanding = () => {
    const od = outstandingInvoices();
    $('#odCard').innerHTML = od.length ? `
      <div class="card-head"><h3>Invoices outstanding (${od.length})</h3><b style="font-family:Sora;color:var(--red)">${money(outstandingTotal(od))}</b></div>
      <div class="card-pad" style="padding-top:0;padding-bottom:.4rem"><small class="muted">Not fully paid even after ${OVERDUE_DAYS} days — follow up on every one of these.</small></div>
      ${od.map(i => `<div class="li-row">
        <span class="li-ic tone-red">${IC.clock}</span>
        <div class="li-main"><b>${esc(i.number)} · ${esc(i.clientName)}</b>
          <small>${fmtDate(i.createdAt)} &nbsp;·&nbsp; ${i.days} days &nbsp;·&nbsp; invoice ${money(i.total)}${i.paid > 0 ? `, ${money(i.paid)} received` : ''}</small></div>
        <span class="badge ${i.status === 'partial' ? 'b-due' : 'b-unpaid'}">${i.status === 'partial' ? 'partial' : 'unpaid'}</span>
        <span class="li-amt" style="color:var(--red)">${money(i.due)}</span>
        <div class="li-actions">
          <button class="icon-mini" data-odpay="${i.id}" title="Record payment">${IC.cash}</button>
          <button class="icon-mini" data-odwa="${i.id}" title="Send WhatsApp reminder">${IC.wa}</button>
          <a class="icon-mini" href="#/invoices/${i.id}" title="Open invoice">${IC.doc}</a>
        </div></div>`).join('')}`
      : `<div class="card-head"><h3>Invoices outstanding</h3><span class="badge b-paid">clear</span></div>
         <div class="card-pad"><small class="muted">No invoice is unpaid or partially paid for more than ${OVERDUE_DAYS} days.</small></div>`;
  };
  const draw = () => {
    const list = getReminders().sort((a, b) => new Date(a.datetime) - new Date(b.datetime));
    $('#remList').innerHTML = list.length ? list.map(r => {
      const t = new Date(r.datetime).getTime();
      const overdue = !r.done && t < Date.now();
      const soon = !r.done && !overdue && t < Date.now() + 864e5;
      return `<div class="li-row" style="${r.done ? 'opacity:.55' : ''}">
        <span class="li-ic ${r.done ? 'tone-green' : overdue ? 'tone-red' : 'tone-blue'}">${r.done ? IC.check : IC.clock}</span>
        <div class="li-main"><b>${esc(r.title)}</b><small>${fmtDateTime(t)}${r.note ? ' · ' + esc(r.note) : ''}</small></div>
        <span class="badge ${r.done ? 'b-paid' : overdue ? 'b-unpaid' : soon ? 'b-due' : 'b-neutral'}">${r.done ? 'done' : overdue ? 'overdue' : soon ? 'today' : 'upcoming'}</span>
        <div class="li-actions">
          <button class="icon-mini" data-done="${r.id}" title="Toggle done">${IC.check}</button>
          <button class="icon-mini" data-del="${r.id}">${IC.trash}</button>
        </div></div>`;
    }).join('') : emptyHTML(IC.clock, 'No reminders yet', 'Meetings, payments or follow-ups — track everything here.');
  };
  draw();
  drawOutstanding();
  $('#odCard').addEventListener('click', async e => {
    const pay = e.target.closest('[data-odpay]');
    const wa = e.target.closest('[data-odwa]');
    if (pay) {
      const inv = getInvoices().find(i => i.id === pay.dataset.odpay);
      const pick = await openPayModal(inv);
      if (pick) { const n = applyPayment(inv.id, pick.amt); toast(`${money(pick.amt)} recorded · ${n.status}`); }
      drawOutstanding();
    }
    if (wa) {
      const inv = outstandingInvoices().find(i => i.id === wa.dataset.odwa);
      if (inv) remindOnWhatsApp(inv);
    }
  });
  $('#remForm').addEventListener('submit', e => {
    e.preventDefault();
    const f = new FormData(e.target);
    const rec = { id: uid(), title: f.get('title').trim(), datetime: f.get('datetime'), note: f.get('note').trim(), done: false, createdAt: Date.now() };
    setReminders([...getReminders(), rec]);
    logEvent('reminder', `Reminder set: ${rec.title}`);
    toast('Reminder added');
    e.target.reset(); draw(); updateReminderPill();
  });
  $('#remList').addEventListener('click', async e => {
    const done = e.target.closest('[data-done]');
    const del = e.target.closest('[data-del]');
    if (done) {
      const list = getReminders(); const r = list.find(x => x.id === done.dataset.done);
      r.done = !r.done; setReminders(list);
      logEvent('reminder', `Reminder ${r.done ? 'completed' : 'reopened'}: ${r.title}`);
      draw(); updateReminderPill();
    }
    if (del) {
      const r = getReminders().find(x => x.id === del.dataset.del);
      if (await confirmBox('Delete reminder?', r.title)) {
        setReminders(getReminders().filter(x => x.id !== r.id));
        logEvent('reminder', `Reminder deleted: ${r.title}`);
        toast('Reminder deleted'); draw(); updateReminderPill();
      }
    }
  });
};

/* ---------- Notes (autosave) ---------- */
function viewNotes() {
  const notes = getNotes().sort((a, b) => b.updatedAt - a.updatedAt);
  return `
  <div class="notes-grid" id="notesGrid">
    <button class="note-new" id="noteNew">${IC.plus}&nbsp; New note</button>
    ${notes.map(n => noteCardHTML(n)).join('')}
  </div>`;
}
const noteCardHTML = n => `
  <div class="note-card" data-id="${n.id}">
    <input class="n-title" value="${esc(n.title)}" placeholder="Title" />
    <textarea placeholder="Write… (autosave)">${esc(n.body)}</textarea>
    <div class="n-foot"><small>${fmtDateTime(n.updatedAt)}</small>
      <span style="display:flex;gap:.5rem;align-items:center">
        <span class="saved-dot">Saved ✓</span>
        <button class="icon-mini" data-del="${n.id}">${IC.trash}</button>
      </span></div>
  </div>`;
MOUNT.notes = () => {
  const persist = debounce((card) => {
    const id = card.dataset.id;
    const list = getNotes();
    const n = list.find(x => x.id === id);
    n.title = $('.n-title', card).value;
    n.body = $('textarea', card).value;
    n.updatedAt = Date.now();
    setNotes(list);
    $('small', $('.n-foot', card)).textContent = fmtDateTime(n.updatedAt);
    const dot = $('.saved-dot', card);
    dot.classList.add('on'); setTimeout(() => dot.classList.remove('on'), 1200);
  }, 600);
  $('#noteNew').addEventListener('click', () => {
    const n = { id: uid(), title: '', body: '', updatedAt: Date.now() };
    setNotes([n, ...getNotes()]);
    logEvent('note', 'Note created');
    $('#notesGrid').insertAdjacentHTML('afterbegin', noteCardHTML(n));
  });
  $('#notesGrid').addEventListener('input', e => {
    const card = e.target.closest('.note-card'); if (card) persist(card);
  });
  $('#notesGrid').addEventListener('click', async e => {
    const del = e.target.closest('[data-del]'); if (!del) return;
    const card = del.closest('.note-card');
    if (await confirmBox('Delete note?', 'This note will be permanently deleted.')) {
      setNotes(getNotes().filter(x => x.id !== del.dataset.del));
      logEvent('note', 'Note deleted');
      card.remove(); toast('Note deleted');
    }
  });
};

/* ---------- Whiteboard (autosave) ---------- */
function viewWhiteboard() {
  return `
  <div class="board-shell">
    <div class="board-tools">
      <button class="tool active" data-tool="pen" title="Pen">${IC.edit}</button>
      <button class="tool" data-tool="eraser" title="Eraser"><svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M20 20H8L3 15a2 2 0 010-3l9-9a2 2 0 013 0l6 6a2 2 0 010 3l-8 8"/><path d="M6.5 10.5l7 7"/></svg></button>
      <span style="width:1px;height:26px;background:var(--line);margin:0 .3rem"></span>
      ${['#0f172a', '#2563eb', '#e11d48', '#059669', '#d97706'].map((c, i) =>
    `<button class="swatch ${i === 0 ? 'active' : ''}" data-color="${c}" style="background:${c}" aria-label="color ${c}"></button>`).join('')}
      <span style="width:1px;height:26px;background:var(--line);margin:0 .3rem"></span>
      <input type="range" id="brushSize" min="1" max="28" value="4" title="Brush size" />
      <button class="tool" id="boardUndo" title="Undo"><svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 7v6h6"/><path d="M21 17a9 9 0 00-15-6.7L3 13"/></svg></button>
      <button class="tool" id="boardClear" title="Clear all">${IC.trash}</button>
      <span class="muted small" id="boardSaved" style="margin-left:auto">Autosave on</span>
    </div>
    <div class="board-canvas-wrap">
      <canvas id="boardCanvas" height="520"></canvas>
      <span class="board-hint">draw with mouse / touch</span>
    </div>
  </div>`;
}
MOUNT.whiteboard = () => {
  const canvas = $('#boardCanvas'), ctx = canvas.getContext('2d');
  const dpr = window.devicePixelRatio || 1;
  let tool = 'pen', color = '#0f172a', size = 4, drawing = false, last = null;
  const undoStack = [];

  const fit = () => {
    const w = canvas.parentElement.clientWidth;
    canvas.width = w * dpr; canvas.height = 520 * dpr;
    canvas.style.height = '520px';
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, w, 520);
    const saved = load(K.board, null);
    if (saved) { const img = new Image(); img.onload = () => ctx.drawImage(img, 0, 0, w, 520); img.src = saved; }
  };
  fit();
  const saveBoard = debounce(() => {
    save(K.board, canvas.toDataURL('image/png'));
    const s = $('#boardSaved'); s.textContent = 'Saved ✓'; setTimeout(() => s.textContent = 'Autosave on', 1200);
  }, 500);

  const pos = e => {
    const r = canvas.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top };
  };
  canvas.addEventListener('pointerdown', e => {
    canvas.setPointerCapture(e.pointerId);
    drawing = true; last = pos(e);
    undoStack.push(canvas.toDataURL()); if (undoStack.length > 15) undoStack.shift();
  });
  canvas.addEventListener('pointermove', e => {
    if (!drawing) return;
    const p = pos(e);
    ctx.lineCap = 'round'; ctx.lineJoin = 'round';
    ctx.strokeStyle = tool === 'eraser' ? '#ffffff' : color;
    ctx.lineWidth = tool === 'eraser' ? size * 4 : size;
    ctx.beginPath(); ctx.moveTo(last.x, last.y); ctx.lineTo(p.x, p.y); ctx.stroke();
    last = p;
  });
  const stop = () => { if (drawing) { drawing = false; saveBoard(); } };
  canvas.addEventListener('pointerup', stop);
  canvas.addEventListener('pointerleave', stop);

  $$('#view .tool[data-tool]').forEach(b => b.addEventListener('click', () => {
    $$('#view .tool[data-tool]').forEach(x => x.classList.remove('active'));
    b.classList.add('active'); tool = b.dataset.tool;
  }));
  $$('#view .swatch').forEach(s => s.addEventListener('click', () => {
    $$('#view .swatch').forEach(x => x.classList.remove('active'));
    s.classList.add('active'); color = s.dataset.color; tool = 'pen';
    $$('#view .tool[data-tool]').forEach(x => x.classList.toggle('active', x.dataset.tool === 'pen'));
  }));
  $('#brushSize').addEventListener('input', e => size = Number(e.target.value));
  $('#boardClear').addEventListener('click', async () => {
    if (await confirmBox('Clear whiteboard?', 'All drawing will be erased.')) {
      undoStack.push(canvas.toDataURL());
      ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, canvas.width, canvas.height);
      save(K.board, canvas.toDataURL('image/png')); toast('Board cleared');
    }
  });
  $('#boardUndo').addEventListener('click', () => {
    const prev = undoStack.pop(); if (!prev) return;
    const img = new Image();
    img.onload = () => { ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, canvas.width, canvas.height); ctx.drawImage(img, 0, 0, canvas.clientWidth, 520); saveBoard(); };
    img.src = prev;
  });
};

/* ---------- Reports ---------- */
const RANGE_MODES = [['month', 'Monthly'], ['year', 'Yearly'], ['day', 'Single day'], ['custom', 'Date range']];
const dayStart = s => new Date(s + 'T00:00:00').getTime();

// -> { from, to (exclusive), label } for the chosen period
function reportRange(mode, a, b) {
  if (mode === 'year') {
    const y = Number(a) || new Date().getFullYear();
    return { from: new Date(y, 0, 1).getTime(), to: new Date(y + 1, 0, 1).getTime(), label: `Year ${y}` };
  }
  if (mode === 'day') {
    const f = dayStart(a || todayISO());
    return { from: f, to: f + 864e5, label: `${fmtDate(f)} (single day)` };
  }
  if (mode === 'custom') {
    let f = dayStart(a || todayISO()), t = dayStart(b || todayISO());
    if (t < f) [f, t] = [t, f];
    return { from: f, to: t + 864e5, label: `${fmtDate(f)} – ${fmtDate(t)}` };
  }
  const mk = a || monthKey(Date.now());
  const [y, m] = mk.split('-').map(Number);
  return { from: new Date(y, m - 1, 1).getTime(), to: new Date(y, m, 1).getTime(), label: monthLabel(mk) };
}

// Revenue is the money actually received: every paid amount inside the period, full or partial.
function reportData(r) {
  const inR = t => t >= r.from && t < r.to;
  const all = getInvoices().filter(i => inR(Number(i.createdAt)));
  const paid = all.filter(i => i.status === 'paid');
  const open = all.filter(i => i.status !== 'paid');
  const exps = getExpenses().filter(e => inR(dayStart(String(e.date || '').slice(0, 10) || todayISO())));
  const rows = all.map(i => ({ i, p: invoicePaidInfo(i) }));
  const sales = rows.reduce((s, x) => s + x.p.paid, 0);
  const invoiced = rows.reduce((s, x) => s + x.p.total, 0);
  const outstanding = rows.reduce((s, x) => s + x.p.remaining, 0);
  const expenses = exps.reduce((s, e) => s + Number(e.amount), 0);
  const clients = {};
  rows.forEach(x => { const c = clients[x.i.clientName] = clients[x.i.clientName] || { name: x.i.clientName, n: 0, v: 0 }; c.n++; c.v += x.p.paid; });
  const items = {};
  all.forEach(i => i.items.forEach(it => { const k = items[it.name] = items[it.name] || { name: it.name, q: 0, v: 0 }; k.q += it.qty; k.v += it.qty * it.price; }));
  const cats = {};
  exps.forEach(e => cats[e.category] = (cats[e.category] || 0) + Number(e.amount));
  const palette = ['#2563eb', '#0ea5e9', '#d97706', '#059669', '#0284c7', '#db2777', '#64748b'];
  return {
    sales, invoiced, expenses, profit: sales - expenses, outstanding,
    count: paid.length, expCount: exps.length, openCount: open.length, invCount: all.length,
    topClients: Object.values(clients).filter(c => c.v > 0).sort((a, b) => b.v - a.v).slice(0, 5),
    topItems: Object.values(items).sort((a, b) => b.v - a.v).slice(0, 5),
    cats: Object.entries(cats).sort((a, b) => b[1] - a[1]).map(([name, value], i) => ({ name, value, color: palette[i % palette.length] }))
  };
}
function viewReports() {
  return `
  <div class="toolbar chip-row">
    <select class="input" id="repMode" style="width:auto">${RANGE_MODES.map(([v, l]) => `<option value="${v}">${l}</option>`).join('')}</select>
    <span class="chip-row" id="repInputs"></span>
    <button class="btn btn-primary btn-sm" id="repPDF" style="margin-left:auto">${IC.pdf} Export PDF</button>
  </div>
  <div id="repBody"></div>`;
}
MOUNT.reports = () => {
  const thisMonth = monthKey(Date.now());
  const state = {
    mode: 'month', month: thisMonth, year: String(new Date().getFullYear()),
    day: todayISO(), cFrom: thisMonth + '-01', cTo: todayISO()
  };
  const inputsHTML = () => {
    if (state.mode === 'custom') return `
      <input class="input" type="date" data-k="cFrom" value="${state.cFrom}" style="width:auto" />
      <span class="muted small">to</span>
      <input class="input" type="date" data-k="cTo" value="${state.cTo}" style="width:auto" />`;
    const type = { month: 'month', year: 'number', day: 'date' }[state.mode];
    const style = type === 'number' ? 'width:110px' : 'width:auto';
    return `<input class="input" type="${type}" data-k="${state.mode}" value="${state[state.mode]}" style="${style}" />`;
  };
  const draw = () => {
    const k = state.mode === 'custom' ? 'cFrom' : state.mode;
    const r = reportRange(state.mode, state[k], state.cTo);
    const d = reportData(r);
    $('#repBody').innerHTML = `
    <div class="grid g-4">
      <div class="stat"><span class="ic tone-brand">${IC.trend}</span><div><small>Revenue</small><b>${money(d.sales)}</b></div></div>
      <div class="stat"><span class="ic tone-amber">${IC.wallet}</span><div><small>Expenses</small><b>${money(d.expenses)}</b></div></div>
      <div class="stat"><span class="ic tone-green">${IC.check}</span><div><small>Net profit</small><b>${money(d.profit)}</b></div></div>
      <div class="stat"><span class="ic tone-red">${IC.clock}</span><div><small>Outstanding</small><b>${money(d.outstanding)}</b></div></div>
    </div>
    <div class="card mt-3 card-pad">
      <div class="row-between"><h3 style="font-size:1rem">${esc(r.label)}</h3>
        <b style="font-family:Sora;font-size:1.4rem;color:${d.profit >= 0 ? 'var(--green)' : 'var(--red)'}">${money(d.profit)}</b></div>
      <small class="muted">Revenue = ${money(d.sales)} received out of ${money(d.invoiced)} invoiced across ${d.invCount} invoice(s) · ${d.count} fully paid · ${d.expCount} expense(s).
        ${d.outstanding ? ` ${money(d.outstanding)} still outstanding on ${d.openCount} unpaid/partial invoice(s).` : ''}</small>
    </div>
    <div class="grid g-3 mt-3">
      <div class="card"><div class="card-head"><h3>Top clients</h3></div>
        ${d.topClients.length ? d.topClients.map(c => `<div class="li-row"><div class="li-main"><b>${esc(c.name || 'Walk-in Client')}</b><small>${c.n} invoice(s)</small></div><span class="li-amt">${money(c.v)}</span></div>`).join('') : `<div class="empty small" style="padding:2rem"><p>No payments received in this period</p></div>`}</div>
      <div class="card"><div class="card-head"><h3>Top items</h3></div>
        ${d.topItems.length ? d.topItems.map(c => `<div class="li-row"><div class="li-main"><b>${esc(c.name)}</b><small>${c.q} sold</small></div><span class="li-amt">${money(c.v)}</span></div>`).join('') : `<div class="empty small" style="padding:2rem"><p>No data</p></div>`}</div>
      <div class="card"><div class="card-head"><h3>Expense split</h3></div>
        <div class="card-pad donut-wrap">${donutChart(d.cats, 130)}
          <ul class="legend" style="flex:1;min-width:120px">${d.cats.map(c => `<li><span class="sw" style="background:${c.color}"></span>${esc(c.name)}<b>${money(c.value)}</b></li>`).join('') || '<li class="muted small">No expenses</li>'}</ul></div></div>
    </div>`;
    $('#repBody').dataset.r = JSON.stringify(r);
    $('#repBody').dataset.d = JSON.stringify(d);
  };
  $('#repInputs').innerHTML = inputsHTML();
  draw();
  $('#repMode').addEventListener('change', () => {
    state.mode = $('#repMode').value;
    $('#repInputs').innerHTML = inputsHTML();
    draw();
  });
  $('#repInputs').addEventListener('change', e => {
    const el = e.target.closest('[data-k]');
    if (!el || !el.value) return;
    state[el.dataset.k] = el.value;
    draw();
  });
  $('#repPDF').addEventListener('click', () => {
    const r = JSON.parse($('#repBody').dataset.r), d = JSON.parse($('#repBody').dataset.d);
    reportPDF(r, d).save(`report-${state.mode}-${(r.label.match(/\d{4}/) || [''])[0]}.pdf`);
    logEvent('system', `Report PDF exported for ${r.label}`);
    toast('Report PDF downloaded');
  });
};

/* ---------- History ---------- */
function viewHistory() {
  return `
  <div class="toolbar chip-row">
    <button class="chip active" data-f="">All</button>
    <button class="chip" data-f="invoice">Invoices</button>
    <button class="chip" data-f="expense">Expenses</button>
    <button class="chip" data-f="reminder">Reminders</button>
    <button class="chip" data-f="note">Notes</button>
    <button class="chip" data-f="system">System</button>
  </div>
  <div class="card card-pad" id="histWrap"></div>`;
}
MOUNT.history = () => {
  let f = '';
  const draw = () => {
    let list = getHistory();
    if (f) list = list.filter(h => h.type === f);
    $('#histWrap').innerHTML = list.length ? `<div class="timeline">${list.map(h => `
      <div class="tl-item t-${h.type}"><p>${esc(h.msg)}</p><small>${fmtDateTime(h.at)}</small></div>`).join('')}</div>`
      : emptyHTML(IC.clock, 'History is empty', 'As soon as you do something, it will be recorded here.');
  };
  draw();
  $$('#view .chip').forEach(c => c.addEventListener('click', () => {
    $$('#view .chip').forEach(x => x.classList.remove('active')); c.classList.add('active'); f = c.dataset.f; draw();
  }));
};

/* ---------- Settings ---------- */
function viewSettings() {
  const s = settings;
  return `
  <div class="settings-grid">
    <div>
      <div class="form-section">
        <h3><span class="step-n">1</span> Business profile</h3>
        <div class="field"><label>Business name</label><input class="input" id="sName" value="${esc(s.businessName)}" /></div>
        <div class="f-row">
          <div class="field"><label>Phone</label><input class="input" id="sPhone" value="${esc(s.phone)}" /></div>
          <div class="field"><label>Email</label><input class="input" id="sEmail" value="${esc(s.email)}" /></div>
        </div>
        <div class="field"><label>Website</label><input class="input" id="sWeb" value="${esc(s.website)}" placeholder="www.yourbusiness.com" /></div>
        <div class="field"><label>Address</label><textarea class="input" id="sAddr" style="min-height:60px">${esc(s.address)}</textarea></div>
        <div class="divider"></div>
        <p class="muted small" style="margin-bottom:.8rem"><b>Logo</b> — upload your custom logo to display on the top-left of every invoice. (Leave empty to use the clean modern emblem).</p>
        <div class="logo-row">
          <img id="sLogoPrev" src="${esc(s.logo)}" alt="" ${s.logo ? '' : 'hidden'} />
          <div>
            <input type="file" id="sLogoFile" accept="image/png,image/jpeg,image/webp" />
            <div><button type="button" class="btn btn-ghost btn-sm mt-1" id="sLogoRm" ${s.logo ? '' : 'hidden'}>Remove logo</button></div>
          </div>
        </div>
      </div>
      <div class="form-section">
        <h3><span class="step-n">2</span> Invoice defaults</h3>
        <div class="f-row">
          <div class="field"><label>Currency symbol</label><input class="input" id="sCur" value="${esc(s.currency)}" placeholder="Rs / $ / ₹" /></div>
          <div class="field"><label>Invoice prefix</label><input class="input" id="sPrefix" value="${esc(s.prefix)}" /></div>
        </div>
        <div class="divider"></div>
        <p class="muted small" style="margin-bottom:.8rem"><b>Invoice table</b> — every invoice prints this many rows. Unused cells show ------. Default is 7.</p>
        <div class="field"><label>Printed item rows</label>
          <input class="input" type="number" min="7" max="30" id="sRows" value="${invoiceRowCount()}" />
        </div>
        <div class="divider"></div>
        <p class="muted small" style="margin-bottom:.8rem"><b>Invoice footer</b> — printed as "Thanks for your business" plus the proprietor name.</p>
        <div class="field"><label>Proprietor / signature name</label><input class="input" id="sSign" value="${esc(s.signName)}" placeholder="Farrukh Iqbal" /></div>
        <button class="btn btn-primary" id="sSave">${IC.check} Save settings</button>
      </div>
    </div>
    <div>
      <div class="form-section">
        <h3><span class="step-n">3</span> Cloud sync (Firebase)
          <span class="sync-status ${cloudOk ? 'on' : ''}"><span class="dot"></span>${cloudOk ? 'auto-sync on' : 'offline / local'}</span></h3>
        <p class="muted small" style="margin-bottom:1rem">
          Sync is <b>fully automatic</b> — you do not have to press anything. After every change the data is saved to <b>Firebase Firestore</b> by itself, and it is fetched back from the cloud on its own when you open / refresh the app. The same data on any device or browser. If there is no internet, the app runs offline and syncs by itself as soon as it connects.
        </p>
        <dl class="kv" style="margin-bottom:.4rem">
          <dt>Mode</dt><dd>Automatic (no manual push/pull)</dd>
          <dt>Backend</dt><dd>Firebase Firestore · ${esc((window.FBSync && window.FBSync.projectId) || 'eppos-41139')} · appdata/snapshot</dd>
          <dt>Last synced</dt><dd>${lastSyncAt ? fmtDate(lastSyncAt) : '—'}</dd>
        </dl>
      </div>
      <div class="form-section">
        <h3><span class="step-n">4</span> Data summary</h3>
        <dl class="kv">
          <dt>Invoices</dt><dd>${getInvoices().length}</dd>
          <dt>Expenses</dt><dd>${getExpenses().length}</dd>
          <dt>Reminders</dt><dd>${getReminders().length}</dd>
          <dt>Notes</dt><dd>${getNotes().length}</dd>
          <dt>History events</dt><dd>${getHistory().length}</dd>
        </dl>
      </div>
      <div class="danger-zone">
        <h3>Danger zone</h3>
        <p>All local data (invoices, expenses, notes, whiteboard, history) will be deleted. This cannot be undone.</p>
        <button class="btn btn-danger btn-sm" id="sWipe">${IC.trash} Clear all data</button>
      </div>
    </div>
  </div>`;
}
MOUNT.settings = () => {
  let logoDraft = null;
  const logoPrev = $('#sLogoPrev'), logoRm = $('#sLogoRm');
  $('#sLogoFile').addEventListener('change', e => {
    const file = e.target.files[0];
    if (!file) return;
    if (file.size > 2 * 1024 * 1024) { e.target.value = ''; return toast('Logo file too large (max 2 MB)', 'err'); }
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      const sc = Math.min(1, 320 / img.width, 320 / img.height);
      const cv = document.createElement('canvas');
      cv.width = Math.max(1, Math.round(img.width * sc)); cv.height = Math.max(1, Math.round(img.height * sc));
      cv.getContext('2d').drawImage(img, 0, 0, cv.width, cv.height);
      URL.revokeObjectURL(url);
      logoDraft = cv.toDataURL(file.type === 'image/jpeg' ? 'image/jpeg' : 'image/png', 0.9);
      logoPrev.src = logoDraft; logoPrev.hidden = false; logoRm.hidden = false;
      if (logoDraft.length > 400 * 1024) toast('Logo is quite heavy — a simpler image keeps cloud sync fast', 'info');
    };
    img.onerror = () => { URL.revokeObjectURL(url); e.target.value = ''; toast('Could not read that image', 'err'); };
    img.src = url;
  });
  logoRm.addEventListener('click', () => {
    logoDraft = ''; logoPrev.src = ''; logoPrev.hidden = true; logoRm.hidden = true; $('#sLogoFile').value = '';
  });
  $('#sSave').addEventListener('click', () => {
    settings = {
      ...settings,
      businessName: $('#sName').value.trim() || 'My Business',
      phone: $('#sPhone').value.trim(), email: $('#sEmail').value.trim(), address: $('#sAddr').value.trim(),
      website: $('#sWeb').value.trim(),
      currency: $('#sCur').value.trim() || 'Rs', prefix: $('#sPrefix').value.trim() || 'INV',
      signName: $('#sSign').value.trim(),
      invoiceRows: Math.max(7, Math.min(30, Math.round(Number($('#sRows').value) || 7)))
    };
    if (logoDraft !== null) settings.logo = logoDraft;
    saveSettings();
    logEvent('system', 'Settings updated');
    refreshSidebarBiz();
    toast('Settings saved');
  });
  $('#sWipe').addEventListener('click', async () => {
    if (await confirmBox('Clear ALL data?', 'Invoices, expenses, reminders, notes, whiteboard and history — all deleted.', 'Yes, clear everything')) {
      Object.values(K).forEach(k => localStorage.removeItem(k));
      settings = { ...DEFAULT_SETTINGS };
      saveSettings();
      // set the cloud to the cleared state too, otherwise the old data comes back on refresh
      localStorage.setItem('nv_savedAt', String(Date.now()));
      syncReady = true;
      await pushToCloud(true);
      refreshSidebarBiz();
      toast('All data cleared');
      location.hash = '#/dashboard';
      render();
    }
  });
};

/* ---------------- sidebar biz info ---------------- */
function refreshSidebarBiz() {
  $('#sideBizName').textContent = settings.businessName;
  $('#sideBizAvatar').textContent = (settings.businessName[0] || 'B').toUpperCase();
  $('#sideBizTag').textContent = cloudOk ? '' : '';
}

/* ---------------- reminder notifications ---------------- */
setInterval(() => {
  const notified = new Set(load(K.notified, []));
  const now = Date.now();
  getReminders().forEach(r => {
    if (r.done || notified.has(r.id)) return;
    const t = new Date(r.datetime).getTime();
    if (t <= now) {
      notified.add(r.id);
      toast('Reminder: ' + r.title, 'info');
      if ('Notification' in window && Notification.permission === 'granted') {
        try { new Notification('NovaPOS reminder', { body: r.title }); } catch { }
      }
    }
  });
  save(K.notified, [...notified].slice(-200));
  updateReminderPill();
  checkOutstanding();
}, 30000);

/* ---------------- boot ---------------- */
if (!location.hash) location.hash = '#/dashboard';
refreshSidebarBiz();
render();
(async () => {
  const adopted = await pullFromCloud(true);
  syncReady = true;
  if (!adopted && localSavedAt()) await pushToCloud(true);
  checkOutstanding();
})();
if ('Notification' in window && Notification.permission === 'default') {
  setTimeout(() => { try { Notification.requestPermission(); } catch { } }, 4000);
}
