'use strict';
const config = require('../config');
const { one, all } = require('../db');
const { fail, coord } = require('../lib/http');
const { authenticate } = require('../lib/auth');
const { distanceM, bbox } = require('../lib/geo');
const { serializeNannyCard, nannyDetail, nannyPosition, isNannyAvailable } = require('../domain');

module.exports = (r) => {
  // Лента мэтчинга: одобренные няни «на линии» в радиусе 1–15 км, ближайшие первыми.
  r.get('/api/nannies', (ctx) => {
    authenticate(ctx, ['parent']);
    const { lat, lng } = coord(ctx.query.lat, ctx.query.lng);
    const radiusKm = Math.min(15, Math.max(1, Number(ctx.query.radius_km) || 5));
    const radiusM = radiusKm * 1000;
    const box = bbox(lat, lng, radiusM);

    const rows = all(
      `SELECT * FROM nannies
        WHERE status = 'approved'
          AND ((is_demo = 0 AND online = 1 AND lat BETWEEN ? AND ? AND lng BETWEEN ? AND ?) OR is_demo = 1)
          AND user_id NOT IN (SELECT id FROM users WHERE blocked = 1)`,
      box.minLat, box.maxLat, box.minLng, box.maxLng
    );

    const out = [];
    for (const n of rows) {
      if (!isNannyAvailable(n)) continue;
      const pos = nannyPosition(n, lat, lng);
      if (!pos) continue;
      const d = distanceM(lat, lng, pos.lat, pos.lng);
      if (d <= radiusM) out.push(serializeNannyCard(n, d));
    }
    // Реальные няни выше демо-анкет, внутри — по расстоянию.
    out.sort((a, b) => a.is_demo - b.is_demo || a.distance_m - b.distance_m);
    return { radius_km: radiusKm, demo: config.demo, items: out.slice(0, 50) };
  });

  r.get('/api/nannies/:id', (ctx) => {
    authenticate(ctx, ['parent', 'admin']);
    const n = one("SELECT * FROM nannies WHERE user_id = ? AND status = 'approved'", Number(ctx.params.id));
    if (!n) fail(404, 'Няня не найдена');
    let distance = null;
    if (ctx.query.lat && ctx.query.lng) {
      const p = coord(ctx.query.lat, ctx.query.lng);
      const pos = nannyPosition(n, p.lat, p.lng);
      if (pos) distance = distanceM(p.lat, p.lng, pos.lat, pos.lng);
    }
    return { ...nannyDetail(n, distance), available: isNannyAvailable(n) };
  });
};
