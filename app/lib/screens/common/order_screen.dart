import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/location.dart';
import '../../core/theme.dart';
import '../../models.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';
import '../../widgets/order_map.dart';
import '../../widgets/sos_button.dart';
import 'chat_screen.dart';

const _steps = ['accepted', 'on_the_way', 'arrived', 'in_progress', 'completed'];
const _stepLabels = ['Принят', 'В пути', 'На месте', 'Работа', 'Готово'];
const _nextAction = {
  'accepted': ('on_the_way', 'Выехала', Icons.directions_walk_rounded),
  'on_the_way': ('arrived', 'Я на месте', Icons.place_rounded),
  'arrived': ('in_progress', 'Начать работу', Icons.play_arrow_rounded),
  'in_progress': ('completed', 'Завершить работу', Icons.check_rounded),
};

/// Экран заказа: трекинг и SOS для родителя, смена статусов для няни.
class OrderScreen extends ConsumerStatefulWidget {
  const OrderScreen({super.key, required this.orderId});

  final int orderId;

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  Order? _o;
  Object? _error;
  Timer? _poll;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_o == null || _o!.isActive) _load();
    });
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final s = _o?.status;
      if (mounted && (s == 'pending' || s == 'in_progress')) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await Api.instance.get('/api/orders/${widget.orderId}');
      final o = Order.fromJson(Map<String, dynamic>.from(res as Map));
      if (!mounted) return;
      if (_o != null && _o!.status != o.status) HapticFeedback.mediumImpact();
      setState(() {
        _o = o;
        _error = null;
      });
    } catch (e) {
      if (mounted && _o == null) setState(() => _error = e);
    }
  }

  void _apply(dynamic res) {
    if (mounted) setState(() => _o = Order.fromJson(Map<String, dynamic>.from(res as Map)));
  }

  Future<void> _advance(Order o) async {
    final (next, label, _) = _nextAction[o.status]!;
    if (next == 'completed') {
      final ok = await _confirm('Завершить работу?', 'Итоговая сумма будет рассчитана по фактическому времени.');
      if (!ok) return;
    }
    final body = <String, dynamic>{'status': next};
    if (next == 'arrived' || next == 'on_the_way') {
      final p = await currentLocation();
      body['lat'] = p.latitude;
      body['lng'] = p.longitude;
    }
    _apply(await Api.instance.post('/api/orders/${o.id}/status', body));
    if (mounted) showMessage(context, '«$label» — статус обновлён');
  }

  Future<void> _cancel(Order o) async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отменить заказ?'),
        content: TextField(controller: reason, decoration: const InputDecoration(hintText: 'Причина (необязательно)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kPink, minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Отменить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _apply(await Api.instance.post('/api/orders/${o.id}/cancel', {'reason': reason.text.trim()}));
  }

  Future<bool> _confirm(String title, String text) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => Navigator.pop(ctx, true), child: const Text('Да')),
        ],
      ),
    );
    return ok == true;
  }

  void _openChat(Order o, bool isParent) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(orderId: o.id, title: (isParent ? o.nanny.name : o.parent.name) ?? 'Чат')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).value;
    final isParent = user?.isParent ?? true;
    final o = _o;
    if (o == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Заказ №${widget.orderId}')),
        body: _error == null ? const Center(child: CircularProgressIndicator()) : ErrorView(message: '$_error', onRetry: _load),
      );
    }
    final showMap = const {'accepted', 'on_the_way', 'arrived', 'in_progress'}.contains(o.status);
    final nannyPos = isParent ? o.nannyLocation : (LocationTracker.instance.last ?? o.nannyLocation);

    return Scaffold(
      appBar: AppBar(
        title: Text('Заказ №${o.id}'),
        actions: [
          if (o.chatOpen)
            IconButton(
              onPressed: () => _openChat(o, isParent),
              icon: Badge(isLabelVisible: o.unread > 0, label: Text('${o.unread}'), child: const Icon(Icons.chat_bubble_outline_rounded)),
            ),
        ],
      ),
      floatingActionButton: showMap ? SosButton(orderId: o.id) : null,
      body: Column(
        children: [
          if (showMap)
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.36,
              child: OrderMap(
                destination: o.destination,
                nanny: nannyPos,
                track: o.track,
                nannyPhotoId: o.nanny.photoId,
                nannyName: o.nanny.name,
                nannySeed: o.nanny.id ?? 0,
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
                children: [
                  _header(o, isParent),
                  if (_steps.contains(o.status)) ...[const SizedBox(height: 16), _Stepper(status: o.status)],
                  const SizedBox(height: 16),
                  ..._actions(o, isParent),
                  _counterpart(o, isParent),
                  const SizedBox(height: 12),
                  _details(o, isParent),
                  if (o.status == 'completed') ...[const SizedBox(height: 12), _summary(o, isParent)],
                  if (o.status == 'completed' && isParent) ...[const SizedBox(height: 12), _ReviewBox(order: o, onDone: _apply)],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(Order o, bool isParent) {
    String? subtitle;
    final now = o.serverNow;
    switch (o.status) {
      case 'pending':
        final left = ((o.expiresAt ?? now) - now) ~/ 1000;
        subtitle = left > 0 ? 'Няня ответит в течение $left сек' : 'Ожидаем ответ…';
      case 'accepted':
        subtitle = o.type == 'scheduled'
            ? 'Ждём ${dateTime(o.scheduledAt)}'
            : (isParent ? 'Няня скоро выедет' : 'Нажмите «Выехала», когда отправитесь');
      case 'on_the_way':
        subtitle = o.distanceM == null ? 'Определяем местоположение' : '${isParent ? 'Няня' : 'Вы'} в ${km(o.distanceM)} от адреса';
      case 'arrived':
        subtitle = isParent ? 'Няня на месте и скоро начнёт работу' : 'Нажмите «Начать работу», когда будете готовы';
      case 'in_progress':
        final elapsed = Duration(milliseconds: (now - (o.startedAt ?? now)).clamp(0, 1 << 40));
        subtitle = 'Идёт ${duration(elapsed)}';
      case 'cancelled':
        subtitle = '${o.cancelledBy == 'nanny' ? 'Отменён няней' : o.cancelledBy == 'parent' ? 'Отменён родителем' : 'Отменён'}'
            '${(o.cancelReason ?? '').isNotEmpty ? ': ${o.cancelReason}' : ''}';
      case 'declined':
        subtitle = 'Няня не может принять заказ. Выберите другую в ленте.';
      case 'expired':
        subtitle = 'Няня не ответила за 60 секунд. Выберите другую в ленте.';
      case 'completed':
        subtitle = 'Спасибо, что пользуетесь Супер Няней!';
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(orderStatusLabels[o.status] ?? o.status, style: Theme.of(context).textTheme.headlineSmall),
      if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle, style: const TextStyle(color: kMuted, fontSize: 15))],
      if (o.status == 'pending') ...[
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: (((o.expiresAt ?? now) - now) / 60000).clamp(0.0, 1.0),
            color: kWarm,
            backgroundColor: kWarm.withValues(alpha: 0.2),
          ),
        ),
      ],
      if (o.status == 'in_progress') ...[
        const SizedBox(height: 12),
        _Timer(order: o, isParent: isParent),
      ],
    ]);
  }

  List<Widget> _actions(Order o, bool isParent) {
    final out = <Widget>[];
    if (!isParent && _nextAction.containsKey(o.status)) {
      final (next, label, icon) = _nextAction[o.status]!;
      out.add(BusyButton(
        label: label,
        icon: icon,
        color: next == 'completed' ? kOk : null,
        onPressed: () => _advance(o),
      ));
      if (next == 'arrived') {
        out.add(const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Статус можно поставить в радиусе 100 м от адреса', style: TextStyle(color: kMuted, fontSize: 12)),
        ));
      }
      out.add(const SizedBox(height: 10));
    }
    if (o.canCancel) {
      out.add(BusyButton(label: 'Отменить заказ', outlined: true, onPressed: () => _cancel(o)));
      out.add(const SizedBox(height: 16));
    }
    if (isParent && const {'declined', 'expired', 'cancelled'}.contains(o.status)) {
      out.add(FilledButton.icon(
        onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
        icon: const Icon(Icons.style_rounded),
        label: const Text('Вернуться к ленте нянь'),
      ));
      out.add(const SizedBox(height: 16));
    }
    return out;
  }

  Widget _counterpart(Order o, bool isParent) {
    final p = isParent ? o.nanny : o.parent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Avatar(photoId: isParent ? o.nanny.photoId : null, name: p.name, seed: p.id ?? 0, size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(isParent ? 'Няня' : 'Родитель', style: const TextStyle(color: kMuted, fontSize: 12)),
              Text(p.name ?? '—', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              if (isParent && p.rating != null)
                Row(children: [RatingStars(rating: p.rating!, size: 14), const SizedBox(width: 4), Text(p.rating!.toStringAsFixed(1))]),
              if (p.phone != null) SelectableText(formatPhone(p.phone!), style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
          ),
          if (o.chatOpen)
            IconButton.filledTonal(onPressed: () => _openChat(o, isParent), icon: const Icon(Icons.chat_rounded)),
        ]),
      ),
    );
  }

  Widget _details(Order o, bool isParent) {
    Widget row(IconData icon, String title, String? value) => (value == null || value.isEmpty)
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, size: 20, color: kMuted),
              const SizedBox(width: 10),
              SizedBox(width: 110, child: Text(title, style: const TextStyle(color: kMuted))),
              Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
          );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          row(Icons.schedule_rounded, 'Когда', o.type == 'scheduled' ? dateTime(o.scheduledAt) : 'Сейчас'),
          row(Icons.place_outlined, 'Адрес', o.address),
          row(Icons.child_care_rounded, 'Дети', '${o.childrenCount}${(o.childrenAges ?? '').isNotEmpty ? ' · ${o.childrenAges}' : ''}'),
          row(Icons.warning_amber_rounded, 'Отметки', o.notes),
          row(Icons.payments_outlined, 'Тариф', '${money(o.price)} / час'),
          row(Icons.account_balance_wallet_outlined, 'Оплата', o.corporate ? 'Корпоративный счёт' : 'Карта'),
          if (o.status != 'completed')
            row(Icons.lock_clock_outlined, isParent ? 'Холд' : 'Ожидаемо', isParent ? money(o.holdAmount) : '≈ ${money(o.expectedEarning)} за 2 ч'),
        ]),
      ),
    );
  }

  Widget _summary(Order o, bool isParent) {
    return Card(
      color: kOk.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Итог', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          _kv('Время работы', '${o.minutes ?? 0} мин'),
          _kv(isParent ? 'Списано' : 'Сумма заказа', money(o.total)),
          if (!isParent) _kv('Комиссия платформы (12%)', '− ${money(o.commission)}'),
          if (!isParent) _kv('Зачислено на баланс', money(o.nannyEarning), bold: true),
        ]),
      ),
    );
  }

  Widget _kv(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(k, style: const TextStyle(color: kMuted))),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ]),
      );
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final current = _steps.indexOf(status);
    return Row(
      children: List.generate(_steps.length, (i) {
        final done = i <= current;
        return Expanded(
          child: Column(children: [
            Row(children: [
              Expanded(child: Container(height: 3, color: i == 0 ? Colors.transparent : (done ? kPrimary : kLine))),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: done ? kPrimary : Colors.white, shape: BoxShape.circle, border: Border.all(color: done ? kPrimary : kLine, width: 2)),
                child: done ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
              ),
              Expanded(child: Container(height: 3, color: i == _steps.length - 1 ? Colors.transparent : (i < current ? kPrimary : kLine))),
            ]),
            const SizedBox(height: 6),
            Text(_stepLabels[i], style: TextStyle(fontSize: 11, fontWeight: i == current ? FontWeight.w800 : FontWeight.w500, color: done ? kPrimary : kMuted)),
          ]),
        );
      }),
    );
  }
}

