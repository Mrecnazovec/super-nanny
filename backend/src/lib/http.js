'use strict';

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function fail(status, message) {
  throw new HttpError(status, message);
}

function sendJson(res, status, data) {
  const body = JSON.stringify(data);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

function readBody(req, limit) {
  const declared = Number(req.headers['content-length'] || 0);
  if (declared > limit) {
    req.resume();
    return Promise.reject(new HttpError(413, 'Слишком большой запрос'));
  }
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    let tooBig = false;
    req.on('data', (c) => {
      size += c.length;
      if (size > limit) tooBig = true;
      else chunks.push(c);
    });
    req.on('end', () => (tooBig ? reject(new HttpError(413, 'Слишком большой запрос')) : resolve(Buffer.concat(chunks))));
    req.on('error', reject);
  });
}

class Context {
  constructor(req, res, url, params) {
    this.req = req;
    this.res = res;
    this.url = url;
    this.params = params;
    this.query = Object.fromEntries(url.searchParams);
    this.ip = String(req.headers['x-forwarded-for'] || req.socket.remoteAddress || '').split(',')[0].trim();
    this.user = null;
  }

  async json() {
    if (this._json) return this._json;
    const buf = await readBody(this.req, 64 * 1024);
    if (!buf.length) return (this._json = {});
    let data;
    try {
      data = JSON.parse(buf.toString('utf8'));
    } catch {
      fail(400, 'Некорректный JSON');
    }
    if (!data || typeof data !== 'object' || Array.isArray(data)) fail(400, 'Ожидается JSON-объект');
    return (this._json = data);
  }

  raw(limit) {
    return readBody(this.req, limit);
  }
}

class Router {
  constructor() {
    this.routes = [];
  }

  add(method, pattern, handler) {
    const keys = [];
    const re = new RegExp(
      '^' + pattern.replace(/:(\w+)/g, (_, k) => { keys.push(k); return '([^/]+)'; }) + '/?$'
    );
    this.routes.push({ method, re, keys, handler });
  }

  get(p, h) { this.add('GET', p, h); }
  post(p, h) { this.add('POST', p, h); }
  put(p, h) { this.add('PUT', p, h); }
  patch(p, h) { this.add('PATCH', p, h); }
  delete(p, h) { this.add('DELETE', p, h); }

  async handle(req, res, url) {
    for (const r of this.routes) {
      if (r.method !== req.method) continue;
      const m = r.re.exec(url.pathname);
      if (!m) continue;
      const params = {};
      r.keys.forEach((k, i) => { params[k] = decodeURIComponent(m[i + 1]); });
      const ctx = new Context(req, res, url, params);
      try {
        const result = await r.handler(ctx);
        if (!res.headersSent) sendJson(res, 200, result === undefined ? { ok: true } : result);
      } catch (e) {
        if (res.headersSent) return true;
        if (e instanceof HttpError) sendJson(res, e.status, { error: e.message });
        else {
          console.error(`[${req.method} ${url.pathname}]`, e);
          sendJson(res, 500, { error: 'Внутренняя ошибка сервера' });
        }
      }
      return true;
    }
    return false;
  }
}

// ---------- валидация ----------

function str(v, name, { min = 0, max = 200, required = false } = {}) {
  if (v === undefined || v === null || v === '') {
    if (required) fail(400, `Поле «${name}» обязательно`);
    return null;
  }
  if (typeof v !== 'string' && typeof v !== 'number') fail(400, `Поле «${name}» должно быть строкой`);
  const s = String(v).trim();
  if (required && !s) fail(400, `Поле «${name}» обязательно`);
  if (s.length < min) fail(400, `Поле «${name}»: минимум ${min} символов`);
  if (s.length > max) fail(400, `Поле «${name}»: максимум ${max} символов`);
  return s || null;
}

function int(v, name, min, max, { required = true } = {}) {
  if (v === undefined || v === null || v === '') {
    if (required) fail(400, `Поле «${name}» обязательно`);
    return null;
  }
  const n = Number(v);
  if (!Number.isInteger(n) || n < min || n > max) fail(400, `Поле «${name}» должно быть целым числом от ${min} до ${max}`);
  return n;
}

function coord(lat, lng, { required = true } = {}) {
  if ((lat === undefined || lat === null) && (lng === undefined || lng === null) && !required) return null;
  const a = Number(lat);
  const b = Number(lng);
  if (!Number.isFinite(a) || !Number.isFinite(b) || Math.abs(a) > 90 || Math.abs(b) > 180) {
    fail(400, 'Некорректные координаты');
  }
  return { lat: a, lng: b };
}

module.exports = { HttpError, fail, sendJson, Router, str, int, coord };
