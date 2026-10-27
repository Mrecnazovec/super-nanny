import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';
import '../nanny/onboarding_screen.dart';
import '../nanny/wallet_screen.dart';
import 'cards_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).value;
    if (user == null) return const SizedBox();
    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Avatar(name: user.name, seed: user.id, size: 64),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(user.name ?? '', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(formatPhone(user.phone), style: const TextStyle(color: kMuted)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: kWarm.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(20)),
                      child: Text(user.isParent ? 'Родитель' : 'Няня', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
          if (user.isParent) ...[
            const SectionTitle('Корпоративный аккаунт (B2B)'),
            _CompanyCard(user: user),
          ],
          const SectionTitle('Настройки'),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              if (user.isNanny) ...[
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_rounded, color: kPrimary),
                  title: const Text('Кошелёк'),
                  subtitle: const Text('Баланс, история и вывод средств'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
                ),
                const Divider(indent: 56),
                ListTile(
                  leading: const Icon(Icons.badge_rounded, color: kPrimary),
                  title: const Text('Моя анкета'),
                  subtitle: const Text('Описание, стоимость, расписание, сертификаты'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OnboardingScreen(editMode: true))),
                ),
                const Divider(indent: 56),
              ],
              ListTile(
                leading: const Icon(Icons.credit_card_rounded, color: kPrimary),
                title: const Text('Мои карты'),
                subtitle: Text(user.cards.isEmpty ? 'Uzcard / Humo не привязаны' : user.cards.map((c) => '•${c.mask.substring(c.mask.length - 4)}').join('  ')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CardsScreen())),
              ),
              const Divider(indent: 56),
              ListTile(
                leading: const Icon(Icons.support_agent_rounded, color: kPrimary),
                title: const Text('Безопасность'),
                subtitle: const Text('Во время заказа удерживайте SOS 3 секунды — администратор получит тревогу с координатами'),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Выйти из аккаунта?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти')),
                  ],
                ),
              );
              if (ok == true) await ref.read(sessionProvider.notifier).logout();
            },
            icon: const Icon(Icons.logout_rounded, color: kPink),
            label: const Text('Выйти', style: TextStyle(color: kPink)),
          ),
          const SizedBox(height: 16),
          Center(child: Text('Супер Няня v$kAppVersion', style: const TextStyle(color: kMuted, fontSize: 12))),
        ],
      ),
    );
  }
}

class _CompanyCard extends ConsumerStatefulWidget {
  const _CompanyCard({required this.user});

  final AppUser user;

  @override
  ConsumerState<_CompanyCard> createState() => _CompanyCardState();
}

class _CompanyCardState extends ConsumerState<_CompanyCard> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final company = widget.user.company;
    if (company != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.business_rounded, color: kPrimary),
          title: Text(company.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: const Text('Заказы можно оплачивать с корпоративного счёта'),
          trailing: TextButton(
            onPressed: () async {
              final res = await Api.instance.delete('/api/me/company');
              ref.read(sessionProvider.notifier).setUser(Map<String, dynamic>.from(res as Map));
            },
            child: const Text('Отвязать'),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Ваш работодатель оплачивает услуги няни? Введите корпоративный код — и оплачивайте заказы с корпоративного счёта.',
              style: TextStyle(color: kMuted)),
          const SizedBox(height: 10),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'Код компании', prefixIcon: Icon(Icons.vpn_key_outlined)),
          ),
          const SizedBox(height: 10),
          BusyButton(
            label: 'Привязать',
            onPressed: () async {
              final res = await Api.instance.post('/api/me/company', {'code': _code.text.trim()});
              ref.read(sessionProvider.notifier).setUser(Map<String, dynamic>.from(res as Map));
            },
          ),
        ]),
      ),
    );
  }
}
