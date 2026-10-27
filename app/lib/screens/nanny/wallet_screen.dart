import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';
import '../common/cards_screen.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  Wallet? _w;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final w = Wallet.fromJson(Map<String, dynamic>.from(await Api.instance.get('/api/nanny/wallet') as Map));
      if (mounted) setState(() => _w = w);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _withdraw(Wallet w) async {
    final cards = ref.read(sessionProvider).value?.cards ?? const <PayCard>[];
    if (cards.isEmpty) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const CardsScreen()));
      return;
    }
    final amount = TextEditingController(text: '${w.balance}');
    var cardId = cards.first.id;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Вывод средств', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: 'Сумма, сум', helperText: 'Минимум ${money(w.minWithdraw)}, доступно ${money(w.balance)}'),
            ),
            const SizedBox(height: 8),
            RadioGroup<int>(
              groupValue: cardId,
              onChanged: (v) => set(() => cardId = v ?? cardId),
              child: Column(children: [
                for (final c in cards) RadioListTile<int>(value: c.id, title: Text(c.mask), subtitle: Text(c.typeLabel)),
              ]),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Вывести')),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    try {
      await Api.instance.post('/api/nanny/withdraw', {'amount': int.tryParse(amount.text) ?? 0, 'card_id': cardId});
      if (mounted) showMessage(context, 'Заявка на вывод создана. Деньги поступят после подтверждения.');
      _load();
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = _w;
    return Scaffold(
      appBar: AppBar(title: const Text('Кошелёк')),
      body: w == null
          ? (_error == null ? const Center(child: CircularProgressIndicator()) : ErrorView(message: '$_error', onRetry: _load))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [kPrimary, Color(0xFF457B9D)]),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Доступно к выводу', style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 4),
                      Text(money(w.balance), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 4),
                      Text('Заработано всего: ${money(w.totalEarned)}', style: const TextStyle(color: kWarm, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: kWarm, foregroundColor: kPrimary),
                        onPressed: w.balance >= w.minWithdraw ? () => _withdraw(w) : null,
                        icon: const Icon(Icons.arrow_outward_rounded),
                        label: const Text('Вывести на карту'),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  InfoPlate(
                    child: Text('Комиссия платформы ${w.commissionPercent}% удерживается автоматически при завершении заказа — '
                        'на баланс зачисляется ${100 - w.commissionPercent}% от суммы.'),
                  ),
                  if (w.withdrawals.isNotEmpty) ...[
                    const SectionTitle('Заявки на вывод'),
                    for (final x in w.withdrawals)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          x.status == 'paid' ? Icons.check_circle_rounded : x.status == 'rejected' ? Icons.cancel_rounded : Icons.hourglass_top_rounded,
                          color: x.status == 'paid' ? kOk : x.status == 'rejected' ? kPink : kWarm,
                        ),
                        title: Text(money(x.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${x.cardMask} · ${dateTime(x.createdAt)}'),
                        trailing: Text({'paid': 'Выплачено', 'rejected': 'Отклонено'}[x.status] ?? 'В обработке'),
                      ),
                  ],
                  const SectionTitle('История'),
                  if (w.transactions.isEmpty) const Text('Здесь появятся начисления за заказы', style: TextStyle(color: kMuted)),
                  for (final t in w.transactions)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: (t.amount >= 0 ? kOk : kPink).withValues(alpha: 0.12),
                        child: Icon(t.amount >= 0 ? Icons.south_west_rounded : Icons.north_east_rounded, color: t.amount >= 0 ? kOk : kPink),
                      ),
                      title: Text({'earning': 'Заказ №${t.orderId}', 'withdrawal': 'Вывод на карту', 'refund': 'Возврат заявки'}[t.kind] ?? t.kind),
                      subtitle: Text(dateTime(t.createdAt)),
                      trailing: Text(
                        '${t.amount >= 0 ? '+' : '−'}${money(t.amount.abs())}',
                        style: TextStyle(fontWeight: FontWeight.w800, color: t.amount >= 0 ? kOk : kPrimary),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
