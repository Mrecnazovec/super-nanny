'use strict';
// Общая предметная логика: сериализация сущностей и переходы статусов заказа.
const config = require('./config');
const { one, all, run, tx } = require('./db');
const { fail } = require('./lib/http');
const { distanceM } = require('./lib/geo');

const ACTIVE = ['accepted', 'on_the_way', 'arrived', 'in_progress'];
// Следующий статус, который может выставить няня.
const NEXT_STATUS = { accepted: 'on_the_way', on_the_way: 'arrived', arrived: 'in_progress', in_progress: 'completed' };
const ONLINE_FRESH_MS = 15 * 60_000;

const rating = (n) => (n && n.rating_count ? Math.round((n.rating_sum / n.rating_count) * 10) / 10 : null);

function photoId(userId) {
  return one("SELECT id FROM documents WHERE user_id = ? AND kind = 'photo' ORDER BY id DESC LIMIT 1", userId)?.id ?? null;
}

// ---------- пользователи ----------

function serializeMe(user) {
  const company = user.company_id ? one('SELECT id, name FROM companies WHERE id = ?', user.company_id) : null;
  const out = {
    id: user.id,
    phone: user.phone,
    name: user.name,
    role: user.role,
    company: company ? { id: company.id, name: company.name } : null,
    cards: all('SELECT id, type, mask, expiry FROM cards WHERE user_id = ? ORDER BY id', user.id),
  };
  if (user.role === 'nanny') {
    const n = one('SELECT status, reject_reason FROM nannies WHERE user_id = ?', user.id);
    out.nanny_status = n?.status ?? 'draft';
    out.reject_reason = n?.reject_reason ?? null;
  }
  return out;
}

// ---------- няни ----------

function serializeNannyCard(n, distance) {
  return {
    id: n.user_id,
    name: n.full_name,
    age: n.age,
    experience: n.experience,
    price: n.price,
    about: n.about,
    rating: rating(n),
    reviews_count: n.rating_count,
    photo_id: photoId(n.user_id),
    med_ok: Boolean(n.med_ok),
    police_ok: Boolean(n.police_ok),
    distance_m: distance ?? null,
    is_demo: Boolean(n.is_demo),
  };
}

function nannyDetail(n, distance) {
  const reviews = all(
    `SELECT r.rating, r.text, r.created_at, COALESCE(r.author_name, u.name, 'Родитель') AS author
       FROM reviews r LEFT JOIN users u ON u.id = r.parent_id
      WHERE r.nanny_id = ? ORDER BY r.created_at DESC LIMIT 30`,
    n.user_id
  );
  const done = one("SELECT COUNT(*) AS c FROM orders WHERE nanny_id = ? AND status = 'completed'", n.user_id).c;
  const certs = all("SELECT id FROM documents WHERE user_id = ? AND kind = 'cert' ORDER BY id", n.user_id).map((d) => d.id);
  return { ...serializeNannyCard(n, distance), schedule: n.schedule, orders_done: done, certificates: certs, reviews };
}

// Позиция няни для ленты: у демо-нянь она «плавает» вокруг смотрящего родителя.
function nannyPosition(n, viewerLat, viewerLng) {
  if (n.is_demo) return { lat: viewerLat + n.demo_dlat, lng: viewerLng + n.demo_dlng };
  return n.lat == null ? null : { lat: n.lat, lng: n.lng };
}

function isNannyBusy(nannyId) {
  return Boolean(
    one("SELECT 1 FROM orders WHERE nanny_id = ? AND status IN ('on_the_way','arrived','in_progress') LIMIT 1", nannyId)
  );
}

function isNannyAvailable(n) {
  if (n.status !== 'approved') return false;
  if (n.is_demo) return config.demo;
  return Boolean(n.online) && n.loc_at > Date.now() - ONLINE_FRESH_MS && !isNannyBusy(n.user_id);
}

// ---------- заказы ----------

function lastTrackPoint(orderId) {
  return one('SELECT lat, lng, ts FROM track WHERE order_id = ? ORDER BY ts DESC LIMIT 1', orderId);
}

function serializeOrder(o, viewer, { detail = false } = {}) {
  const parent = one('SELECT id, name, phone FROM users WHERE id = ?', o.parent_id) || {};
  const nanny = one(
    `SELECT u.id, u.name, u.phone, n.full_name, n.rating_sum, n.rating_count, n.is_demo, n.lat, n.lng, n.loc_at
       FROM users u LEFT JOIN nannies n ON n.user_id = u.id WHERE u.id = ?`,
    o.nanny_id
  ) || {};
  const active = ACTIVE.includes(o.status);
  const showPhones = active && !nanny.is_demo;

  const out = {
    id: o.id,
    status: o.status,
    type: o.type,
    scheduled_at: o.scheduled_at,
    children_count: o.children_count,
    children_ages: o.children_ages,
    notes: o.notes,
    address: o.address,
    lat: o.lat,
    lng: o.lng,
    corporate: Boolean(o.corporate),
    price: o.price,
    hold_amount: o.hold_amount,
    expected_earning: Math.round(o.hold_amount * (1 - config.commission)),
    created_at: o.created_at,
    accepted_at: o.accepted_at,
    started_at: o.started_at,
    finished_at: o.finished_at,
    minutes: o.minutes,
    total: o.total,
    commission: o.commission,
    nanny_earning: o.nanny_earning,
    cancel_reason: o.cancel_reason,
    cancelled_by: o.cancelled_by,
    expires_at: o.status === 'pending' ? o.created_at + config.acceptTimeoutMs : null,
    server_time: Date.now(),
    parent: { id: parent.id, name: parent.name, phone: showPhones ? parent.phone : null },
    nanny: {
      id: nanny.id,
      name: nanny.full_name || nanny.name,
      phone: showPhones ? nanny.phone : null,
      photo_id: photoId(o.nanny_id),
      rating: rating(nanny),
      is_demo: Boolean(nanny.is_demo),
    },
  };

  if (viewer) {
    const read = one('SELECT last_id FROM chat_reads WHERE order_id = ? AND user_id = ?', o.id, viewer.id)?.last_id ?? 0;
    out.unread = one('SELECT COUNT(*) AS c FROM messages WHERE order_id = ? AND id > ? AND sender_id != ?', o.id, read, viewer.id).c;
  }

  // Где сейчас няня — только пока заказ активен.
  let loc = null;
  if (active) {
    const p = lastTrackPoint(o.id);
    if (p) loc = p;
    else if (!nanny.is_demo && nanny.lat != null) loc = { lat: nanny.lat, lng: nanny.lng, ts: nanny.loc_at };
  }
  out.nanny_location = loc;
  out.distance_m = loc ? distanceM(loc.lat, loc.lng, o.lat, o.lng) : null;

  if (detail) {
    out.track = all('SELECT lat, lng FROM track WHERE order_id = ? ORDER BY ts DESC LIMIT 300', o.id)
      .reverse()
      .map((p) => [p.lat, p.lng]);
    out.review = one('SELECT rating, text, created_at FROM reviews WHERE order_id = ?', o.id) || null;
  }
  return out;
}

