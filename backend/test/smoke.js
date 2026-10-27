'use strict';
// Сквозной прогон основного сценария на свежей базе:
//   node test/smoke.js            — поднимет сервер сам во временной папке
//   BASE=https://... node test/smoke.js  — прогон против уже запущенного сервера (нужен ADMIN_PASSWORD)
const { spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const assert = require('node:assert/strict');

const PORT = 3999;
let BASE = process.env.BASE;
let server;
let dataDir;

async function api(method, url, { token, body, raw } = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (body) headers['Content-Type'] = 'application/json';
  const r = await fetch(BASE + url, { method, headers, body: raw ?? (body ? JSON.stringify(body) : undefined) });
  const text = await r.text();
  let data;
  try { data = JSON.parse(text); } catch { data = text; }
  if (!r.ok) {
    const err = new Error(`${method} ${url} -> ${r.status}: ${data?.error ?? text}`);
    err.status = r.status;
    throw err;
  }
  return data;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const rnd = () => String(Math.floor(Math.random() * 1e7)).padStart(7, '0');
const JPEG = Buffer.concat([Buffer.from([0xff, 0xd8, 0xff, 0xe0]), Buffer.alloc(200, 1)]);

async function login(phone, name, role) {
  const otp = await api('POST', '/api/auth/otp', { body: { phone } });
  assert.ok(otp.demo_code, 'ожидался demo_code в демо-режиме');
  const v = await api('POST', '/api/auth/verify', { body: { phone, code: otp.demo_code } });
  const me = await api('PATCH', '/api/me', { token: v.access, body: { name, role } });
  assert.equal(me.role, role);
  return { ...v, me };
}

async function main() {
  if (!BASE) {
    dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'nanny-'));
    BASE = `http://127.0.0.1:${PORT}`;
    server = spawn(process.execPath, ['--disable-warning=ExperimentalWarning', path.join(__dirname, '..', 'src', 'index.js')], {
      env: { ...process.env, PORT: String(PORT), DATA_DIR: dataDir, ADMIN_PASSWORD: 'test-admin' },
      stdio: ['ignore', 'inherit', 'inherit'],
    });
    for (let i = 0; i < 50; i++) {
      try { await api('GET', '/health'); break; } catch { await sleep(100); }
    }
  }
  const step = (s) => console.log('✓', s);

  await api('GET', '/health');
  step('health');

  const parent = await login(`+99890${rnd()}`, 'Азиза', 'parent');
  const nanny = await login(`+99891${rnd()}`, 'Тестовая Няня', 'nanny');
  step('вход по OTP для родителя и няни');

  await assert.rejects(api('POST', '/api/auth/verify', { body: { phone: '+998901112233', code: '0000' } }), /истёк/);
  const refreshed = await api('POST', '/api/auth/refresh', { body: { refresh: parent.refresh } });
  await assert.rejects(api('POST', '/api/auth/refresh', { body: { refresh: parent.refresh } }), /401/);
  parent.access = refreshed.access;
  step('refresh-токен ротируется');

  await api('PUT', '/api/nanny/profile', {
    token: nanny.access,
    body: { full_name: 'Тестова Няня Ивановна', age: 29, experience: 5, about: 'Люблю детей', price: 50000, schedule: 'Пн-Пт' },
  });
  await assert.rejects(api('POST', '/api/nanny/submit', { token: nanny.access }), /документы/);
  for (const kind of ['photo', 'passport', 'selfie', 'medbook', 'police', 'cert']) {
    await api('PUT', `/api/files/${kind}`, { token: nanny.access, raw: JPEG });
  }
  await assert.rejects(api('PUT', '/api/files/passport', { token: nanny.access, raw: Buffer.from('not an image at all') }), /JPEG/);
  let prof = await api('POST', '/api/nanny/submit', { token: nanny.access });
  assert.equal(prof.status, 'pending');
  await assert.rejects(api('POST', '/api/nanny/online', { token: nanny.access, body: { online: true, lat: 41.31, lng: 69.27 } }), /403/);
  step('KYC: анкета + документы отправлены, до одобрения выйти на линию нельзя');

  const adminPass = process.env.ADMIN_PASSWORD || 'test-admin';
  const { access: admin } = await api('POST', '/api/admin/login', { body: { password: adminPass } });
  const pending = await api('GET', '/api/admin/nannies?status=pending', { token: admin });
  assert.ok(pending.some((n) => n.id === nanny.me.id));
  const detail = await api('GET', `/api/admin/nannies/${nanny.me.id}`, { token: admin });
  assert.equal(detail.docs.length, 6);
  const file = await fetch(`${BASE}/api/files/${detail.docs[0].id}`, { headers: { Authorization: `Bearer ${admin}` } });
  assert.equal(file.status, 200);
  assert.ok(Buffer.from(await file.arrayBuffer()).equals(JPEG), 'файл расшифровывается без потерь');
  const passportId = detail.docs.find((x) => x.kind === 'passport').id;
  assert.equal((await fetch(`${BASE}/api/files/${passportId}`, { headers: { Authorization: `Bearer ${parent.access}` } })).status, 404);
  await api('POST', `/api/admin/nannies/${nanny.me.id}/approve`, { token: admin, body: { med_ok: true, police_ok: true } });
  step('модератор видит документы (зашифрованы, родителю паспорт недоступен) и одобряет');

  const home = { lat: 41.3111, lng: 69.2797 };
  await api('POST', '/api/nanny/online', { token: nanny.access, body: { online: true, lat: home.lat + 0.01, lng: home.lng } });
  const feed = await api('GET', `/api/nannies?lat=${home.lat}&lng=${home.lng}&radius_km=5`, { token: parent.access });
  assert.equal(feed.items[0].id, nanny.me.id, 'реальная няня первой в ленте');
  assert.ok(feed.items[0].med_ok && feed.items[0].police_ok);
  const far = await api('GET', `/api/nannies?lat=${home.lat}&lng=${home.lng}&radius_km=1`, { token: parent.access });
  assert.ok(!far.items.some((n) => n.id === nanny.me.id), 'радиус 1 км отсекает няню в 1.1 км');
  step(`лента: ${feed.items.length} нянь в 5 км, фильтр радиуса работает`);

  const orderBody = { nanny_id: nanny.me.id, type: 'now', children_count: 2, children_ages: '3 и 5 лет', notes: 'Аллергия на орехи', address: 'ул. Навои, 10', ...home };
  await assert.rejects(api('POST', '/api/orders', { token: parent.access, body: orderBody }), /карту/);
  await assert.rejects(api('POST', '/api/cards', { token: parent.access, body: { number: '4111111111111111', expiry: '12/30' } }), /Uzcard/);
  const card = await api('POST', '/api/cards', { token: parent.access, body: { number: '8600123412341234', expiry: '12/30' } });
  assert.equal(card.type, 'uzcard');
  let order = await api('POST', '/api/orders', { token: parent.access, body: orderBody });
  assert.equal(order.status, 'pending');
  assert.equal(order.hold_amount, 100000);
  step('заказ создан, холд за 2 часа = 100 000 сум');

  const incoming = await api('GET', '/api/nanny/incoming', { token: nanny.access });
  assert.equal(incoming[0].id, order.id);
  assert.ok(incoming[0].distance_m > 1000);
  order = await api('POST', `/api/orders/${order.id}/accept`, { token: nanny.access });
  assert.equal(order.status, 'accepted');
  assert.ok(order.parent.phone, 'после принятия стороны видят телефоны');

  order = await api('POST', `/api/orders/${order.id}/status`, { token: nanny.access, body: { status: 'on_the_way' } });
  await api('POST', '/api/nanny/location', { token: nanny.access, body: { points: [{ lat: home.lat + 0.005, lng: home.lng, ts: Date.now() - 1000 }, { lat: home.lat + 0.002, lng: home.lng }] } });
  order = await api('GET', `/api/orders/${order.id}`, { token: parent.access });
  assert.equal(order.track.length, 2);
  assert.ok(order.nanny_location);
  await assert.rejects(api('POST', `/api/orders/${order.id}/status`, { token: nanny.access, body: { status: 'arrived', lat: home.lat + 0.002, lng: home.lng } }), /не на месте/);
  order = await api('POST', `/api/orders/${order.id}/status`, { token: nanny.access, body: { status: 'arrived', lat: home.lat + 0.0005, lng: home.lng } });
  assert.equal(order.status, 'arrived');
  order = await api('POST', `/api/orders/${order.id}/status`, { token: nanny.access, body: { status: 'in_progress' } });
  assert.ok(order.started_at);
  step('статусы: принят → выехала → (сверка 100 м) на месте → в работе, родитель видит трек');

  await api('POST', `/api/orders/${order.id}/messages`, { token: parent.access, body: { text: 'Здравствуйте!' } });
  await api('POST', `/api/orders/${order.id}/messages`, { token: nanny.access, body: { text: 'Добрый день, я на месте' } });
  const chats = await api('GET', '/api/chats', { token: parent.access });
  assert.equal(chats[0].unread, 1);
  const msgs = await api('GET', `/api/orders/${order.id}/messages?after=0`, { token: parent.access });
  assert.equal(msgs.length, 2);
  assert.equal((await api('GET', '/api/chats', { token: parent.access }))[0].unread, 0);
  step('чат и счётчик непрочитанных');

  const sos = await api('POST', '/api/sos', { token: parent.access, body: { order_id: order.id, ...home } });
  const sosList = await api('GET', '/api/admin/sos', { token: admin });
  assert.equal(sosList[0].id, sos.id);
  assert.equal(sosList[0].order.id, order.id);
  step('SOS долетает до админки с координатами и данными заказа');

  order = await api('POST', `/api/orders/${order.id}/status`, { token: nanny.access, body: { status: 'completed' } });
  assert.equal(order.status, 'completed');
  assert.equal(order.total, 50000);
  assert.equal(order.commission, 6000);
  assert.equal(order.nanny_earning, 44000);
  const wallet = await api('GET', '/api/nanny/wallet', { token: nanny.access });
  assert.equal(wallet.balance, 44000);
  step('завершение: минимум 1 час, комиссия 12%, няне зачислено 44 000');

  order = await api('POST', `/api/orders/${order.id}/review`, { token: parent.access, body: { rating: 5, text: 'Отлично!' } });
  assert.equal(order.review.rating, 5);
  const nd = await api('GET', `/api/nannies/${nanny.me.id}`, { token: parent.access });
  assert.equal(nd.rating, 5);
  assert.equal(nd.reviews[0].text, 'Отлично!');
  step('отзыв и рейтинг');

  const ncard = await api('POST', '/api/cards', { token: nanny.access, body: { number: '9860123412341234', expiry: '01/29' } });
  await assert.rejects(api('POST', '/api/nanny/withdraw', { token: nanny.access, body: { amount: 50000, card_id: ncard.id } }), /Недостаточно/);
  await api('POST', '/api/nanny/withdraw', { token: nanny.access, body: { amount: 40000, card_id: ncard.id } });
  const wds = await api('GET', '/api/admin/withdrawals', { token: admin });
  await api('POST', `/api/admin/withdrawals/${wds[0].id}/paid`, { token: admin });
  assert.equal((await api('GET', '/api/nanny/wallet', { token: nanny.access })).balance, 4000);
  step('вывод средств на Humo и подтверждение выплаты');

  const company = await api('POST', '/api/admin/companies', { token: admin, body: { name: 'Uzum', code: 'uzum2026' } });
  const me = await api('POST', '/api/me/company', { token: parent.access, body: { code: 'UZUM2026' } });
  assert.equal(me.company.id, company.id);
  step('B2B: компания создана, родитель привязан по коду');

  const demo = feed.items.find((n) => n.is_demo);
  if (demo) {
    let o = await api('POST', '/api/orders', { token: parent.access, body: { ...orderBody, nanny_id: demo.id, corporate: true } });
    assert.ok(o.corporate);
    for (let i = 0; i < 12 && o.status !== 'on_the_way'; i++) {
      await sleep(1500);
      o = await api('GET', `/api/orders/${o.id}`, { token: parent.access });
    }
    assert.equal(o.status, 'on_the_way');
    await sleep(3500);
    o = await api('GET', `/api/orders/${o.id}`, { token: parent.access });
    assert.ok(o.track.length >= 2, 'демо-няня двигается');
    await api('POST', `/api/orders/${o.id}/cancel`, { token: parent.access, body: { reason: 'тест' } });
    step('демо-няня сама принимает корпоративный заказ и едет по карте; отмена работает');
  }

  const stats = await api('GET', '/api/admin/stats', { token: admin });
  assert.equal(stats.money.revenue, 6000);
  step(`статистика: выручка платформы ${stats.money.revenue}, SOS открыто ${stats.sos_open}`);

  await api('POST', `/api/admin/users/${parent.me.id}/block`, { token: admin, body: { blocked: true } });
  await assert.rejects(api('GET', '/api/me', { token: parent.access }), /403/);
  step('блокировка пользователя');

  console.log('\nВсе проверки пройдены');
}

main()
  .catch((e) => {
    console.error('\n✗', e.message);
    process.exitCode = 1;
  })
  .finally(() => {
    if (server) server.kill();
    if (dataDir) setTimeout(() => fs.rmSync(dataDir, { recursive: true, force: true }), 300);
  });
