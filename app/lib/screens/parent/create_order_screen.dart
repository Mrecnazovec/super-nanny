import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';
import '../../widgets/order_map.dart';
import '../common/cards_screen.dart';
import '../common/order_screen.dart';

class CreateOrderScreen extends ConsumerStatefulWidget {
  const CreateOrderScreen({super.key, required this.nanny, required this.point});

  final NannyCard nanny;
  final LatLng point;

  @override
  ConsumerState<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends ConsumerState<CreateOrderScreen> {
  final _ages = TextEditingController();
  final _notes = TextEditingController();
  final _address = TextEditingController();
  late LatLng _point = widget.point;
  bool _scheduled = false;
  DateTime? _when;
  int _children = 1;
  bool _corporate = false;
  int? _cardId;

  @override
  void dispose() {
    _ages.dispose();
    _notes.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _pickWhen() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      initialDate: _when ?? now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_when ?? now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    setState(() => _when = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    final user = ref.read(sessionProvider).value!;
    if (_address.text.trim().isEmpty) throw ApiException(400, 'Укажите адрес');
    if (_scheduled && _when == null) throw ApiException(400, 'Выберите дату и время');
    if (!_corporate && user.cards.isEmpty) throw ApiException(400, 'Привяжите карту Uzcard или Humo для оплаты');
    final res = await Api.instance.post('/api/orders', {
      'nanny_id': widget.nanny.id,
      'type': _scheduled ? 'scheduled' : 'now',
      if (_scheduled) 'scheduled_at': _when!.millisecondsSinceEpoch,
      'children_count': _children,
      'children_ages': _ages.text.trim(),
      'notes': _notes.text.trim(),
      'address': _address.text.trim(),
      'lat': _point.latitude,
      'lng': _point.longitude,
      'corporate': _corporate,
      if (!_corporate) 'card_id': _cardId ?? user.cards.first.id,
    });
    final order = Order.fromJson(Map<String, dynamic>.from(res as Map));
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => OrderScreen(orderId: order.id)));
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).value;
    final n = widget.nanny;
    final cards = user?.cards ?? const <PayCard>[];
    final hold = n.price * 2;
    return Scaffold(
      appBar: AppBar(title: const Text('Оформление заказа')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              leading: Avatar(photoId: n.photoId, name: n.name, seed: n.id, size: 52),
              title: Text(n.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text('${money(n.price)} / час · опыт ${years(n.experience ?? 0)}'),
            ),
          ),
          const SectionTitle('Когда'),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('На сейчас'), icon: Icon(Icons.bolt_rounded)),
              ButtonSegment(value: true, label: Text('На время'), icon: Icon(Icons.event_rounded)),
            ],
            selected: {_scheduled},
            onSelectionChanged: (s) => setState(() => _scheduled = s.first),
          ),
          if (_scheduled) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickWhen,
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text(_when == null ? 'Выбрать дату и время' : DateFormat('d MMMM, HH:mm', 'ru').format(_when!)),
            ),
          ],
          const SectionTitle('Дети'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(children: [
                const Expanded(child: Text('Количество детей', style: TextStyle(fontWeight: FontWeight.w600))),
                IconButton.filledTonal(
                  onPressed: _children > 1 ? () => setState(() => _children--) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                SizedBox(width: 36, child: Text('$_children', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                IconButton.filledTonal(
                  onPressed: _children < 6 ? () => setState(() => _children++) : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          TextField(controller: _ages, decoration: const InputDecoration(labelText: 'Возраст детей', hintText: 'Например: 3 года и 6 лет')),
          const SizedBox(height: 10),
          TextField(
            controller: _notes,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(labelText: 'Особые отметки', hintText: 'Аллергии, режим сна, что нельзя…'),
          ),
          const SectionTitle('Адрес'),
          TextField(
            controller: _address,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.home_outlined), hintText: 'Улица, дом, квартира, ориентир'),
          ),
          const SizedBox(height: 10),
          SizedBox(height: 190, child: PickPointMap(point: _point, onChanged: (p) => setState(() => _point = p))),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Нажмите на карту, чтобы уточнить точку', style: TextStyle(color: kMuted, fontSize: 12)),
          ),
          const SectionTitle('Оплата'),
          if (user?.company != null)
            Card(
              child: CheckboxListTile(
                value: _corporate,
                onChanged: (v) => setState(() => _corporate = v ?? false),
                title: const Text('Оплатить с корпоративного счёта', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(user!.company!.name),
                secondary: const Icon(Icons.business_rounded, color: kPrimary),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: Text(
                'Корпоративная оплата доступна сотрудникам компаний-партнёров: введите код компании в профиле.',
                style: TextStyle(color: kMuted, fontSize: 12),
              ),
            ),
          if (!_corporate) ...[
            const SizedBox(height: 8),
            if (cards.isEmpty)
              OutlinedButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CardsScreen())),
                icon: const Icon(Icons.add_card_rounded),
                label: const Text('Привязать карту Uzcard / Humo'),
              )
            else
              Card(
                child: RadioGroup<int>(
                  groupValue: _cardId ?? cards.first.id,
                  onChanged: (v) => setState(() => _cardId = v),
                  child: Column(children: [
                    for (final c in cards)
                      RadioListTile<int>(
                        value: c.id,
                        title: Text(c.mask, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${c.typeLabel} · до ${c.expiry}'),
                      ),
                  ]),
                ),
              ),
          ],
          const SizedBox(height: 16),
          InfoPlate(
            icon: Icons.lock_clock_rounded,
            child: Text(
              'При принятии заказа на ${_corporate ? 'счёте компании' : 'карте'} будет заблокировано ${money(hold)} (2 часа). '
              'По завершении спишется сумма по факту — поминутно, минимум 1 час. Остаток разблокируется.',
            ),
          ),
          const SizedBox(height: 20),
          BusyButton(label: 'Отправить заявку няне', icon: Icons.send_rounded, onPressed: _submit),
        ],
      ),
    );
  }
}