function getOrderFor(ctx, id) {
  const o = one('SELECT * FROM orders WHERE id = ?', Number(id));
  if (!o) fail(404, 'Заказ не найден');
  const u = ctx.user;
  if (u.role !== 'admin' && o.parent_id !== u.id && o.nanny_id !== u.id) fail(404, 'Заказ не найден');
  return o;
}

function expirePending() {
  const now = Date.now();
  run(
    "UPDATE orders SET status = 'expired', updated_at = ? WHERE status = 'pending' AND created_at < ?",
    now,
    now - config.acceptTimeoutMs
  );
}

function acceptOrder(orderId) {
  return tx(() => {
    const o = one('SELECT * FROM orders WHERE id = ?', orderId);
    if (!o || o.status !== 'pending') fail(409, 'Заказ уже неактуален');
    const now = Date.now();
    if (now - o.created_at > config.acceptTimeoutMs) fail(409, 'Время на принятие заказа истекло');
    run("UPDATE orders SET status = 'accepted', accepted_at = ?, updated_at = ? WHERE id = ?", now, now, o.id);
    // Холдирование суммы за holdHours часов (эмуляция эквайринга Payme/Click).
    run(
      `INSERT INTO payments(order_id, method, card_id, company_id, amount, status, created_at, updated_at)
       VALUES (?,?,?,?,?, 'held', ?, ?)`,
      o.id, o.corporate ? 'company' : 'card', o.card_id, o.company_id, o.hold_amount, now, now
    );
    return one('SELECT * FROM orders WHERE id = ?', o.id);
  });
}

function setStatus(orderId, status) {
  const now = Date.now();
  const extra = status === 'in_progress' ? ', started_at = ' + now : '';
  run(`UPDATE orders SET status = ?, updated_at = ?${extra} WHERE id = ?`, status, now, orderId);
}

function completeOrder(orderId) {
  return tx(() => {
    const o = one('SELECT * FROM orders WHERE id = ?', orderId);
    if (!o || o.status !== 'in_progress') fail(409, 'Заказ не в работе');
    const now = Date.now();
    // Минимальный заказ — 1 час, дальше поминутно; сумма округляется до 100 сум.
    const minutes = Math.max(60, Math.ceil((now - o.started_at) / 60_000));
    const total = Math.round((o.price * minutes) / 60 / 100) * 100;
    const commission = Math.round(total * config.commission);
    const earning = total - commission;
    run(
      `UPDATE orders SET status = 'completed', finished_at = ?, updated_at = ?, minutes = ?, total = ?,
              commission = ?, nanny_earning = ? WHERE id = ?`,
      now, now, minutes, total, commission, earning, o.id
    );
    run("UPDATE payments SET status = 'charged', amount = ?, updated_at = ? WHERE order_id = ? AND status = 'held'", total, now, o.id);
    if (o.corporate && o.company_id) run('UPDATE companies SET spent = spent + ? WHERE id = ?', total, o.company_id);
    run('UPDATE nannies SET balance = balance + ? WHERE user_id = ?', earning, o.nanny_id);
    run("INSERT INTO wallet_tx(nanny_id, amount, kind, order_id, created_at) VALUES (?, ?, 'earning', ?, ?)", o.nanny_id, earning, o.id, now);
    return one('SELECT * FROM orders WHERE id = ?', o.id);
  });
}

function cancelOrder(o, by, reason) {
  if (!['pending', 'accepted', 'on_the_way', 'arrived'].includes(o.status)) fail(409, 'Этот заказ уже нельзя отменить');
  const now = Date.now();
  tx(() => {
    run(
      "UPDATE orders SET status = 'cancelled', cancelled_by = ?, cancel_reason = ?, updated_at = ? WHERE id = ?",
      by, reason, now, o.id
    );
    run("UPDATE payments SET status = 'released', updated_at = ? WHERE order_id = ? AND status = 'held'", now, o.id);
  });
}

module.exports = {
  ACTIVE,
  NEXT_STATUS,
  rating,
  photoId,
  serializeMe,
  serializeNannyCard,
  nannyDetail,
  nannyPosition,
  isNannyAvailable,
  isNannyBusy,
  serializeOrder,
  getOrderFor,
  expirePending,
  acceptOrder,
  setStatus,
  completeOrder,
  cancelOrder,
};
