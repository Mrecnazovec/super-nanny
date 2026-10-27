import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';

/// Привязка карт Uzcard / Humo. Сервер хранит только маску и токен.
class CardsScreen extends ConsumerStatefulWidget {
  const CardsScreen({super.key});

  @override
  ConsumerState<CardsScreen> createState() => _CardsScreenState();
}

class _CardsScreenState extends ConsumerState<CardsScreen> {
  final _number = TextEditingController();
  final _expiry = TextEditingController();

  @override
  void initState() {
    super.initState();
    _number.addListener(() => setState(() {}));
    _expiry.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _number.dispose();
    _expiry.dispose();
    super.dispose();
  }

  String get _digits => _number.text.replaceAll(' ', '');

  String? get _type {
    if (RegExp(r'^(8600|5614)').hasMatch(_digits)) return 'UZCARD';
    if (_digits.startsWith('9860')) return 'HUMO';
    return null;
  }

  Future<void> _add() async {
    await Api.instance.post('/api/cards', {'number': _digits, 'expiry': _expiry.text});
    _number.clear();
    _expiry.clear();
    await ref.read(sessionProvider.notifier).reload();
    if (mounted) {
      FocusScope.of(context).unfocus();
      showMessage(context, 'Карта привязана');
    }
  }

  Future<void> _remove(int id) async {
    try {
      await Api.instance.delete('/api/cards/$id');
      await ref.read(sessionProvider.notifier).reload();
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cards = ref.watch(sessionProvider).value?.cards ?? const [];
    final ready = _digits.length == 16 && _expiry.text.length == 5;
    return Scaffold(
      appBar: AppBar(title: const Text('Мои карты')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          for (final c in cards)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: c.type == 'humo' ? const [Color(0xFF0B6E4F), Color(0xFF2A9D8F)] : const [kPrimary, Color(0xFF457B9D)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(c.typeLabel, style: const TextStyle(color: kWarm, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
                      const SizedBox(height: 14),
                      Text(c.mask, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1)),
                      const SizedBox(height: 4),
                      Text('до ${c.expiry}', style: const TextStyle(color: Colors.white70)),
                    ]),
                  ),
                  IconButton(onPressed: () => _remove(c.id), icon: const Icon(Icons.delete_outline_rounded, color: Colors.white70)),
                ]),
              ),
            ),
          const SectionTitle('Новая карта'),
          TextField(
            controller: _number,
            keyboardType: TextInputType.number,
            inputFormatters: [GroupedDigitsFormatter(const [4, 4, 4, 4], ' ')],
            decoration: InputDecoration(
              labelText: 'Номер карты',
              hintText: '8600 0000 0000 0000',
              prefixIcon: const Icon(Icons.credit_card_rounded),
              suffixText: _type,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _expiry,
            keyboardType: TextInputType.number,
            inputFormatters: [GroupedDigitsFormatter(const [2, 2], '/')],
            decoration: const InputDecoration(labelText: 'Срок действия', hintText: 'ММ/ГГ', prefixIcon: Icon(Icons.event_rounded)),
          ),
          const SizedBox(height: 16),
          BusyButton(label: 'Привязать карту', onPressed: ready ? _add : null),
          const SizedBox(height: 16),
          const InfoPlate(
            icon: Icons.verified_user_outlined,
            child: Text(
              'Принимаются карты Uzcard и Humo. Номер карты не хранится в приложении: '
              'платёжный шлюз (Payme / Click) выдаёт токен, а мы видим только маску карты.',
            ),
          ),
        ],
      ),
    );
  }
}
