'use strict';
const { one, all, run } = require('../db');
const { fail } = require('../lib/http');
const { authenticate } = require('../lib/auth');
const files = require('../lib/files');

const KINDS = ['photo', 'passport', 'selfie', 'medbook', 'police', 'cert'];
const KYC = ['passport', 'selfie', 'medbook', 'police'];
const PUBLIC_KINDS = ['photo', 'cert']; // видны родителям у одобренных нянь
const MAX_SIZE = 6 * 1024 * 1024;

module.exports = (r) => {
  // Загрузка: тело запроса — сам файл (image/jpeg, png, webp или pdf), без multipart.
  r.put('/api/files/:kind', async (ctx) => {
    const user = authenticate(ctx, ['nanny']);
    const kind = ctx.params.kind;
    if (!KINDS.includes(kind)) fail(400, 'Неизвестный тип документа');
    const nanny = one('SELECT status FROM nannies WHERE user_id = ?', user.id);
    if (KYC.includes(kind) && ['pending', 'approved'].includes(nanny?.status)) {
      fail(409, 'Документы уже на проверке или одобрены');
    }
    const buf = await ctx.raw(MAX_SIZE);
    const mime = files.detectMime(buf);
    if (!mime) fail(400, 'Поддерживаются JPEG, PNG, WEBP и PDF');
    if (kind === 'photo' && mime === 'application/pdf') fail(400, 'Фото профиля должно быть изображением');

    if (kind === 'cert') {
      if (one("SELECT COUNT(*) AS c FROM documents WHERE user_id = ? AND kind = 'cert'", user.id).c >= 10) {
        fail(400, 'Можно загрузить не больше 10 сертификатов');
      }
    } else {
      for (const d of all('SELECT id, file FROM documents WHERE user_id = ? AND kind = ?', user.id, kind)) {
        files.remove(d.file);
        run('DELETE FROM documents WHERE id = ?', d.id);
      }
    }
    const name = files.save(buf);
    const id = run(
      'INSERT INTO documents(user_id, kind, mime, file, size, created_at) VALUES (?,?,?,?,?,?)',
      user.id, kind, mime, name, buf.length, Date.now()
    ).lastInsertRowid;
    return { id, kind, mime };
  });

  r.get('/api/files/:id', (ctx) => {
    const user = authenticate(ctx, ['parent', 'nanny', 'admin']);
    const doc = one('SELECT * FROM documents WHERE id = ?', Number(ctx.params.id));
    if (!doc) fail(404, 'Файл не найден');
    let allowed = user.role === 'admin' || doc.user_id === user.id;
    if (!allowed && PUBLIC_KINDS.includes(doc.kind)) {
      allowed = Boolean(one("SELECT 1 FROM nannies WHERE user_id = ? AND status = 'approved'", doc.user_id));
    }
    if (!allowed) fail(404, 'Файл не найден');
    let buf;
    try {
      buf = files.read(doc.file);
    } catch {
      fail(404, 'Файл недоступен');
    }
    ctx.res.writeHead(200, {
      'Content-Type': doc.mime,
      'Content-Length': buf.length,
      'Cache-Control': 'private, max-age=86400',
    });
    ctx.res.end(buf);
  });

  r.delete('/api/files/:id', (ctx) => {
    const user = authenticate(ctx, ['nanny']);
    const doc = one("SELECT * FROM documents WHERE id = ? AND user_id = ? AND kind = 'cert'", Number(ctx.params.id), user.id);
    if (!doc) fail(404, 'Файл не найден');
    files.remove(doc.file);
    run('DELETE FROM documents WHERE id = ?', doc.id);
    return { ok: true };
  });
};

module.exports.KYC = KYC;
