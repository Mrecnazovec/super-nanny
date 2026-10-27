'use strict';
const crypto = require('node:crypto');
const config = require('../config');
const { one, run } = require('../db');
const { fail } = require('./http');

const sha256 = (s) => crypto.createHash('sha256').update(s).digest('hex');
const b64u = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');
const hmac = (data) => crypto.createHmac('sha256', config.jwtSecret).update(data).digest('base64url');

function safeEqual(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

function signJwt(payload, ttlSec) {
  const now = Math.floor(Date.now() / 1000);
  const head = b64u({ alg: 'HS256', typ: 'JWT' });
  const body = b64u({ ...payload, iat: now, exp: now + ttlSec });
  return `${head}.${body}.${hmac(`${head}.${body}`)}`;
}

function verifyJwt(token) {
  const parts = String(token).split('.');
  if (parts.length !== 3) return null;
  const [head, body, sig] = parts;
  if (!safeEqual(sig, hmac(`${head}.${body}`))) return null;
  try {
    const p = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
    if (!p.exp || p.exp < Date.now() / 1000) return null;
    return p;
  } catch {
    return null;
  }
}

function issueTokens(userId) {
  const refresh = crypto.randomBytes(32).toString('base64url');
  run('INSERT INTO refresh_tokens(hash, user_id, expires_at) VALUES (?,?,?)', sha256(refresh), userId, Date.now() + config.refreshTtlMs);
  return {
    access: signJwt({ sub: userId, typ: 'access' }, config.accessTtlSec),
    refresh,
    expires_in: config.accessTtlSec,
  };
}

function issueAdminToken() {
  return signJwt({ sub: 0, adm: true, typ: 'access' }, 12 * 3600);
}

/**
 * Проверяет Bearer-токен и кладёт пользователя в ctx.user.
 * roles — список допустимых ролей ('parent' | 'nanny' | 'admin'); без него пускает любого вошедшего, кроме админа.
 */
function authenticate(ctx, roles) {
  const h = ctx.req.headers.authorization || '';
  const p = h.startsWith('Bearer ') ? verifyJwt(h.slice(7)) : null;
  if (!p || p.typ !== 'access') fail(401, 'Требуется авторизация');
  if (p.adm) {
    if (!roles || !roles.includes('admin')) fail(403, 'Нет доступа');
    return (ctx.user = { id: 0, role: 'admin' });
  }
  const user = one('SELECT * FROM users WHERE id = ?', p.sub);
  if (!user) fail(401, 'Пользователь не найден');
  if (user.blocked) fail(403, 'Аккаунт заблокирован. Обратитесь в поддержку');
  if (roles && !roles.includes(user.role)) fail(403, 'Нет доступа');
  return (ctx.user = user);
}

// ---------- rate limit (в памяти, этого достаточно для одного инстанса) ----------

const buckets = new Map();
function rateLimit(key, max, windowMs) {
  const now = Date.now();
  let b = buckets.get(key);
  if (!b || b.reset < now) {
    b = { n: 0, reset: now + windowMs };
    buckets.set(key, b);
  }
  if (++b.n > max) fail(429, 'Слишком много запросов, попробуйте позже');
}
setInterval(() => {
  const now = Date.now();
  for (const [k, b] of buckets) if (b.reset < now) buckets.delete(k);
  run('DELETE FROM refresh_tokens WHERE expires_at < ?', now);
  run('DELETE FROM otp WHERE expires_at < ?', now - 3600_000);
}, 10 * 60_000).unref();

module.exports = { sha256, safeEqual, signJwt, verifyJwt, issueTokens, issueAdminToken, authenticate, rateLimit };
