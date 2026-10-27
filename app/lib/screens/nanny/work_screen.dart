import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/location.dart';
import '../../core/theme.dart';
import '../../models.dart';
import '../../widgets/common.dart';
import '../common/order_screen.dart';
import 'wallet_screen.dart';

/// Рабочий экран няни: тумблер «На линии», входящие заявки, активные заказы, баланс.
class WorkScreen extends StatefulWidget {
  const WorkScreen({super.key});

  @override
  State<WorkScreen> createState() => _WorkScreenState();
}

class _WorkScreenState extends State<WorkScreen> with WidgetsBindingObserver {
  NannyProfile? _p;
  List<Order> _active = [];
  bool _online = false;
  bool _switching = false;
  Timer? _incomingTimer;
  Timer? _refreshTimer;
  final _shown = <int>{};
  bool _dialogOpen = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load(resume: true);
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
      if (_online) _pollIncoming();
    }
  }

  Future<void> _load({bool resume = false}) async {
    try {
      final results = await Future.wait([
        Api.instance.get('/api/nanny/profile'),
        Api.instance.get('/api/orders?scope=active'),
      ]);
      final p = NannyProfile.fromJson(Map<String, dynamic>.from(results[0] as Map));
      final active = (results[1] as List).map((e) => Order.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (!mounted) return;
      setState(() {
        _p = p;
        _active = active;
        _error = null;
      });
      // Сервер помнит, что няня была на линии — восстанавливаем трансляцию после перезапуска.
      if (resume && p.online && !_online) {
        try {
          await LocationTracker.instance.start();
          _setOnline(true);
        } catch (_) {}
      }
    } catch (e) {
      if (mounted && _p == null) setState(() => _error = e);
    }
  }

  void _setOnline(bool v) {
    setState(() => _online = v);
    _incomingTimer?.cancel();
    if (v) {
      _pollIncoming();
      _incomingTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollIncoming());
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() => _switching = true);
    try {
      if (value) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.getBool('location_disclosure_ok') != true) {
          if (!mounted) return;
          final ok = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const LocationDisclosureScreen()));
          if (ok != true) return;
          await prefs.setBool('location_disclosure_ok', true);
        }
        final pos = await currentLocation();
        await Api.instance.post('/api/nanny/online', {'online': true, 'lat': pos.latitude, 'lng': pos.longitude});
        await LocationTracker.instance.start();
        _setOnline(true);
      } else {
        await Api.instance.post('/api/nanny/online', {'online': false});
        if (_active.where((o) => o.status != 'pending').isEmpty) await LocationTracker.instance.stop();
        _setOnline(false);
      }
    } on LocationUnavailable catch (e) {
      if (mounted) {
        showMessage(context, e.message);
      }
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _switching = false);
    }
  }

  Future<void> _pollIncoming() async {
    if (_dialogOpen || !mounted) return;
    try {
      final list = await Api.instance.get('/api/nanny/incoming') as List;
      final orders = list.map((e) => Order.fromJson(Map<String, dynamic>.from(e as Map))).where((o) => !_shown.contains(o.id)).toList();
      if (orders.isEmpty || !mounted) return;
      final o = orders.first;
      _shown.add(o.id);
      _dialogOpen = true;
      final accepted = await showDialog<Order>(
        context: context,
        barrierDismissible: false,
        builder: (_) => IncomingOrderDialog(order: o),
      );
      _dialogOpen = false;
      if (accepted != null && mounted) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderScreen(orderId: accepted.id)));
      }
      _load();
    } catch (_) {
      _dialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Работа')),
        body: _error == null ? const Center(child: CircularProgressIndicator()) : ErrorView(message: '$_error', onRetry: _load),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Работа')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            _onlineCard(),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _MiniStat(
                  icon: Icons.account_balance_wallet_rounded,
                  title: money(p.balance),
                  subtitle: 'Баланс',
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
                    _load();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  icon: Icons.star_rounded,
                  title: p.rating?.toStringAsFixed(1) ?? '—',
                  subtitle: '${p.reviewsCount} отзывов',
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, children: [
              if (p.medOk) const VerifiedChip('Медкнижка проверена'),
              if (p.policeOk) const VerifiedChip('МВД проверено'),
            ]),
            SectionTitle(_active.isEmpty ? 'Активных заказов нет' : 'Активные заказы'),
            if (_active.isEmpty)
              Text(
                _online ? 'Новые заявки появятся здесь — у вас будет 60 секунд, чтобы принять заказ.' : 'Выйдите на линию, чтобы родители рядом увидели вашу анкету.',
                style: const TextStyle(color: kMuted),
              ),
            for (final o in _active)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    leading: Avatar(name: o.parent.name, seed: o.parent.id ?? 0),
                    title: Text(o.address ?? 'Заказ №${o.id}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Align(alignment: Alignment.centerLeft, child: StatusChip(o.status))),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderScreen(orderId: o.id)));
                      _load();
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _onlineCard() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _online ? kPrimary : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _online ? kPrimary : kLine),
      ),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: _online ? kOk : kBg, shape: BoxShape.circle),
          child: Icon(_online ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded, color: _online ? Colors.white : kMuted),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_online ? 'На линии' : 'Офлайн',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _online ? Colors.white : kPrimary)),
            const SizedBox(height: 2),
            AnimatedBuilder(
              animation: LocationTracker.instance,
              builder: (_, _) => Text(
                _online
                    ? (LocationTracker.instance.pending > 1 ? 'Нет сети: ${LocationTracker.instance.pending} точек GPS ждут отправки' : 'Ждём заказы рядом с вами…')
                    : 'Родители вас не видят',
                style: TextStyle(color: _online ? Colors.white70 : kMuted),
              ),
            ),
          ]),
        ),
        _switching
            ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3))
            : Switch(value: _online, onChanged: _toggle, activeTrackColor: kOk),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.title, required this.subtitle, this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kWarm.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: kPrimary),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(subtitle, style: const TextStyle(color: kMuted)),
          ]),
        ),
      ),
    );
  }
}

