'use strict';
const crypto = require('node:crypto');
const { one, all, run } = require('../db');
const { fail, str } = require('../lib/http');
const { authenticate } = require('../lib/auth');
const { serializeMe } = require('../domain');

function cardType(number) {
  if (/^(8600|5614)/.test(number)) return 'uzcard';
  if (/^9860/.test(number)) return 'humo';
  return null;
}

module.exports = (r) => {
  r.get('/api/me', (ctx) => serializeMe(authenticate(ctx)));

  r.patch('/api/me', async (ctx) => {
    const user = authenticate(ctx);
    const b = await ctx.json();
    const name = b.name !== undefined ? str(b.name, 'Имя', { min: 2, max: 60, required: true }) : user.name;
    let role = user.role;
    if (b.role !== undefined && b.role !== user.role) {
      if (user.role) fail(400, 'Роль уже выбрана');
      if (!['parent', 'nanny'].includes(b.role)) fail(400, 'Неизвестная роль');
      role = b.role;
    }
    run('UPDATE users SET name = ?, role = ? WHERE id = ?', name, role, user.id);
    if (role === 'nanny') {
      run('INSERT INTO nannies(user_id, full_name) VALUES (?, ?) ON CONFLICT(user_id) DO NOTHING', user.id, name);
    }
    return serializeMe(one('SELECT * FROM users WHERE id = ?', user.id));
  });

  // ---------- B2B: привязка к компании по корпоративному коду ----------

  r.post('/api/me/company', async (ctx) => {
    const user = authenticate(ctx, ['parent']);
    const code = str((await ctx.json()).code, 'Код компании', { min: 3, max: 20, required: true }).toUpperCase();
    const company = one('SELECT * FROM companies WHERE code = ?', code);
    if (!company) fail(404, 'Компания с таким кодом не найдена');
    run('UPDATE users SET company_id = ? WHERE id = ?', company.id, user.id);
    return serializeMe(one('SELECT * FROM users WHERE id = ?', user.id));
  });

  r.delete('/api/me/company', (ctx) => {
    const user = authenticate(ctx, ['parent']);
    run('UPDATE users SET company_id = NULL WHERE id = ?', user.id);
    return serializeMe(one('SELECT * FROM users WHERE id = ?', user.id));
  });

  // ---------- Карты Uzcard / Humo ----------
  // Номер карты целиком не хранится: только маска и токен. Здесь токен — заглушка;
  // при подключении Payme/Click сюда встаёт вызов cards.create + cards.verify (SMS).

  r.get('/api/cards', (ctx) => {
    const user = authenticate(ctx);
    return all('SELECT id, type, mask, expiry FROM cards WHERE user_id = ? ORDER BY id', user.id);
  });

  r.post('/api/cards', async (ctx) => {
    const user = authenticate(ctx);
    const b = await ctx.json();
    const number = String(b.number || '').replace(/\D/g, '');
    const expiry = String(b.expiry || '').trim();
    if (number.length !== 16) fail(400, 'Номер карты должен содержать 16 цифр');
    const type = cardType(number);
    if (!type) fail(400, 'Поддерживаются только карты Uzcard и Humo');
    const m = /^(\d{2})\/(\d{2})$/.exec(expiry);
    if (!m || +m[1] < 1 || +m[1] > 12) fail(400, 'Срок действия в формате ММ/ГГ');
    const now = new Date();
    const exp = new Date(2000 + Number(m[2]), Number(m[1]), 1);
    if (exp <= now) fail(400, 'Срок действия карты истёк');
    if (one('SELECT COUNT(*) AS c FROM cards WHERE user_id = ?', user.id).c >= 5) fail(400, 'Можно привязать не больше 5 карт');
    const mask = `${number.slice(0, 4)} •••• •••• ${number.slice(-4)}`;
    if (one('SELECT 1 FROM cards WHERE user_id = ? AND mask = ? AND expiry = ?', user.id, mask, expiry)) fail(409, 'Эта карта уже привязана');
    const token = 'demo_' + crypto.randomBytes(12).toString('hex');
    const id = run(
      'INSERT INTO cards(user_id, type, mask, expiry, token, created_at) VALUES (?,?,?,?,?,?)',
      user.id, type, mask, expiry, token, Date.now()
    ).lastInsertRowid;
    return { id, type, mask, expiry };
  });

  r.delete('/api/cards/:id', (ctx) => {
    const user = authenticate(ctx);
    run('DELETE FROM cards WHERE id = ? AND user_id = ?', Number(ctx.params.id), user.id);
    return { ok: true };
  });
};
