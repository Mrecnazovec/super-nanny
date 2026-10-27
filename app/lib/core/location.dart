import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

class LocationUnavailable implements Exception {
  LocationUnavailable(this.message, {this.canOpenSettings = false});

  final String message;
  final bool canOpenSettings;

  @override
  String toString() => message;
}

/// Проверяет службу геолокации и разрешение, при необходимости запрашивает его.
Future<void> ensureLocationPermission() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw LocationUnavailable('Включите геолокацию на телефоне', canOpenSettings: true);
  }
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
  if (perm == LocationPermission.denied) {
    throw LocationUnavailable('Разрешите доступ к геолокации, чтобы найти нянь рядом');
  }
  if (perm == LocationPermission.deniedForever) {
    throw LocationUnavailable('Доступ к геолокации запрещён. Разрешите его в настройках', canOpenSettings: true);
  }
}

Future<LatLng> currentLocation() async {
  await ensureLocationPermission();
  try {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
    );
    return LatLng(p.latitude, p.longitude);
  } catch (_) {
    final last = await Geolocator.getLastKnownPosition();
    if (last != null) return LatLng(last.latitude, last.longitude);
    throw LocationUnavailable('Не удалось определить местоположение');
  }
}

/// Быстрая позиция для SOS: последняя известная, иначе свежая с коротким таймаутом.
Future<LatLng?> quickLocation() async {
  try {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    final last = await Geolocator.getLastKnownPosition();
    if (last != null && DateTime.now().difference(last.timestamp).inMinutes < 2) {
      return LatLng(last.latitude, last.longitude);
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 6)),
    );
    return LatLng(p.latitude, p.longitude);
  } catch (_) {
    final last = await Geolocator.getLastKnownPosition();
    return last == null ? null : LatLng(last.latitude, last.longitude);
  }
}

/// Трансляция GPS няни, пока она «на линии».
/// Работает как foreground-сервис (уведомление в шторке), поэтому не останавливается в фоне.
/// Точки копятся в локальной очереди и уходят на сервер пачками — при обрыве связи ничего не теряется.
class LocationTracker extends ChangeNotifier {
  LocationTracker._();

  static final LocationTracker instance = LocationTracker._();
  static const _queueKey = 'gps_queue';
  static const _maxQueue = 2000;

  StreamSubscription<Position>? _sub;
  Timer? _flushTimer;
  final List<Map<String, dynamic>> _queue = [];
  bool _flushing = false;
  LatLng? last;

  bool get running => _sub != null;
  int get pending => _queue.length;

  Future<void> start() async {
    if (running) return;
    await ensureLocationPermission();
    await _restoreQueue();
    final settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 15,
            intervalDuration: const Duration(seconds: 10),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Супер Няня: вы на линии',
              notificationText: 'Геопозиция передаётся для поиска заказов и безопасности',
              enableWakeLock: true,
              setOngoing: true,
            ),
          )
        : const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15);
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (p) {
        last = LatLng(p.latitude, p.longitude);
        _queue.add({'lat': p.latitude, 'lng': p.longitude, 'ts': p.timestamp.millisecondsSinceEpoch});
        if (_queue.length > _maxQueue) _queue.removeRange(0, _queue.length - _maxQueue);
        _persistQueue();
        notifyListeners();
      },
      onError: (_) {},
    );
    _flushTimer = Timer.periodic(const Duration(seconds: 10), (_) => flush());
    notifyListeners();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    await flush();
    notifyListeners();
  }

  Future<void> flush() async {
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    try {
      while (_queue.isNotEmpty) {
        final batch = _queue.take(500).toList();
        await Api.instance.post('/api/nanny/location', {'points': batch});
        _queue.removeRange(0, batch.length);
      }
      await _persistQueue();
    } catch (_) {
      // нет сети — повторим на следующем тике
    } finally {
      _flushing = false;
      notifyListeners();
    }
  }

  Future<void> _restoreQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null || _queue.isNotEmpty) return;
    try {
      _queue.addAll((jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) {}
  }

  Future<void> _persistQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_queueKey, jsonEncode(_queue));
  }
}
