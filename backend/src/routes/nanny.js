'use strict';
const config = require('../config');
const { one, all, run, tx } = require('../db');
const { fail, str, int, coord } = require('../lib/http');
const { authenticate } = require('../lib/auth');
const { serializeOrder, rating } = require('../domain');
const { KYC } = require('./files');
const { distanceM } = require('../lib/geo');

const REQUIRED_DOCS = ['photo', ...KYC];
const MIN_WITHDRAW = 10_000;

function profile(userId) {
  const n = one('SELECT * FROM nannies WHERE user_id = ?', userId);
  if (!n) fail(404, 'Профиль няни не найден');
  const docs = all('SELECT id, kind, mime, created_at FROM documents WHERE user_id = ? ORDER BY id', userId);
  return {
    full_name: n.full_name,
    age: n.age,
    experience: n.experience,
    about: n.about,
    price: n.price,
    schedule: n.schedule,
    status: n.status,
    reject_reason: n.reject_reason,
    med_ok: Boolean(n.med_ok),
    police_ok: Boolean(n.police_ok),
    online: Boolean(n.online),
    rating: rating(n),
    reviews_count: n.rating_count,
    balance: n.balance,
    docs,
  };
}

module.exports = (r) => {
  r.get('/api/nanny/profile', (ctx) => profile(authenticate(ctx, ['nanny']).id));

  r.put('/api/nanny/profile', async (ctx) => {
    const user = authenticate(ctx, ['nanny']);
    const b = await ctx.json();
    const fullName = str(b.full_name, 'ФИО', { min: 5, max: 80, required: true });
    run(
      'UPDATE nannies SET full_name = ?, age = ?, experience = ?, about = ?, price = ?, schedule = ? WHERE user_id = ?',
      fullName,
      int(b.age, 'Возраст', 18, 75),
      int(b.experience, 'Опыт', 0, 55),
      str(b.about, 'О себе', { max: 1000 }),
      int(b.price, 'Стоимость часа', 10_000, 1_000_000),
      str(b.schedule, 'Расписание', { max: 300 }),
      user.id
    );
    run('UPDATE users SET name = ? WHERE id = ?', fullName, user.id);
    return profile(user.id);
  });

  r.post('/api/nanny/submit', (ctx) => {
    const user = authenticate(ctx, ['nanny']);
    const n = one('SELECT * FROM nannies WHERE user_id = ?', user.id);
    if (!n) fail(404, 'Профиль няни не найден');
    if (!['draft', 'rejected'].includes(n.status)) fail(409, 'Анкета уже отправлена');
    if (!n.full_name || !n.age || n.experience == null || !n.price) fail(400, 'Заполните анкету: ФИО, возраст, опыт и стоимость');
    const have = new Set(all('SELECT kind FROM documents WHERE user_id = ?', user.id).map((d) => d.kind));
    const missing = REQUIRED_DOCS.filter((k) => !have.has(k));
    if (missing.length) fail(400, 'Загрузите все документы: ' + missing.join(', '));
    run("UPDATE nannies SET status = 'pending', reject_reason = NULL, submitted_at = ? WHERE user_id = ?", Date.now(), user.id);
    return profile(user.id);
  });

  r.post('/api/nanny/online', async (ctx) => {
    const user = authenticate(ctx, ['nanny']);
    const b = await ctx.json();
    const n = one('SELECT status FROM nannies WHERE user_id = ?', user.id);
    if (n?.status !== 'approved') fail(403, 'Аккаунт ещё не прошёл проверку');
    const online = Boolean(b.online);
    const p = coord(b.lat, b.lng, { required: online });
    if (p) run('UPDATE nannies SET online = ?, lat = ?, lng = ?, loc_at = ? WHERE user_id = ?', online, p.lat, p.lng, Date.now(), user.id);
    else run('UPDATE nannies SET online = ? WHERE user_id = ?', online, user.id);
    return { online };
  });

  // Пакет GPS-точек: приложение копит их офлайн и отправляет пачкой.
  r.post('/api/nanny/location', async (ctx) => {
    const user = authenticate(ctx, ['nanny']);
    const b = await ctx.json();
    const raw = Array.isArray(b.points) ? b.points : [b];
    if (!raw.length || raw.length > 500) fail(400, 'Ожидается от 1 до 500 точек');
    const now = Date.now();
    const points = raw
      .map((p) => ({ ...coord(p.lat, p.lng), ts: Math.min(Number(p.ts) || now, now) }))
      .sort((a, b2) => a.ts - b2.ts);
    const last = points[points.length - 1];
    const active = all(
      "SELECT id FROM orders WHERE nanny_id = ? AND status IN ('accepted','on_the_way','arrived','in_progress')",
      user.id
    );
    tx(() => {
      run('UPDATE nannies SET lat = ?, lng = ?, loc_at = ? WHERE user_id = ?', last.lat, last.lng, last.ts, user.id);
      for (const o of active) {
        for (const p of points) run('INSERT INTO track(order_id, lat, lng, ts) VALUES (?,?,?,?)', o.id, p.lat, p.lng, p.ts);
      }
    });
    return { ok: true, active_orders: active.map((o) => o.id) };
  });

  r.get('/api/nanny/incoming', (ctx) => {
    const user = authenticate(ctx, ['nanny']);
    const rows = all(
      "SELECT * FROM orders WHERE nanny_id = ? AND status = 'pending' AND created_at > ? ORDER BY created_at",
      user.id, Date.now() - config.acceptTimeoutMs
    );
    const me = one('SELECT lat, lng FROM nannies WHERE user_id = ?', user.id);
    return rows.map((o) => ({
      ...serializeOrder(o, user),
      distance_m: me?.lat != null ? distanceM(me.lat, me.lng, o.lat, o.lng) : null,
    }));
  });

  r.get('/api/nanny/wallet', (ctx) => {
    const user = authenticate(ctx, ['nanny']);
    const n = one('SELECT balance FROM nannies WHERE user_id = ?', user.id);
    const earned = one("SELECT COALESCE(SUM(amount), 0) AS s FROM wallet_tx WHERE nanny_id = ? AND kind = 'earning'", user.id).s;
    return {
      balance: n?.balance ?? 0,
      total_earned: earned,
      commission_percent: Math.round(config.commission * 100),
      min_withdraw: MIN_WITHDRAW,
      transactions: all('SELECT id, amount, kind, order_id, created_at FROM wallet_tx WHERE nanny_id = ? ORDER BY id DESC LIMIT 100', user.id),
      withdrawals: all('SELECT id, amount, card_mask, status, created_at, processed_at FROM withdrawals WHERE nanny_id = ? ORDER BY id DESC LIMIT 50', user.id),
    };
  });

  r.post('/api/nanny/withdraw', async (ctx) => {
    const user = authenticate(ctx, ['nanny']);
    const b = await ctx.json();
    const amount = int(b.amount, 'Сумма', MIN_WITHDRAW, 1_000_000_000);
    const card = one('SELECT * FROM cards WHERE id = ? AND user_id = ?', Number(b.card_id), user.id);
    if (!card) fail(400, 'Выберите карту для вывода');
    tx(() => {
      const n = one('SELECT balance FROM nannies WHERE user_id = ?', user.id);
      if (!n || n.balance < amount) fail(400, 'Недостаточно средств на балансе');
      const now = Date.now();
      run('UPDATE nannies SET balance = balance - ? WHERE user_id = ?', amount, user.id);
      run('INSERT INTO withdrawals(nanny_id, amount, card_mask, status, created_at) VALUES (?, ?, ?, \'pending\', ?)', user.id, amount, card.mask, now);
      run("INSERT INTO wallet_tx(nanny_id, amount, kind, created_at) VALUES (?, ?, 'withdrawal', ?)", user.id, -amount, now);
    });
    return { ok: true };
  });
};
