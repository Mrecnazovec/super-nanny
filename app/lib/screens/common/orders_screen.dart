import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';
import 'order_screen.dart';

/// Список заказов (родитель — свои заказы, няня — принятые). Обновляется, пока вкладка видна.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key, this.visible = true});

  final bool visible;

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  List<Order>? _orders;
  Object? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.visible) _start();
  }

  @override
  void didUpdateWidget(OrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) _start();
    if (!widget.visible) _timer?.cancel();
  }

  void _start() {
    _load();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _load());
  }

  Future<void> _load() async {
    try {
      final list = await Api.instance.get('/api/orders') as List;
      if (!mounted) return;
      setState(() {
        _orders = list.map((e) => Order.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isParent = ref.watch(sessionProvider).value?.isParent ?? true;
    final orders = _orders;
    Widget body;
    if (orders == null) {
      body = _error == null ? const Center(child: CircularProgressIndicator()) : ErrorView(message: '$_error', onRetry: _load);
    } else if (orders.isEmpty) {
      body = EmptyView(
        icon: Icons.receipt_long_rounded,
        title: 'Заказов пока нет',
        subtitle: isParent ? 'Выберите няню в ленте — свайп вправо.' : 'Выйдите на линию, чтобы получать заказы.',
      );
    } else {
      final active = orders.where((o) => o.isActive).toList();
      final history = orders.where((o) => !o.isActive).toList();
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            if (active.isNotEmpty) const SectionTitle('Активные'),
            for (final o in active) _OrderTile(order: o, isParent: isParent, onReturn: _load),
            if (history.isNotEmpty) const SectionTitle('История'),
            for (final o in history) _OrderTile(order: o, isParent: isParent, onReturn: _load),
          ],
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('Заказы')), body: body);
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.isParent, required this.onReturn});

  final Order order;
  final bool isParent;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final who = isParent ? o.nanny : o.parent;
    final amount = o.total ?? o.holdAmount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderScreen(orderId: o.id)));
            onReturn();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Avatar(photoId: isParent ? o.nanny.photoId : null, name: who.name, seed: who.id ?? 0, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(who.name ?? '—', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    o.type == 'scheduled' ? 'На ${dateTime(o.scheduledAt)}' : 'Создан ${dateTime(o.createdAt)}',
                    style: const TextStyle(color: kMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  StatusChip(o.status),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(money(isParent ? amount : (o.nannyEarning ?? o.expectedEarning)), style: const TextStyle(fontWeight: FontWeight.w700)),
                if (o.unread > 0) ...[
                  const SizedBox(height: 6),
                  Badge(label: Text('${o.unread}'), child: const Icon(Icons.chat_bubble_outline_rounded, size: 20)),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
