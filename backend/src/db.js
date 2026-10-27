'use strict';
const path = require('node:path');
const { DatabaseSync } = require('node:sqlite');
const config = require('./config');

const db = new DatabaseSync(path.join(config.dataDir, 'app.db'));

db.exec(`
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA busy_timeout = 5000;

CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY,
  phone TEXT UNIQUE NOT NULL,
  name TEXT,
  role TEXT,
  company_id INTEGER,
  blocked INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS otp (
  phone TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  attempts INTEGER NOT NULL DEFAULT 0,
  sent_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
  hash TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS companies (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  code TEXT UNIQUE NOT NULL,
  spent INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS nannies (
  user_id INTEGER PRIMARY KEY,
  full_name TEXT,
  age INTEGER,
  experience INTEGER,
  about TEXT,
  price INTEGER,
  schedule TEXT,
  status TEXT NOT NULL DEFAULT 'draft',
  reject_reason TEXT,
  med_ok INTEGER NOT NULL DEFAULT 0,
  police_ok INTEGER NOT NULL DEFAULT 0,
  online INTEGER NOT NULL DEFAULT 0,
  lat REAL,
  lng REAL,
  loc_at INTEGER,
  rating_sum INTEGER NOT NULL DEFAULT 0,
  rating_count INTEGER NOT NULL DEFAULT 0,
  balance INTEGER NOT NULL DEFAULT 0,
  is_demo INTEGER NOT NULL DEFAULT 0,
  demo_dlat REAL,
  demo_dlng REAL,
  submitted_at INTEGER,
  verified_at INTEGER
);

CREATE TABLE IF NOT EXISTS documents (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL,
  kind TEXT NOT NULL,
  mime TEXT NOT NULL,
  file TEXT NOT NULL,
  size INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS documents_user ON documents(user_id, kind);

CREATE TABLE IF NOT EXISTS cards (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL,
  type TEXT NOT NULL,
  mask TEXT NOT NULL,
  expiry TEXT NOT NULL,
  token TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS orders (
  id INTEGER PRIMARY KEY,
  parent_id INTEGER NOT NULL,
  nanny_id INTEGER NOT NULL,
  type TEXT NOT NULL,
  scheduled_at INTEGER,
  children_count INTEGER NOT NULL,
  children_ages TEXT,
  notes TEXT,
  address TEXT,
  lat REAL NOT NULL,
  lng REAL NOT NULL,
  corporate INTEGER NOT NULL DEFAULT 0,
  company_id INTEGER,
  card_id INTEGER,
  price INTEGER NOT NULL,
  hold_amount INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at INTEGER NOT NULL,
  accepted_at INTEGER,
  started_at INTEGER,
  finished_at INTEGER,
  updated_at INTEGER NOT NULL,
  minutes INTEGER,
  total INTEGER,
  commission INTEGER,
  nanny_earning INTEGER,
  cancel_reason TEXT,
  cancelled_by TEXT
);
CREATE INDEX IF NOT EXISTS orders_parent ON orders(parent_id, created_at);
CREATE INDEX IF NOT EXISTS orders_nanny ON orders(nanny_id, status);
CREATE INDEX IF NOT EXISTS orders_status ON orders(status);

CREATE TABLE IF NOT EXISTS track (
  order_id INTEGER NOT NULL,
  lat REAL NOT NULL,
  lng REAL NOT NULL,
  ts INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS track_order ON track(order_id, ts);

CREATE TABLE IF NOT EXISTS messages (
  id INTEGER PRIMARY KEY,
  order_id INTEGER NOT NULL,
  sender_id INTEGER NOT NULL,
  text TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS messages_order ON messages(order_id, id);

CREATE TABLE IF NOT EXISTS chat_reads (
  order_id INTEGER NOT NULL,
  user_id INTEGER NOT NULL,
  last_id INTEGER NOT NULL,
  PRIMARY KEY (order_id, user_id)
);

CREATE TABLE IF NOT EXISTS reviews (
  id INTEGER PRIMARY KEY,
  order_id INTEGER UNIQUE NOT NULL,
  parent_id INTEGER NOT NULL,
  nanny_id INTEGER NOT NULL,
  rating INTEGER NOT NULL,
  text TEXT,
  author_name TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS reviews_nanny ON reviews(nanny_id, created_at);

CREATE TABLE IF NOT EXISTS payments (
  id INTEGER PRIMARY KEY,
  order_id INTEGER NOT NULL,
  method TEXT NOT NULL,
  card_id INTEGER,
  company_id INTEGER,
  amount INTEGER NOT NULL,
  status TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS payments_order ON payments(order_id);

CREATE TABLE IF NOT EXISTS wallet_tx (
  id INTEGER PRIMARY KEY,
  nanny_id INTEGER NOT NULL,
  amount INTEGER NOT NULL,
  kind TEXT NOT NULL,
  order_id INTEGER,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS wallet_tx_nanny ON wallet_tx(nanny_id, id);

CREATE TABLE IF NOT EXISTS withdrawals (
  id INTEGER PRIMARY KEY,
  nanny_id INTEGER NOT NULL,
  amount INTEGER NOT NULL,
  card_mask TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  created_at INTEGER NOT NULL,
  processed_at INTEGER
);

CREATE TABLE IF NOT EXISTS sos (
  id INTEGER PRIMARY KEY,
  user_id INTEGER NOT NULL,
  order_id INTEGER,
  lat REAL,
  lng REAL,
  resolved INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  resolved_at INTEGER
);
`);

// node:sqlite не умеет биндить undefined и boolean — приводим заранее.
const norm = (params) => params.map((v) => (v === undefined ? null : typeof v === 'boolean' ? Number(v) : v));

const cache = new Map();
function stmt(sql) {
  let s = cache.get(sql);
  if (!s) {
    s = db.prepare(sql);
    cache.set(sql, s);
  }
  return s;
}

const one = (sql, ...p) => stmt(sql).get(...norm(p));
const all = (sql, ...p) => stmt(sql).all(...norm(p));
const run = (sql, ...p) => stmt(sql).run(...norm(p));

function tx(fn) {
  db.exec('BEGIN IMMEDIATE');
  try {
    const result = fn();
    db.exec('COMMIT');
    return result;
  } catch (e) {
    db.exec('ROLLBACK');
    throw e;
  }
}

module.exports = { db, one, all, run, tx };
