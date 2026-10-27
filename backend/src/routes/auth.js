'use strict';
const crypto = require('node:crypto');
const config = require('../config');
const { one, run } = require('../db');
const { fail } = require('../lib/http');
const { sha256, safeEqual, issueTokens, rateLimit } = require('../lib/auth');
const { smsEnabled, sendSms } = require('../lib/notify');
const { serializeMe } = require('../domain');

const OTP_TTL_MS = 5 * 60_000;
const RESEND_MS = 60_000;

function normPhone(raw) {
  let d = String(raw || '').replace(/\D/g, '');
  if (d.length === 9) d = '998' + d;
  if (!/^998\d{9}$/.test(d)) fail(400, 'Введите номер в формате +998 XX XXX XX XX');
  return '+' + d;
}

const codeHash = (phone, code) => sha256(`${phone}:${code}:${config.jwtSecret}`);

module.exports = (r) => {
  r.post('/api/auth/otp', async (ctx) => {
    const phone = normPhone((await ctx.json()).phone);
    rateLimit('otp-ip:' + ctx.ip, 10, 10 * 60_000);
    const now = Date.now();
    const prev = one('SELECT sent_at FROM otp WHERE phone = ?', phone);
    if (prev && now - prev.sent_at < RESEND_MS) {
      fail(429, `Повторно запросить код можно через ${Math.ceil((RESEND_MS - (now - prev.sent_at)) / 1000)} сек`);
    }
    const code = String(crypto.randomInt(1000, 10000));
    run(
      `INSERT INTO otp(phone, code_hash, expires_at, attempts, sent_at) VALUES (?, ?, ?, 0, ?)
       ON CONFLICT(phone) DO UPDATE SET code_hash = excluded.code_hash, expires_at = excluded.expires_at,
                                        attempts = 0, sent_at = excluded.sent_at`,
      phone, codeHash(phone, code), now + OTP_TTL_MS, now
    );

    if (!smsEnabled()) {
      // Демо-режим без SMS-шлюза: код возвращается в ответе и показывается в приложении.
      return { ok: true, resend_in: RESEND_MS / 1000, demo_code: code };
    }
    try {
      await sendSms(phone, `Super Nyanya: kod dlya vhoda ${code}`);
    } catch (e) {
      console.error('SMS error:', e.message);
      run('DELETE FROM otp WHERE phone = ?', phone);
      fail(502, 'Не удалось отправить SMS, попробуйте позже');
    }
    return { ok: true, resend_in: RESEND_MS / 1000 };
  });

  r.post('/api/auth/verify', async (ctx) => {
    const b = await ctx.json();
    const phone = normPhone(b.phone);
    const code = String(b.code || '').trim();
    rateLimit('verify-ip:' + ctx.ip, 30, 10 * 60_000);

    const row = one('SELECT * FROM otp WHERE phone = ?', phone);
    if (!row || row.expires_at < Date.now()) fail(400, 'Код истёк, запросите новый');
    if (row.attempts >= 5) fail(429, 'Слишком много попыток, запросите новый код');
    if (!safeEqual(row.code_hash, codeHash(phone, code))) {
      run('UPDATE otp SET attempts = attempts + 1 WHERE phone = ?', phone);
      fail(400, 'Неверный код');
    }
    run('DELETE FROM otp WHERE phone = ?', phone);

    let user = one('SELECT * FROM users WHERE phone = ?', phone);
    if (!user) {
      const id = run('INSERT INTO users(phone, created_at) VALUES (?, ?)', phone, Date.now()).lastInsertRowid;
      user = one('SELECT * FROM users WHERE id = ?', id);
    }
    if (user.blocked) fail(403, 'Аккаунт заблокирован. Обратитесь в поддержку');
    return { ...issueTokens(user.id), user: serializeMe(user) };
  });

  r.post('/api/auth/refresh', async (ctx) => {
    const { refresh } = await ctx.json();
    rateLimit('refresh-ip:' + ctx.ip, 60, 10 * 60_000);
    const row = refresh ? one('SELECT * FROM refresh_tokens WHERE hash = ?', sha256(String(refresh))) : null;
    if (!row || row.expires_at < Date.now()) fail(401, 'Сессия истекла, войдите снова');
    run('DELETE FROM refresh_tokens WHERE hash = ?', row.hash);
    const user = one('SELECT * FROM users WHERE id = ?', row.user_id);
    if (!user || user.blocked) fail(401, 'Сессия истекла, войдите снова');
    return issueTokens(user.id);
  });

  r.post('/api/auth/logout', async (ctx) => {
    const { refresh } = await ctx.json();
    if (refresh) run('DELETE FROM refresh_tokens WHERE hash = ?', sha256(String(refresh)));
    return { ok: true };
  });
};
