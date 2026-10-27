# Супер Няня — MVP

Агрегатор верифицированных нянь для Узбекистана: свайп-лента, KYC нянь, заказ с GPS-трекингом и SOS, оплата с комиссией 12%, B2B.

```
app/       Flutter-приложение (Android APK), Riverpod
backend/   Node.js без зависимостей + встроенный SQLite, веб-панель модератора /admin
```

Упрощения относительно ТЗ (чтобы сервер оставался лёгким):

| ТЗ | В MVP |
|---|---|
| NestJS + PostgreSQL + Redis | один процесс Node.js + SQLite (WAL), гео-поиск — bbox + Haversine |
| AWS S3 + presigned URLs | файлы на томе, шифрование AES-256-GCM, выдача только через API с проверкой прав |
| WebSockets | короткий polling (чат 3 с, трекинг 4 с, входящие заявки 3 с) |
| Google / Yandex Maps | OpenStreetMap (flutter_map), без API-ключа |
| FCM push | polling + вибрация/звук в приложении |
| Payme / Click, Eskiz | эмуляция холда/списания; Eskiz включается переменными окружения |
| React-админка | одна HTML-страница `/admin`, встроенная в бэкенд |

## Сборка APK

```bash
cd app
flutter build apk --release --dart-define=API_URL=https://<домен-бэкенда>
```

Ключ подписи: `app/android/key.properties` + `app/android/app/supernanny-release.jks` (в git не попадают — храните копию отдельно,
без него нельзя будет выпустить обновление поверх установленного приложения).

Подробнее о бэкенде — в [backend/README.md](backend/README.md).
