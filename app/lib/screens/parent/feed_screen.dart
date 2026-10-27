import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/location.dart';
import '../../core/theme.dart';
import '../../models.dart';
import '../../widgets/common.dart';
import '../../widgets/swipe_deck.dart';
import 'create_order_screen.dart';
import 'nanny_detail_screen.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _deck = GlobalKey<SwipeDeckState>();
  LatLng? _pos;
  bool _fallback = false;
  int _radius = 5;
  List<NannyCard>? _items;
  Object? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool relocate = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_pos == null || relocate) {
        _pos = await currentLocation();
        _fallback = false;
      }
      final p = _pos!;
      final res = Map<String, dynamic>.from(
        await Api.instance.get('/api/nannies?lat=${p.latitude}&lng=${p.longitude}&radius_km=$_radius') as Map,
      );
      final items = (res['items'] as List).map((e) => NannyCard.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (!mounted) return;
      setState(() => _items = items);
      _precache(0);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Предзагрузка фото 6 следующих карточек — свайп без задержек.
  void _precache(int from) {
    final items = _items;
    if (items == null) return;
    for (final n in items.skip(from).take(6)) {
      if (n.photoId != null) precacheImage(authImage(n.photoId!), context).ignore();
    }
  }

  void _useFallback() {
    _pos = const LatLng(kFallbackLat, kFallbackLng);
    _fallback = true;
    _load();
  }

  Future<void> _onSwiped(NannyCard n, SwipeDirection dir) async {
    if (dir == SwipeDirection.left) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => CreateOrderScreen(nanny: n, point: _pos!)));
  }

  Future<void> _openDetail(NannyCard n) async {
    final choose = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => NannyDetailScreen(nannyId: n.id, point: _pos, showChoose: true)),
    );
    if (choose == true) _deck.currentState?.swipe(SwipeDirection.right);
  }

  Future<void> _pickRadius() async {
    var value = _radius.toDouble();
    final result = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Радиус поиска', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('Показывать нянь не дальше ${value.round()} км', style: const TextStyle(color: kMuted)),
                Slider(value: value, min: 1, max: 15, divisions: 14, label: '${value.round()} км', onChanged: (v) => set(() => value = v)),
                const SizedBox(height: 8),
                FilledButton(onPressed: () => Navigator.pop(ctx, value.round()), child: const Text('Применить')),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null && result != _radius) {
      setState(() => _radius = result);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(children: [AppLogo(size: 34), SizedBox(width: 10), Text('Супер Няня')]),
        actions: [
          ActionChip(
            avatar: const Icon(Icons.tune_rounded, size: 18),
            label: Text('до $_radius км'),
            onPressed: _pickRadius,
            backgroundColor: Colors.white,
            side: const BorderSide(color: kLine),
          ),
          IconButton(onPressed: _loading ? null : () => _load(relocate: !_fallback), icon: const Icon(Icons.refresh_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_error is LocationUnavailable) {
      final e = _error as LocationUnavailable;
      return EmptyView(
        icon: Icons.location_off_rounded,
        title: 'Нужна геолокация',
        subtitle: '${e.message}.\nМы показываем нянь, которые находятся рядом с вами.',
        action: Column(children: [
          SizedBox(
            width: 260,
            child: FilledButton(
              onPressed: e.canOpenSettings ? () => Geolocator.openAppSettings() : () => _load(relocate: true),
              child: Text(e.canOpenSettings ? 'Открыть настройки' : 'Разрешить доступ'),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(onPressed: _useFallback, child: const Text('Показать нянь в центре Ташкента')),
        ]),
      );
    }
    if (_error != null && _items == null) {
      return ErrorView(message: _error is ApiException ? (_error as ApiException).message : '$_error', onRetry: _load);
    }
    if (_items == null) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        if (_fallback)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: InfoPlate(child: Text('Показаны няни в центре Ташкента — геолокация недоступна')),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SwipeDeck(
              key: _deck,
              items: _items!,
              onSwiped: _onSwiped,
              onTap: _openDetail,
              onIndexChanged: _precache,
              empty: EmptyView(
                icon: Icons.child_friendly_rounded,
                title: 'Рядом пока нет свободных нянь',
                subtitle: 'Попробуйте увеличить радиус поиска или обновить ленту через пару минут.',
                action: Wrap(spacing: 8, children: [
                  OutlinedButton(onPressed: _pickRadius, child: const Text('Радиус')),
                  FilledButton(onPressed: _load, child: const Text('Обновить')),
                ]),
              ),
            ),
          ),
        ),
        if (_items!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundAction(icon: Icons.close_rounded, color: kPink, size: 64, onTap: () => _deck.currentState?.swipe(SwipeDirection.left)),
                const SizedBox(width: 20),
                _RoundAction(
                  icon: Icons.info_outline_rounded,
                  color: kPrimary,
                  size: 50,
                  onTap: () {
                    final c = _deck.currentState?.current;
                    if (c != null) _openDetail(c);
                  },
                ),
                const SizedBox(width: 20),
                _RoundAction(icon: Icons.favorite_rounded, color: kOk, size: 64, onTap: () => _deck.currentState?.swipe(SwipeDirection.right)),
              ],
            ),
          ),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.icon, required this.color, required this.size, required this.onTap});

  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: kPrimary.withValues(alpha: 0.25),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: size, height: size, child: Icon(icon, color: color, size: size * 0.48)),
      ),
    );
  }
}
