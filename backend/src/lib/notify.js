'use strict';
const config = require('../config');

// ---------- SMS через Eskiz.uz (включается, если заданы ESKIZ_EMAIL и ESKIZ_PASSWORD) ----------

let eskizToken = null;
let eskizTokenAt = 0;

const smsEnabled = () => Boolean(config.eskiz.email && config.eskiz.password);

async function eskizLogin() {
  const form = new FormData();
  form.set('email', config.eskiz.email);
  form.set('password', config.eskiz.password);
  const r = await fetch('https://notify.eskiz.uz/api/auth/login', { method: 'POST', body: form, signal: AbortSignal.timeout(10_000) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j?.data?.token) throw new Error(`Eskiz login failed: ${r.status}`);
  eskizToken = j.data.token;
  eskizTokenAt = Date.now();
}

async function sendSms(phone, text) {
  if (!eskizToken || Date.now() - eskizTokenAt > 20 * 24 * 3600_000) await eskizLogin();
  const attempt = () => {
    const form = new FormData();
    form.set('mobile_phone', phone.replace(/\D/g, ''));
    form.set('message', text);
    form.set('from', config.eskiz.from);
    return fetch('https://notify.eskiz.uz/api/message/sms/send', {
      method: 'POST',
      headers: { Authorization: `Bearer ${eskizToken}` },
      body: form,
      signal: AbortSignal.timeout(10_000),
    });
  };
  let r = await attempt();
  if (r.status === 401) {
    await eskizLogin();
    r = await attempt();
  }
  if (!r.ok) throw new Error(`Eskiz send failed: ${r.status}`);
}

// ---------- Алерты админам в Telegram (TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID) ----------

async function alertAdmins(text) {
  if (!config.telegram.token || !config.telegram.chatId) return;
  try {
    await fetch(`https://api.telegram.org/bot${config.telegram.token}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: config.telegram.chatId, text, disable_web_page_preview: true }),
      signal: AbortSignal.timeout(10_000),
    });
  } catch (e) {
    console.error('Telegram alert failed:', e.message);
  }
}

module.exports = { smsEnabled, sendSms, alertAdmins };
