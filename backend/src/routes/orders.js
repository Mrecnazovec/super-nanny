'use strict';
const config = require('../config');
const { one, all, run } = require('../db');
const { fail, str, int, coord } = require('../lib/http');
const { authenticate, rateLimit } = require('../lib/auth');
const { distanceM } = require('../lib/geo');
const { alertAdmins } = require('../lib/notify');
const d = require('../domain');

const CHAT_CLOSED = ['pending', 'declined', 'expired'];

module.exports = (r) => {
  // ---------- создание заказа (свайп вправо) ----------
  r.post('/api/orders', async (ctx) => {
    const user = authenticate(ctx, ['parent']);
    const b = await ctx.json();
    rateLimit('order:' + user.id, 20, 10 * 60_000);

    const nanny = one('SELECT * FROM nannies WHERE user_id = ?', Number(b.nanny_id));
    if (!nanny || !d.isNannyAvailable(nanny)) fail(409, 'Няня сейчас недоступна, выберите другую');
    if (one("SELECT 1 FROM orders WHERE parent_id = ? AND nanny_id = ? AND status = 'pending'", user.id, nanny.user_id)) {
      fail(409, 'Вы уже отправили заявку этой няне — дождитесь ответа');
    }

    const type = b.type === 'scheduled' ? 'scheduled' : 'now';
    let scheduledAt = null;
    if (type === 'scheduled') {
      scheduledAt = Number(b.scheduled_at);
      const now = Date.now();
      if (!Number.isFinite(scheduledAt) || scheduledAt < now + 15 * 60_000 || scheduledAt > now + 30 * 24 * 3600_000) {
        fail(400, 'Время заказа — не раньше чем через 15 минут и не позже чем через 30 дней');
      }
    }
    const pos = coord(b.lat, b.lng);

    let companyId = null;
    let cardId = null;
    const corporate = Boolean(b.corporate);
    if (corporate) {
      if (!user.company_id) fail(400, 'Профиль не привязан к компании');
      companyId = user.company_id;
    } else {
      const card = b.card_id
        ? one('SELECT id FROM cards WHERE id = ? AND user_id = ?', Number(b.card_id), user.id)
        : one('SELECT id FROM cards WHERE user_id = ? ORDER BY id LIMIT 1', user.id);
      if (!card) fail(400, 'Привяжите карту Uzcard или Humo для оплаты');
      cardId = card.id;
    }

    const now = Date.now();
    const id = run(
      `INSERT INTO orders(parent_id, nanny_id, type, scheduled_at, children_count, children_ages, notes, address,
                          lat, lng, corporate, company_id, card_id, price, hold_amount, status, created_at, updated_at)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?, 'pending', ?, ?)`,
      user.id, nanny.user_id, type, scheduledAt,
      int(b.children_count, 'Количество детей', 1, 6),
      str(b.children_ages, 'Возраст детей', { max: 100 }),
      str(b.notes, 'Особые отметки', { max: 500 }),
      str(b.address, 'Адрес', { max: 200, required: true }),
      pos.lat, pos.lng, corporate, companyId, cardId,
      nanny.price, nanny.price * config.holdHours, now, now
    ).lastInsertRowid;
    return d.serializeOrder(one('SELECT * FROM orders WHERE id = ?', id), user, { detail: true });
  });

  r.get('/api/orders', (ctx) => {
    const user = authenticate(ctx, ['parent', 'nanny']);
    const col = user.role === 'parent' ? 'parent_id' : 'nanny_id';
    const scope = ctx.query.scope || 'all';
    let where = '';
    if (scope === 'active') where = " AND status IN ('pending','accepted','on_the_way','arrived','in_progress')";
    if (scope === 'history') where = " AND status IN ('completed','cancelled','declined','expired')";
    // Няне не показываем заявки, которые она не приняла.
    if (user.role === 'nanny') where += " AND status NOT IN ('pending','declined','expired')";
    const rows = all(`SELECT * FROM orders WHERE ${col} = ?${where} ORDER BY created_at DESC LIMIT 100`, user.id);
    return rows.map((o) => d.serializeOrder(o, user));
  });

  r.get('/api/orders/:id', (ctx) => {
    const user = authenticate(ctx, ['parent', 'nanny', 'admin']);
    return d.serializeOrder(d.getOrderFor(ctx, ctx.params.id), user, { detail: true });
  });

  // ---------- действия няни ----------
  r.post('/api/orders/:id/accept', (ctx) => {
    const user = authenticate(ctx, ['nanny']);
    const o = d.getOrderFor(ctx, ctx.params.id);
    if (o.nanny_id !== user.id) fail(403, 'Нет доступа');
    if (o.type === 'now' && d.isNannyBusy(user.id)) fail(409, 'Сначала завершите текущий заказ');
    return d.serializeOrder(d.acceptOrder(o.id), user, { detail: true });
  });

  r.post('/api/orders/:id/decline', (ctx) => {
    const user = authenticate(ctx, ['nanny']);
    const o = d.getOrderFor(ctx, ctx.params.id);
    if (o.nanny_id !== user.id) fail(403, 'Нет доступа');
    if (o.status !== 'pending') fail(409, 'Заказ уже неактуален');
    run("UPDATE orders SET status = 'declined', updated_at = ? WHERE id = ?", Date.now(), o.id);
    return { ok: true };
  });

  // Принять -> Выехала -> На месте (сверка гео, 100 м) -> Начать работу -> Завершить работу
  r.post('/api/orders/:id/status', async (ctx) => {
    const user = authenticate(ctx, ['nanny']);
    const b = await ctx.json();
    const o = d.getOrderFor(ctx, ctx.params.id);
    if (o.nanny_id !== user.id) fail(403, 'Нет доступа');
    const next = d.NEXT_STATUS[o.status];
    if (!next || b.status !== next) fail(409, 'Недопустимая смена статуса');

    const p = coord(b.lat, b.lng, { required: false });
    if (p) {
      const now = Date.now();
      run('UPDATE nannies SET lat = ?, lng = ?, loc_at = ? WHERE user_id = ?', p.lat, p.lng, now, user.id);
      run('INSERT INTO track(order_id, lat, lng, ts) VALUES (?,?,?,?)', o.id, p.lat, p.lng, now);
    }

    if (next === 'on_the_way' && d.isNannyBusy(user.id)) fail(409, 'Сначала завершите текущий заказ');
    if (next === 'arrived') {
      const loc = p || one('SELECT lat, lng FROM nannies WHERE user_id = ?', user.id);
      if (!loc || loc.lat == null) fail(400, 'Не удалось определить ваше местоположение');
      const dist = distanceM(loc.lat, loc.lng, o.lat, o.lng);
      if (dist > config.arrivalRadiusM) fail(409, `Вы ещё не на месте: до адреса ${dist} м`);
    }

    if (next === 'completed') d.completeOrder(o.id);
    else d.setStatus(o.id, next);
    return d.serializeOrder(one('SELECT * FROM orders WHERE id = ?', o.id), user, { detail: true });
  });

  r.post('/api/orders/:id/cancel', async (ctx) => {
    const user = authenticate(ctx, ['parent', 'nanny']);
    const b = await ctx.json();
    const o = d.getOrderFor(ctx, ctx.params.id);
    d.cancelOrder(o, user.role, str(b.reason, 'Причина', { max: 300 }));
    return d.serializeOrder(one('SELECT * FROM orders WHERE id = ?', o.id), user, { detail: true });
  });

  r.post('/api/orders/:id/review', async (ctx) => {
    const user = authenticate(ctx, ['parent']);
    const b = await ctx.json();
    const o = d.getOrderFor(ctx, ctx.params.id);
    if (o.status !== 'completed') fail(409, 'Отзыв можно оставить после завершения заказа');
    if (one('SELECT 1 FROM reviews WHERE order_id = ?', o.id)) fail(409, 'Отзыв уже оставлен');
    const rating = int(b.rating, 'Оценка', 1, 5);
    run(
      'INSERT INTO reviews(order_id, parent_id, nanny_id, rating, text, created_at) VALUES (?,?,?,?,?,?)',
      o.id, user.id, o.nanny_id, rating, str(b.text, 'Отзыв', { max: 1000 }), Date.now()
    );
    run('UPDATE nannies SET rating_sum = rating_sum + ?, rating_count = rating_count + 1 WHERE user_id = ?', rating, o.nanny_id);
    return d.serializeOrder(one('SELECT * FROM orders WHERE id = ?', o.id), user, { detail: true });
  });

  // ---------- чат по заказу ----------
  r.get('/api/chats', (ctx) => {
    const user = authenticate(ctx, ['parent', 'nanny']);
    const rows = all(
      `SELECT o.*, (SELECT MAX(id) FROM messages m WHERE m.order_id = o.id) AS last_msg
         FROM orders o
        WHERE (o.parent_id = ? OR o.nanny_id = ?) AND o.status NOT IN ('pending','declined','expired')
        ORDER BY COALESCE(last_msg, 0) DESC, o.updated_at DESC LIMIT 50`,
      user.id, user.id
    );
    return rows.map((o) => {
      const s = d.serializeOrder(o, user);
      const last = o.last_msg ? one('SELECT sender_id, text, created_at FROM messages WHERE id = ?', o.last_msg) : null;
      const other = user.role === 'parent' ? s.nanny : s.parent;
      return {
        order_id: o.id,
        status: o.status,
        title: other.name || 'Без имени',
        photo_id: user.role === 'parent' ? s.nanny.photo_id : null,
        unread: s.unread,
        last_message: last ? { text: last.text, created_at: last.created_at, mine: last.sender_id === user.id } : null,
        updated_at: last?.created_at ?? o.updated_at,
      };
    });
  });

  r.get('/api/orders/:id/messages', (ctx) => {
    const user = authenticate(ctx, ['parent', 'nanny', 'admin']);
    const o = d.getOrderFor(ctx, ctx.params.id);
    const after = Number(ctx.query.after) || 0;
    const msgs = all('SELECT id, sender_id, text, created_at FROM messages WHERE order_id = ? AND id > ? ORDER BY id LIMIT 200', o.id, after);
    if (msgs.length && user.role !== 'admin') {
      run(
        `INSERT INTO chat_reads(order_id, user_id, last_id) VALUES (?,?,?)
         ON CONFLICT(order_id, user_id) DO UPDATE SET last_id = MAX(last_id, excluded.last_id)`,
        o.id, user.id, msgs[msgs.length - 1].id
      );
    }
    return msgs.map((m) => ({ ...m, mine: m.sender_id === user.id }));
  });

  r.post('/api/orders/:id/messages', async (ctx) => {
    const user = authenticate(ctx, ['parent', 'nanny']);
    const o = d.getOrderFor(ctx, ctx.params.id);
    if (CHAT_CLOSED.includes(o.status)) fail(409, 'Чат доступен после принятия заказа');
    rateLimit('msg:' + user.id, 60, 60_000);
    const text = str((await ctx.json()).text, 'Сообщение', { min: 1, max: 1000, required: true });
    const now = Date.now();
    const id = run('INSERT INTO messages(order_id, sender_id, text, created_at) VALUES (?,?,?,?)', o.id, user.id, text, now).lastInsertRowid;
    run(
      `INSERT INTO chat_reads(order_id, user_id, last_id) VALUES (?,?,?)
       ON CONFLICT(order_id, user_id) DO UPDATE SET last_id = MAX(last_id, excluded.last_id)`,
      o.id, user.id, id
    );
    return { id, sender_id: user.id, text, created_at: now, mine: true };
  });

  // ---------- SOS ----------
  r.post('/api/sos', async (ctx) => {
    const user = authenticate(ctx, ['parent', 'nanny']);
    const b = await ctx.json();
    rateLimit('sos:' + user.id, 10, 10 * 60_000);
    const p = coord(b.lat, b.lng, { required: false });
    let orderId = null;
    if (b.order_id) orderId = d.getOrderFor(ctx, b.order_id).id;
    const id = run(
      'INSERT INTO sos(user_id, order_id, lat, lng, created_at) VALUES (?,?,?,?,?)',
      user.id, orderId, p?.lat, p?.lng, Date.now()
    ).lastInsertRowid;
    console.warn(`🚨 SOS #${id} от ${user.phone} (${user.role}), заказ ${orderId ?? '-'}, ${p ? `${p.lat},${p.lng}` : 'без координат'}`);
    const map = p ? `\nКарта: https://maps.google.com/?q=${p.lat},${p.lng}` : '';
    alertAdmins(
      `🚨 SOS #${id}\n${user.role === 'parent' ? 'Родитель' : 'Няня'}: ${user.name || ''} ${user.phone}` +
        (orderId ? `\nЗаказ №${orderId}` : '') + map
    );
    return { ok: true, id };
  });
};
