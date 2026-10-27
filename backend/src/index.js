'use strict';
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const config = require('./config');
const { db } = require('./db');
const { Router, sendJson } = require('./lib/http');
const { expirePending } = require('./domain');
const { smsEnabled } = require('./lib/notify');

const router = new Router();
for (const m of ['auth', 'me', 'files', 'nanny', 'feed', 'orders', 'admin']) require(`./routes/${m}`)(router);

const PUBLIC = path.join(__dirname, '..', 'public');
const pages = {
  '/': 'index.html',
  '/admin': 'admin.html',
  '/admin/': 'admin.html',
};

const server = http.createServer(async (req, res) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  if (req.method === 'OPTIONS') {
    res.writeHead(204).end();
    return;
  }

  const url = new URL(req.url, 'http://localhost');
  if (url.pathname === '/health') return sendJson(res, 200, { ok: true, uptime: Math.round(process.uptime()) });

  if (req.method === 'GET' && pages[url.pathname]) {
    const html = fs.readFileSync(path.join(PUBLIC, pages[url.pathname]));
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-cache', 'X-Frame-Options': 'DENY' });
    return res.end(html);
  }

  if (await router.handle(req, res, url)) return;
  sendJson(res, 404, { error: 'Не найдено' });
});

server.requestTimeout = 60_000;
server.headersTimeout = 15_000;
server.keepAliveTimeout = 30_000;

setInterval(expirePending, 5000).unref();
require('./demo').start();

server.listen(config.port, () => {
  console.log(`Супер Няня API слушает порт ${config.port}; данные: ${config.dataDir}`);
  console.log(`SMS: ${smsEnabled() ? 'Eskiz' : 'демо-режим (код возвращается в ответе)'}; демо-няни: ${config.demo ? 'вкл' : 'выкл'}`);
  if (!config.adminPasswordFromEnv) console.log(`Пароль админки (задайте ADMIN_PASSWORD, чтобы сменить): ${config.adminPassword}`);
});

function shutdown() {
  server.close(() => {
    db.close();
    process.exit(0);
  });
  setTimeout(() => process.exit(0), 5000).unref();
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
