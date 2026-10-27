# Супер Няня — бэкенд

Node.js 22.13+ без единой npm-зависимости: HTTP — `node:http`, база — встроенный `node:sqlite`, JWT и шифрование — `node:crypto`.
В Docker-контейнере занимает ~40–60 МБ RAM, сборка образа — простое копирование файлов.

## Запуск

```bash
npm start            # http://localhost:3000, данные в ./data
npm run smoke        # сквозной тест основного сценария на временной базе
```

Docker: `docker build -t super-nanny . && docker run -p 3000:3000 -v nanny-data:/data super-nanny`

## Переменные окружения

| Переменная | Назначение |
|---|---|
| `ADMIN_PASSWORD` | пароль панели модератора `/admin` (если не задан — генерируется и печатается в лог) |
| `DEMO` | `0` — выключить демо-нянь (по умолчанию включены) |
| `ESKIZ_EMAIL`, `ESKIZ_PASSWORD`, `ESKIZ_FROM` | SMS через Eskiz.uz. Без них — демо-режим: OTP возвращается в ответе |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | мгновенные SOS-алерты админам в Telegram |
| `ARRIVAL_RADIUS_M` | радиус сверки «На месте», по умолчанию 100 м |
| `JWT_SECRET`, `FILES_KEY` | необязательно: иначе генерируются и хранятся в `/data/secrets.json` |
| `DATA_DIR`, `PORT` | по умолчанию `/data` и `3000` в контейнере |

Всё состояние — в одном томе `/data` (SQLite + зашифрованные AES-256-GCM файлы документов). Бэкап = копия тома.

## Что реализовано

- Вход по телефону +998 и OTP, JWT access (30 мин) + ротация refresh-токенов.
- Роли: родитель, няня, модератор (веб-панель `/admin`).
- KYC няни: анкета, фото, паспорт, селфи с паспортом, медкнижка, справка МВД. Документы шифруются на диске и отдаются только владельцу и модератору.
- Лента: одобренные няни «на линии» в радиусе 1–15 км, ближайшие первыми.
- Заказ: «сейчас» / на время, дети, отметки, B2B-оплата с корпоративного счёта, холд за 2 часа.
- 60 секунд на принятие, статусы «Принять → Выехала → На месте (сверка 100 м) → Работа → Завершить».
- Трекинг GPS (пакетная отправка точек), чат по заказу, SOS с координатами.
- Расчёт по факту (минимум 1 час), комиссия 12%, кошелёк няни и заявки на вывод.
- Отзывы и рейтинг.

## Что подключается позже (заглушки готовы)

- **Payme / Click**: `POST /api/cards` хранит маску и токен-заглушку; `payments` фиксирует held → charged / released. Сюда встаёт Save Card API и сплитование 88/12.
- **Eskiz.uz**: уже поддерживается, нужны только переменные окружения.
- **FCM push**: сейчас приложение опрашивает сервер (няня «на линии» — раз в 3 с).

## API (кратко)

```
POST /api/auth/otp {phone}            POST /api/auth/verify {phone, code}
POST /api/auth/refresh {refresh}      GET/PATCH /api/me
POST/DELETE /api/me/company           GET/POST/DELETE /api/cards
PUT  /api/files/:kind (сырое тело)    GET /api/files/:id
GET/PUT /api/nanny/profile            POST /api/nanny/submit | online | location | withdraw
GET  /api/nanny/incoming | wallet     GET /api/nannies?lat&lng&radius_km, /api/nannies/:id
POST /api/orders                      GET /api/orders, /api/orders/:id
POST /api/orders/:id/accept|decline|status|cancel|review
GET/POST /api/orders/:id/messages     GET /api/chats      POST /api/sos
/api/admin/* — login, stats, nannies (approve/reject), sos, users, orders, companies, withdrawals
```
