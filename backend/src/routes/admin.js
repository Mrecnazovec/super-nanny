'use strict';
const crypto = require('node:crypto');
const config = require('../config');
const { one, all, run, tx } = require('../db');
const { fail, str } = require('../lib/http');
const { authenticate, issueAdminToken, rateLimit } = require('../lib/auth');
const { serializeOrder, rating } = require('../domain');

const admin = (ctx) => authenticate(ctx, ['admin']);
const count = (sql, ...p) => one(sql, ...p).c;

module.exports = (r) => {
  r.post('/api/admin/login', async (ctx) => {
    rateLimit('admin-login:' + ctx.ip, 10, 10 * 60_000);
    const pass = String((await ctx.json()).password || '');
    const a = crypto.createHash('sha256').update(pass).digest();
    const b = crypto.createHash('sha256').update(config.adminPassword).digest();
    if (!crypto.timingSafeEqual(a, b)) fail(401, 'Неверный пароль');
    return { access: issueAdminToken() };
  });

  r.get('/api/admin/stats', (ctx) => {
    admin(ctx);
    const dayStart = new Date();
    dayStart.setHours(0, 0, 0, 0);
    return {
      users: {
        parents: count("SELECT COUNT(*) AS c FROM users WHERE role = 'parent'"),
        nannies: count("SELECT COUNT(*) AS c FROM nannies WHERE is_demo = 0"),
      },
      nannies: {
        pending: count("SELECT COUNT(*) AS c FROM nannies WHERE status = 'pending'"),
        approved: count("SELECT COUNT(*) AS c FROM nannies WHERE status = 'approved' AND is_demo = 0"),
        online: count('SELECT COUNT(*) AS c FROM nannies WHERE online = 1 AND is_demo = 0 AND loc_at > ?', Date.now() - 15 * 60_000),
      },
      orders: {
        total: count('SELECT COUNT(*) AS c FROM orders'),
        active: count("SELECT COUNT(*) AS c FROM orders WHERE status IN ('accepted','on_the_way','arrived','in_progress')"),
        completed: count("SELECT COUNT(*) AS c FROM orders WHERE status = 'completed'"),
        today: count('SELECT COUNT(*) AS c FROM orders WHERE created_at >= ?', dayStart.getTime()),
      },
      money: {
        gmv: one("SELECT COALESCE(SUM(total), 0) AS s FROM orders WHERE status = 'completed'").s,
        revenue: one("SELECT COALESCE(SUM(commission), 0) AS s FROM orders WHERE status = 'completed'").s,
        b2b: one("SELECT COALESCE(SUM(total), 0) AS s FROM orders WHERE status = 'completed' AND corporate = 1").s,
        payouts_pending: one("SELECT COALESCE(SUM(amount), 0) AS s FROM withdrawals WHERE status = 'pending'").s,
      },
      sos_open: count('SELECT COUNT(*) AS c FROM sos WHERE resolved = 0'),
      demo: config.demo,
    };
  });

  // ---------- верификация нянь ----------
  r.get('/api/admin/nannies', (ctx) => {
    admin(ctx);
    const status = ctx.query.status;
    const rows = all(
      `SELECT n.*, u.phone, u.blocked, u.created_at FROM nannies n JOIN users u ON u.id = n.user_id
        WHERE n.is_demo = 0 ${status ? 'AND n.status = ?' : ''}
        ORDER BY COALESCE(n.submitted_at, u.created_at) DESC LIMIT 300`,
      ...(status ? [status] : [])
    );
    return rows.map((n) => ({
      id: n.user_id,
      phone: n.phone,
      full_name: n.full_name,
      age: n.age,
      experience: n.experience,
      price: n.price,
      status: n.status,
      reject_reason: n.reject_reason,
      online: Boolean(n.online),
      rating: rating(n),
      blocked: Boolean(n.blocked),
      submitted_at: n.submitted_at,
      created_at: n.created_at,
    }));
  });

  r.get('/api/admin/nannies/:id', (ctx) => {
    admin(ctx);
    const n = one('SELECT n.*, u.phone, u.blocked FROM nannies n JOIN users u ON u.id = n.user_id WHERE n.user_id = ?', Number(ctx.params.id));
    if (!n) fail(404, 'Няня не найдена');
    return {
      id: n.user_id,
      phone: n.phone,
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
      balance: n.balance,
      rating: rating(n),
      reviews_count: n.rating_count,
      submitted_at: n.submitted_at,
      verified_at: n.verified_at,
      docs: all('SELECT id, kind, mime, size, created_at FROM documents WHERE user_id = ? ORDER BY kind, id', n.user_id),
      orders_done: count("SELECT COUNT(*) AS c FROM orders WHERE nanny_id = ? AND status = 'completed'", n.user_id),
    };
  });

  r.post('/api/admin/nannies/:id/approve', async (ctx) => {
    admin(ctx);
    const b = await ctx.json();
    const id = Number(ctx.params.id);
    const n = one('SELECT status FROM nannies WHERE user_id = ? AND is_demo = 0', id);
    if (!n) fail(404, 'Няня не найдена');
    run(
      "UPDATE nannies SET status = 'approved', reject_reason = NULL, med_ok = ?, police_ok = ?, verified_at = ? WHERE user_id = ?",
      b.med_ok !== false, b.police_ok !== false, Date.now(), id
    );
    return { ok: true };
  });

  r.post('/api/admin/nannies/:id/reject', async (ctx) => {
    admin(ctx);
    const reason = str((await ctx.json()).reason, 'Причина', { min: 3, max: 300, required: true });
    const id = Number(ctx.params.id);
    if (!one('SELECT 1 FROM nannies WHERE user_id = ? AND is_demo = 0', id)) fail(404, 'Няня не найдена');
    run("UPDATE nannies SET status = 'rejected', reject_reason = ?, online = 0, med_ok = 0, police_ok = 0 WHERE user_id = ?", reason, id);
    return { ok: true };
  });

  // ---------- SOS ----------
  r.get('/api/admin/sos', (ctx) => {
    admin(ctx);
    const rows = all(
      `SELECT s.*, u.name, u.phone, u.role FROM sos s LEFT JOIN users u ON u.id = s.user_id
        ORDER BY s.resolved, s.created_at DESC LIMIT 200`
    );
    return rows.map((s) => {
      const o = s.order_id ? one('SELECT * FROM orders WHERE id = ?', s.order_id) : null;
      return {
        id: s.id,
        lat: s.lat,
        lng: s.lng,
        resolved: Boolean(s.resolved),
        created_at: s.created_at,
        resolved_at: s.resolved_at,
        user: { id: s.user_id, name: s.name, phone: s.phone, role: s.role },
        order: o
          ? {
              id: o.id,
              status: o.status,
              address: o.address,
              parent: one('SELECT name, phone FROM users WHERE id = ?', o.parent_id),
              nanny: one('SELECT name, phone FROM users WHERE id = ?', o.nanny_id),
            }
          : null,
      };
    });
  });

  r.post('/api/admin/sos/:id/resolve', (ctx) => {
    admin(ctx);
    run('UPDATE sos SET resolved = 1, resolved_at = ? WHERE id = ?', Date.now(), Number(ctx.params.id));
    return { ok: true };
  });

  // ---------- пользователи ----------
  r.get('/api/admin/users', (ctx) => {
    admin(ctx);
    const q = String(ctx.query.q || '').trim();
    const like = `%${q}%`;
    return all(
      `SELECT u.id, u.phone, u.name, u.role, u.blocked, u.created_at, c.name AS company
         FROM users u LEFT JOIN companies c ON c.id = u.company_id
        WHERE u.phone NOT LIKE 'demo:%' ${q ? 'AND (u.phone LIKE ? OR u.name LIKE ?)' : ''}
        ORDER BY u.id DESC LIMIT 300`,
      ...(q ? [like, like] : [])
    ).map((u) => ({ ...u, blocked: Boolean(u.blocked) }));
  });

  r.post('/api/admin/users/:id/block', async (ctx) => {
    admin(ctx);
    const blocked = Boolean((await ctx.json()).blocked);
    const id = Number(ctx.params.id);
    tx(() => {
      run('UPDATE users SET blocked = ? WHERE id = ?', blocked, id);
      if (blocked) {
        run('DELETE FROM refresh_tokens WHERE user_id = ?', id);
        run('UPDATE nannies SET online = 0 WHERE user_id = ?', id);
      }
    });
    return { ok: true };
  });

  // ---------- заказы и биллинг ----------
  r.get('/api/admin/orders', (ctx) => {
    admin(ctx);
    const status = ctx.query.status;
    const rows = all(
      `SELECT * FROM orders ${status ? 'WHERE status = ?' : ''} ORDER BY created_at DESC LIMIT 300`,
      ...(status ? [status] : [])
    );
    return rows.map((o) => {
      const s = serializeOrder(o, null);
      return {
        ...s,
        company: o.company_id ? one('SELECT name FROM companies WHERE id = ?', o.company_id)?.name : null,
        payment: one('SELECT method, amount, status FROM payments WHERE order_id = ? ORDER BY id DESC LIMIT 1', o.id) || null,
      };
    });
  });

  r.get('/api/admin/companies', (ctx) => {
    admin(ctx);
    return all(
      `SELECT c.*, (SELECT COUNT(*) FROM users u WHERE u.company_id = c.id) AS employees,
              (SELECT COUNT(*) FROM orders o WHERE o.company_id = c.id AND o.status = 'completed') AS orders
         FROM companies c ORDER BY c.id DESC`
    );
  });

  r.post('/api/admin/companies', async (ctx) => {
    admin(ctx);
    const b = await ctx.json();
    const name = str(b.name, 'Название', { min: 2, max: 100, required: true });
    const code = str(b.code, 'Код', { min: 3, max: 20, required: true }).toUpperCase();
    if (!/^[A-Z0-9_-]+$/.test(code)) fail(400, 'Код: латинские буквы, цифры, _ и -');
    if (one('SELECT 1 FROM companies WHERE code = ?', code)) fail(409, 'Такой код уже существует');
    const id = run('INSERT INTO companies(name, code, created_at) VALUES (?,?,?)', name, code, Date.now()).lastInsertRowid;
    return one('SELECT * FROM companies WHERE id = ?', id);
  });

  r.get('/api/admin/withdrawals', (ctx) => {
    admin(ctx);
    return all(
      `SELECT w.*, n.full_name, u.phone FROM withdrawals w
         JOIN nannies n ON n.user_id = w.nanny_id JOIN users u ON u.id = w.nanny_id
        ORDER BY (w.status = 'pending') DESC, w.id DESC LIMIT 300`
    );
  });

  r.post('/api/admin/withdrawals/:id/:action', (ctx) => {
    admin(ctx);
    const action = ctx.params.action;
    if (!['paid', 'reject'].includes(action)) fail(404, 'Не найдено');
    const w = one("SELECT * FROM withdrawals WHERE id = ? AND status = 'pending'", Number(ctx.params.id));
    if (!w) fail(404, 'Заявка не найдена или уже обработана');
    const now = Date.now();
    tx(() => {
      run('UPDATE withdrawals SET status = ?, processed_at = ? WHERE id = ?', action === 'paid' ? 'paid' : 'rejected', now, w.id);
      if (action === 'reject') {
        run('UPDATE nannies SET balance = balance + ? WHERE user_id = ?', w.amount, w.nanny_id);
        run("INSERT INTO wallet_tx(nanny_id, amount, kind, created_at) VALUES (?, ?, 'refund', ?)", w.nanny_id, w.amount, now);
      }
    });
    return { ok: true };
  });
};
