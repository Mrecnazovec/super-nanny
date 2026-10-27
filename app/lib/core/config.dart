/// Адрес бэкенда задаётся при сборке: flutter build apk --dart-define=API_URL=https://...
/// Для эмулятора по умолчанию — локальный сервер на машине разработчика.
const String kDefaultApiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:3000');

const String kAppVersion = '1.0.0';

/// Центр Ташкента — запасная точка, если геолокация недоступна.
const double kFallbackLat = 41.3111;
const double kFallbackLng = 69.2797;
