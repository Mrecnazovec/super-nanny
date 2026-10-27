'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const config = require('../config');

// Файлы (паспорта, справки, фото) лежат на диске только в зашифрованном виде: AES-256-GCM.
// Формат: iv(12) | tag(16) | ciphertext. Отдаются исключительно через API с проверкой прав.

const NAME_RE = /^[a-f0-9]{32}$/;

function detectMime(buf) {
  if (buf.length < 12) return null;
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (buf.toString('ascii', 0, 4) === 'RIFF' && buf.toString('ascii', 8, 12) === 'WEBP') return 'image/webp';
  if (buf.toString('ascii', 0, 5) === '%PDF-') return 'application/pdf';
  return null;
}

function save(buf) {
  const name = crypto.randomBytes(16).toString('hex');
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', config.filesKey, iv);
  const enc = Buffer.concat([cipher.update(buf), cipher.final()]);
  fs.writeFileSync(path.join(config.filesDir, name), Buffer.concat([iv, cipher.getAuthTag(), enc]));
  return name;
}

function read(name) {
  if (!NAME_RE.test(name)) throw new Error('bad file name');
  const data = fs.readFileSync(path.join(config.filesDir, name));
  const decipher = crypto.createDecipheriv('aes-256-gcm', config.filesKey, data.subarray(0, 12));
  decipher.setAuthTag(data.subarray(12, 28));
  return Buffer.concat([decipher.update(data.subarray(28)), decipher.final()]);
}

function remove(name) {
  if (NAME_RE.test(name)) fs.rmSync(path.join(config.filesDir, name), { force: true });
}

module.exports = { detectMime, save, read, remove };