class _Timer extends StatelessWidget {
  const _Timer({required this.order, required this.isParent});

  final Order order;
  final bool isParent;

  @override
  Widget build(BuildContext context) {
    final now = order.serverNow;
    final elapsed = Duration(milliseconds: (now - (order.startedAt ?? now)).clamp(0, 1 << 40));
    final billable = elapsed.inMinutes < 60 ? 60 : elapsed.inMinutes + 1;
    final cost = ((order.price * billable / 60) / 100).round() * 100;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        const Icon(Icons.timer_outlined, color: Colors.white, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(duration(elapsed), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()])),
            Text('Время работы', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(money(isParent ? cost : (cost * 0.88).round()), style: const TextStyle(color: kWarm, fontSize: 16, fontWeight: FontWeight.w800)),
          Text(isParent ? 'к оплате сейчас' : 'ваш заработок', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
        ]),
      ]),
    );
  }
}

class _ReviewBox extends StatefulWidget {
  const _ReviewBox({required this.order, required this.onDone});

  final Order order;
  final void Function(dynamic) onDone;

  @override
  State<_ReviewBox> createState() => _ReviewBoxState();
}

class _ReviewBoxState extends State<_ReviewBox> {
  int _rating = 5;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.order.review;
    if (r != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ваш отзыв', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            RatingStars(rating: r.rating.toDouble(), size: 22),
            if ((r.text ?? '').isNotEmpty) ...[const SizedBox(height: 6), Text(r.text!)],
          ]),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Оцените няню', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          Row(
            children: List.generate(5, (i) => IconButton(
                  onPressed: () => setState(() => _rating = i + 1),
                  icon: Icon(i < _rating ? Icons.star_rounded : Icons.star_outline_rounded, color: kWarm, size: 36),
                )),
          ),
          TextField(controller: _text, maxLines: 3, minLines: 2, decoration: const InputDecoration(hintText: 'Расскажите, как всё прошло')),
          const SizedBox(height: 12),
          BusyButton(
            label: 'Отправить отзыв',
            onPressed: () async {
              final res = await Api.instance.post('/api/orders/${widget.order.id}/review', {'rating': _rating, 'text': _text.text.trim()});
              widget.onDone(res);
            },
          ),
        ]),
      ),
    );
  }
}
