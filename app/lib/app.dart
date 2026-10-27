import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/api.dart';
import 'core/theme.dart';
import 'screens/auth/phone_screen.dart';
import 'screens/auth/role_screen.dart';
import 'screens/nanny/nanny_root.dart';
import 'screens/parent/parent_home.dart';
import 'state/session.dart';
import 'widgets/common.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class SuperNannyApp extends StatelessWidget {
  const SuperNannyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Супер Няня',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: buildTheme(),
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Тап мимо поля ввода прячет клавиатуру.
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: ConnectivityBanner(child: child ?? const SizedBox()),
      ),
      home: const RootGate(),
    );
  }
}

/// Выбирает стартовый экран по состоянию сессии.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(sessionProvider, (prev, next) {
      // При выходе / истечении сессии закрываем все вложенные экраны.
      final was = prev?.value;
      if (was != null && next.hasValue && next.value == null) {
        navigatorKey.currentState?.popUntil((r) => r.isFirst);
      }
    });
    final session = ref.watch(sessionProvider);
    return session.when(
      skipLoadingOnRefresh: true,
      skipLoadingOnReload: true,
      loading: () => const SplashScreen(),
      error: (e, _) => Scaffold(
        body: ErrorView(
          message: e is ApiException ? e.message : 'Не удалось загрузить данные',
          onRetry: () => ref.invalidate(sessionProvider),
        ),
      ),
      data: (user) {
        if (user == null) return const PhoneScreen();
        if (user.role == null || (user.name ?? '').isEmpty) return const RoleScreen();
        if (user.isParent) return const ParentHome();
        return const NannyRoot();
      },
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppLogo(size: 88),
            SizedBox(height: 20),
            Text('Супер Няня', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kPrimary)),
            SizedBox(height: 28),
            SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          ],
        ),
      ),
    );
  }
}

/// Плашка «Нет соединения» поверх любого экрана.
class ConnectivityBanner extends StatefulWidget {
  const ConnectivityBanner({super.key, required this.child});

  final Widget child;

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    Connectivity().checkConnectivity().then(_update);
    _sub = Connectivity().onConnectivityChanged.listen(_update);
  }

  void _update(List<ConnectivityResult> r) {
    final offline = r.isEmpty || r.every((e) => e == ConnectivityResult.none);
    if (mounted && offline != _offline) setState(() => _offline = offline);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: IgnorePointer(
            child: AnimatedSlide(
              offset: _offline ? Offset.zero : const Offset(0, -1),
              duration: const Duration(milliseconds: 250),
              child: Material(
                color: kPink,
                child: SafeArea(
                  bottom: false,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_off_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text('Нет соединения', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
