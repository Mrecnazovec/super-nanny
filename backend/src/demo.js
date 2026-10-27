'use strict';
// Демо-режим (DEMO != '0'): виртуальные няни, которые видны вокруг любого родителя
// и сами проходят весь цикл заказа. Позволяет показать приложение с одного телефона.
// Отключается переменной окружения DEMO=0.
const config = require('./config');
const { one, all, run } = require('./db');
const { distanceM } = require('./lib/geo');
const d = require('./domain');

const NANNIES = [
  ['Малика Юсупова', 28, 6, 60000, 'Педагог начальных классов. Развивающие игры, помощь с уроками, прогулки. Говорю на узбекском, русском и английском.', 0.006, 0.004, 48, 10],
  ['Нигора Ахмедова', 34, 10, 75000, 'Опыт с малышами от 6 месяцев. Режим дня, прикорм, сон. Есть сертификат первой помощи.', -0.011, 0.009, 99, 21],
  ['Елена Ким', 41, 15, 90000, 'Профессиональная няня-воспитатель. Методика Монтессори, подготовка к школе, творчество.', 0.019, -0.014, 99, 20],
  ['Дилноза Каримова', 25, 3, 45000, 'Студентка педагогического университета. Активные игры, чтение, английский для малышей.', -0.004, -0.008, 43, 9],
  ['Гульнара Рашидова', 38, 12, 80000, 'Медсестра по образованию. Могу присмотреть за ребёнком после болезни, слежу за приёмом лекарств.', 0.027, 0.021, 96, 20],
  ['Анна Петрова', 30, 7, 65000, 'Люблю детей и спокойные игры. Готовлю детское меню, вожу на кружки и секции.', -0.022, 0.031, 66, 14],
  ['Шахноза Турсунова', 23, 2, 40000, 'Аниматор детских праздников. Весёлые игры, рисование, музыка — скучно не будет!', 0.041, -0.006, 37, 8],
  ['Зарина Алиева', 45, 20, 100000, 'Няня с большим стажем, вырастила троих детей. Рекомендации от семей, работаю с двойняшками.', -0.035, -0.027, 145, 30],
];

const REVIEWS = [
  ['Азиза', 5, 'Очень внимательная, ребёнок в восторге. Обязательно позовём ещё!'],
  ['Тимур', 5, 'Пришла вовремя, всё чётко, отчиталась фотографиями в чате.'],
  ['Ольга', 4, 'Хорошая няня, дочке понравилось рисовать вместе.'],
  ['Камола', 5, 'Спасибо! Уложила малыша спать, хотя обычно это квест.'],
];

const REPLIES = [
  'Здравствуйте! Заказ получила, всё в силе 🙂',
  'Хорошо, учту. Есть ещё пожелания?',
  'Уже в пути, буду совсем скоро.',
  'Поняла вас! Не переживайте, всё будет хорошо.',
];

function seed() {
  if (one('SELECT 1 FROM nannies WHERE is_demo = 1 LIMIT 1')) return;
  const now = Date.now();
  NANNIES.forEach(([name, age, exp, price, about, dlat, dlng, rsum, rcount], i) => {
    const id = run('INSERT INTO users(phone, name, role, created_at) VALUES (?, ?, ?, ?)', `demo:${i + 1}`, name, 'nanny', now).lastInsertRowid;
    run(
      `INSERT INTO nannies(user_id, full_name, age, experience, about, price, schedule, status, med_ok, police_ok, online,
                           rating_sum, rating_count, is_demo, demo_dlat, demo_dlng, verified_at)
       VALUES (?,?,?,?,?,?,?, 'approved', 1, 1, 1, ?, ?, 1, ?, ?, ?)`,
      id, name, age, exp, about, price, 'Пн–Пт 08:00–20:00, Сб по договорённости', rsum, rcount, dlat, dlng, now
    );
    REVIEWS.slice(0, 2 + (i % 3)).forEach(([author, rating, text], j) => {
      run(
        'INSERT INTO reviews(order_id, parent_id, nanny_id, rating, text, author_name, created_at) VALUES (?,?,?,?,?,?,?)',
        -(id * 10 + j), 0, id, rating, text, author, now - (j + 1) * 86400_000 * 3
      );
    });
  });
  console.log(`Демо: создано ${NANNIES.length} демо-нянь`);
}

function moveToward(from, to, stepM) {
  const dist = distanceM(from.lat, from.lng, to.lat, to.lng);
  if (dist <= stepM) return { ...to, arrived: true };
  const k = stepM / dist;
  return { lat: from.lat + (to.lat - from.lat) * k, lng: from.lng + (to.lng - from.lng) * k, arrived: false };
}

function tick() {
  const now = Date.now();
  const rows = all(
    `SELECT o.*, n.demo_dlat, n.demo_dlng FROM orders o JOIN nannies n ON n.user_id = o.nanny_id
      WHERE n.is_demo = 1 AND o.status IN ('pending','accepted','on_the_way','arrived','in_progress')`
  );
  for (const o of rows) {
    try {
      const since = now - o.updated_at;
      const later = o.type === 'scheduled' && o.scheduled_at - now > 3600_000;
      if (o.status === 'pending' && since > 4000) d.acceptOrder(o.id);
      else if (o.status === 'accepted' && since > 6000 && !later) {
        // Демо-няня стартует в 0.6–3 км от адреса.
        const k = 0.45;
        run('INSERT INTO track(order_id, lat, lng, ts) VALUES (?,?,?,?)', o.id, o.lat + o.demo_dlat * k, o.lng + o.demo_dlng * k, now);
        d.setStatus(o.id, 'on_the_way');
      } else if (o.status === 'on_the_way') {
        const last = one('SELECT lat, lng FROM track WHERE order_id = ? ORDER BY ts DESC LIMIT 1', o.id);
        const from = last || { lat: o.lat + 0.01, lng: o.lng + 0.01 };
        const total = distanceM(from.lat, from.lng, o.lat, o.lng);
        const p = moveToward(from, { lat: o.lat, lng: o.lng }, Math.max(60, total * 0.12));
        run('INSERT INTO track(order_id, lat, lng, ts) VALUES (?,?,?,?)', o.id, p.lat, p.lng, now);
        if (p.arrived) d.setStatus(o.id, 'arrived');
      } else if (o.status === 'arrived' && since > 10_000) d.setStatus(o.id, 'in_progress');
      else if (o.status === 'in_progress' && now - o.started_at > 3 * 60_000) d.completeOrder(o.id);
    } catch (e) {
      if (!e.status) console.error('demo tick', o.id, e);
    }
  }

  // Демо-няня отвечает в чате.
  const chats = all(
    `SELECT o.id, o.nanny_id, m.sender_id, m.created_at FROM orders o
       JOIN nannies n ON n.user_id = o.nanny_id
       JOIN messages m ON m.id = (SELECT MAX(id) FROM messages WHERE order_id = o.id)
      WHERE n.is_demo = 1 AND m.sender_id = o.parent_id AND m.created_at < ? AND m.created_at > ?`,
    now - 2500, now - 120_000
  );
  for (const c of chats) {
    const n = one('SELECT COUNT(*) AS c FROM messages WHERE order_id = ? AND sender_id = ?', c.id, c.nanny_id).c;
    run('INSERT INTO messages(order_id, sender_id, text, created_at) VALUES (?,?,?,?)', c.id, c.nanny_id, REPLIES[n % REPLIES.length], now);
  }
}

function start() {
  if (!config.demo) return;
  seed();
  setInterval(tick, 3000).unref();
}

module.exports = { start };
