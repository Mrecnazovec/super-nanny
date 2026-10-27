'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const DATA_DIR = path.resolve(process.env.DATA_DIR || path.join(__dirname, '..', 'data'));
fs.mkdirSync(path.join(DATA_DIR, 'files'), { recursive: true });

// Секреты, не заданные через env, генерируются один раз и хранятся в томе с данными,
// чтобы перезапуск контейнера не разлогинивал пользователей и не терял ключ шифрования файлов.
function loadSecrets() {
  const file = path.join(DATA_DIR, 'secrets.json');
  let s = {};
  try {
    s = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {}
  let changed = false;
  if (!s.jwtSecret) { s.jwtSecret = crypto.randomBytes(48).toString('base64'); changed = true; }
  if (!s.filesKey) { s.filesKey = crypto.randomBytes(32).toString('base64'); changed = true; }
  if (!s.adminPassword) { s.adminPassword = crypto.randomBytes(9).toString('base64url'); changed = true; }
  if (changed) fs.writeFileSync(file, JSON.stringify(s, null, 2), { mode: 0o600 });
  return s;
}

const secrets = loadSecrets();
const env = process.env;

const filesKey = Buffer.from(env.FILES_KEY || secrets.filesKey, 'base64');
if (filesKey.length !== 32) throw new Error('FILES_KEY должен быть 32 байта в base64');

module.exports = {
  port: Number(env.PORT) || 3000,
  dataDir: DATA_DIR,
  filesDir: path.join(DATA_DIR, 'files'),
  jwtSecret: env.JWT_SECRET || secrets.jwtSecret,
  filesKey,
  adminPassword: env.ADMIN_PASSWORD || secrets.adminPassword,
  adminPasswordFromEnv: Boolean(env.ADMIN_PASSWORD),
  demo: env.DEMO !== '0',
  commission: 0.12,
  holdHours: 2,
  arrivalRadiusM: Number(env.ARRIVAL_RADIUS_M) || 100,
  acceptTimeoutMs: 60_000,
  accessTtlSec: 30 * 60,
  refreshTtlMs: 30 * 24 * 3600_000,
  eskiz: {
    email: env.ESKIZ_EMAIL || '',
    password: env.ESKIZ_PASSWORD || '',
    from: env.ESKIZ_FROM || '4546',
  },
  telegram: {
    token: env.TELEGRAM_BOT_TOKEN || '',
    chatId: env.TELEGRAM_CHAT_ID || '',
  },
};