/// Входящая заявка с таймером 60 секунд.
class IncomingOrderDialog extends StatefulWidget {
  const IncomingOrderDialog({super.key, required this.order});

  final Order order;

  @override
  State<IncomingOrderDialog> createState() => _IncomingOrderDialogState();
}

class _IncomingOrderDialogState extends State<IncomingOrderDialog> {
  Timer? _timer;
  bool _busy = false;

  int get _left {
    final now = widget.order.serverNow;
    return (((widget.order.expiresAt ?? now) - now) / 1000).ceil().clamp(0, 60);
  }

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_left <= 0) {
        t.cancel();
        if (mounted) Navigator.pop(context);
        return;
      }
      if (t.tick % 3 == 0) HapticFeedback.mediumImpact();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _act(bool accept) async {
    setState(() => _busy = true);
    try {
      if (accept) {
        final res = await Api.instance.post('/api/orders/${widget.order.id}/accept');
        if (mounted) Navigator.pop(context, Order.fromJson(Map<String, dynamic>.from(res as Map)));
      } else {
        await Api.instance.post('/api/orders/${widget.order.id}/decline');
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, e);
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(child: Text('Новый заказ!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
            Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 54,
                height: 54,
                child: CircularProgressIndicator(value: _left / 60, strokeWidth: 5, color: kPink, backgroundColor: kPink.withValues(alpha: 0.15)),
              ),
              Text('$_left', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            ]),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: kWarm.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('≈ ${money(o.expectedEarning)}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              Text('ваш заработок за 2 часа · ${money(o.price)}/ч до комиссии', style: const TextStyle(color: kMuted)),
            ]),
          ),
          const SizedBox(height: 12),
          _line(Icons.place_rounded, o.address ?? '—', o.distanceM == null ? null : '${km(o.distanceM)} от вас'),
          _line(Icons.child_care_rounded, 'Детей: ${o.childrenCount}', o.childrenAges),
          _line(Icons.schedule_rounded, o.type == 'scheduled' ? 'На ${dateTime(o.scheduledAt)}' : 'Прямо сейчас', null),
          if ((o.notes ?? '').isNotEmpty) _line(Icons.warning_amber_rounded, o.notes!, null),
          const SizedBox(height: 16),
          if (_busy)
            const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
          else
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => _act(false), child: const Text('Отклонить'))),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(style: FilledButton.styleFrom(backgroundColor: kOk), onPressed: () => _act(true), child: const Text('Принять')),
              ),
            ]),
        ]),
      ),
    );
  }

  Widget _line(IconData icon, String text, String? sub) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: kPrimary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (sub != null && sub.isNotEmpty) Text(sub, style: const TextStyle(color: kMuted, fontSize: 13)),
            ]),
          ),
        ]),
      );
}

/// Экран-объяснение перед запросом геолокации (требование Google Play / App Store).
class LocationDisclosureScreen extends StatelessWidget {
  const LocationDisclosureScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: kWarm.withValues(alpha: 0.25), shape: BoxShape.circle),
              child: const Icon(Icons.my_location_rounded, size: 40, color: kPrimary),
            ),
            const SizedBox(height: 24),
            Text('Доступ к геолокации', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            const Text(
              'Супер Няня собирает данные о вашем местоположении, пока вы «На линии» или выполняете заказ, '
              'даже когда приложение закрыто или не используется. Это нужно, чтобы:',
              style: TextStyle(fontSize: 15, height: 1.45),
            ),
            const SizedBox(height: 14),
            for (final t in const [
              'показывать вашу анкету родителям поблизости;',
              'родитель видел на карте, как вы едете к нему;',
              'подтвердить статус «На месте» (сверка с адресом, 100 м);',
              'передать координаты при нажатии тревожной кнопки SOS.',
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check_circle_rounded, color: kOk, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t, style: const TextStyle(fontSize: 15))),
                ]),
              ),
            const SizedBox(height: 8),
            const Text(
              'Пока вы на линии, в шторке уведомлений будет значок. Переключитесь в «Офлайн» — и передача прекратится.',
              style: TextStyle(color: kMuted, height: 1.4),
            ),
            const Spacer(),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Разрешить и продолжить')),
            const SizedBox(height: 8),
            Center(child: TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Не сейчас'))),
          ]),
        ),
      ),
    );
  }
}
