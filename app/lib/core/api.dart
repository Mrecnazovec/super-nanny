import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

class ApiException implements Exception {
  ApiException(this.status, this.message);

  final int status;
  final String message;

  bool get isNetwork => status == 0;

  @override
  String toString() => message;
}

/// HTTP-клиент: JWT access + refresh, прозрачное обновление токена (single-flight).
class Api {
  Api._();

  static final Api instance = Api._();

  final http.Client _client = http.Client();
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String baseUrl = kDefaultApiUrl;
  String? _access;
  String? _refresh;
  Future<bool>? _refreshing;

  /// Вызывается, когда сессию восстановить не удалось — приложение возвращается на вход.
  void Function()? onSessionExpired;

  bool get hasSession => _refresh != null;

  Map<String, String> get authHeaders => {if (_access != null) 'Authorization': 'Bearer $_access'};

  String fileUrl(int id) => '$baseUrl/api/files/$id';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString('api_url') ?? kDefaultApiUrl;
    try {
      _access = await _storage.read(key: 'access');
      _refresh = await _storage.read(key: 'refresh');
    } catch (_) {
      _access = null;
      _refresh = null;
    }
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_url', baseUrl);
  }

  Future<void> saveTokens(Map<String, dynamic> json) async {
    _access = json['access'] as String?;
    _refresh = json['refresh'] as String?;
    try {
      await _storage.write(key: 'access', value: _access);
      await _storage.write(key: 'refresh', value: _refresh);
    } catch (_) {}
  }

  Future<void> clearTokens() async {
    _access = null;
    _refresh = null;
    try {
      await _storage.delete(key: 'access');
      await _storage.delete(key: 'refresh');
    } catch (_) {}
  }

  Future<void> logout() async {
    final refresh = _refresh;
    await clearTokens();
    if (refresh != null) {
      try {
        await _send('POST', '/api/auth/logout', body: {'refresh': refresh}, retry: false);
      } catch (_) {}
    }
  }

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body ?? const {});
  Future<dynamic> put(String path, Object body) => _send('PUT', path, body: body);
  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);
  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> upload(String path, Uint8List bytes, String contentType) =>
      _send('PUT', path, bytes: bytes, contentType: contentType);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Uint8List? bytes,
    String? contentType,
    bool retry = true,
  }) async {
    final req = http.Request(method, Uri.parse('$baseUrl$path'));
    req.headers.addAll(authHeaders);
    if (bytes != null) {
      req.headers['Content-Type'] = contentType ?? 'application/octet-stream';
      req.bodyBytes = bytes;
    } else if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }

    http.Response res;
    try {
      final streamed = await _client.send(req).timeout(Duration(seconds: bytes != null ? 90 : 20));
      res = await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw ApiException(0, 'Сервер не отвечает. Проверьте интернет');
    } on SocketException {
      throw ApiException(0, 'Нет соединения с сервером');
    } on http.ClientException {
      throw ApiException(0, 'Нет соединения с сервером');
    } on HandshakeException {
      throw ApiException(0, 'Ошибка защищённого соединения');
    }

    if (res.statusCode == 401 && retry && _refresh != null && !path.startsWith('/api/auth/')) {
      if (await _refreshTokens()) {
        return _send(method, path, body: body, bytes: bytes, contentType: contentType, retry: false);
      }
      await clearTokens();
      onSessionExpired?.call();
    }

    final text = utf8.decode(res.bodyBytes, allowMalformed: true);
    dynamic data;
    try {
      data = text.isEmpty ? null : jsonDecode(text);
    } catch (_) {
      data = text;
    }
    if (res.statusCode >= 400) {
      final msg = data is Map && data['error'] is String ? data['error'] as String : 'Ошибка сервера (${res.statusCode})';
      throw ApiException(res.statusCode, msg);
    }
    return data;
  }

  Future<bool> _refreshTokens() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final refresh = _refresh;
    if (refresh == null) return false;
    try {
      final data = await _send('POST', '/api/auth/refresh', body: {'refresh': refresh}, retry: false);
      await saveTokens(Map<String, dynamic>.from(data as Map));
      return true;
    } on ApiException catch (e) {
      // Сетевые ошибки не должны выкидывать пользователя из аккаунта.
      if (e.isNetwork) rethrow;
      return false;
    }
  }
}
