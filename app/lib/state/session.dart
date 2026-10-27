import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/location.dart';
import '../models.dart';

/// Текущий пользователь. null — не вошёл.
final sessionProvider = AsyncNotifierProvider<SessionNotifier, AppUser?>(SessionNotifier.new);

class SessionNotifier extends AsyncNotifier<AppUser?> {
  @override
  Future<AppUser?> build() async {
    final api = Api.instance;
    api.onSessionExpired = () {
      unawaited(LocationTracker.instance.stop());
      state = const AsyncData(null);
    };
    await api.init();
    if (!api.hasSession) return null;
    try {
      return AppUser.fromJson(Map<String, dynamic>.from(await api.get('/api/me') as Map));
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) {
        await api.clearTokens();
        return null;
      }
      rethrow;
    }
  }

  /// После успешного ввода OTP.
  Future<void> signIn(Map<String, dynamic> verifyResponse) async {
    await Api.instance.saveTokens(verifyResponse);
    state = AsyncData(AppUser.fromJson(Map<String, dynamic>.from(verifyResponse['user'] as Map)));
  }

  void setUser(Map<String, dynamic> json) => state = AsyncData(AppUser.fromJson(json));

  Future<AppUser> reload() async {
    final user = AppUser.fromJson(Map<String, dynamic>.from(await Api.instance.get('/api/me') as Map));
    state = AsyncData(user);
    return user;
  }

  Future<void> logout() async {
    await LocationTracker.instance.stop();
    await Api.instance.logout();
    state = const AsyncData(null);
  }
}
