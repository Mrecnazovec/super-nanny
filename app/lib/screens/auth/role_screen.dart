import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';

class RoleScreen extends ConsumerStatefulWidget {
  const RoleScreen({super.key});

  @override
  ConsumerState<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends ConsumerState<RoleScreen> {
  final _name = TextEditingController();
  String? _role;

  @override
  void initState() {
    super.initState();
    final user = ref.read(sessionProvider).value;
    _name.text = user?.name ?? '';
    _role = user?.role;
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final res = await Api.instance.patch('/api/me', {'name': _name.text.trim(), 'role': _role});
    ref.read(sessionProvider.notifier).setUser(Map<String, dynamic>.from(res as Map));
  }

  @override
  Widget build(BuildContext context) {
    final locked = ref.watch(sessionProvider).value?.role != null;
    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton(onPressed: () => ref.read(sessionProvider.notifier).logout(), child: const Text('Выйти')),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text('Давайте познакомимся', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Как к вам обращаться и кем вы будете в сервисе?', style: TextStyle(color: kMuted, fontSize: 15)),
            const SizedBox(height: 24),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Ваше имя', prefixIcon: Icon(Icons.person_outline_rounded)),
            ),
            const SizedBox(height: 20),
            _RoleCard(
              icon: Icons.family_restroom_rounded,
              title: 'Я родитель',
              subtitle: 'Ищу проверенную няню для своих детей',
              selected: _role == 'parent',
              onTap: locked ? null : () => setState(() => _role = 'parent'),
            ),
            const SizedBox(height: 12),
            _RoleCard(
              icon: Icons.child_care_rounded,
              title: 'Я няня',
              subtitle: 'Хочу получать заказы. Потребуется проверка документов',
              selected: _role == 'nanny',
              onTap: locked ? null : () => setState(() => _role = 'nanny'),
            ),
            const SizedBox(height: 28),
            BusyButton(label: 'Продолжить', onPressed: _name.text.trim().length >= 2 && _role != null ? _save : null),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.icon, required this.title, required this.subtitle, required this.selected, this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? kWarm.withValues(alpha: 0.22) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: selected ? kWarm : kLine, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: selected ? kPrimary : kBg, borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: selected ? Colors.white : kPrimary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: kMuted)),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.check_circle_rounded, color: kPrimary),
            ],
          ),
        ),
      ),
    );
  }
}
