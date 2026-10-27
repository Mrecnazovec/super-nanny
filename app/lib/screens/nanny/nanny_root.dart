import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';
import '../common/chats_screen.dart';
import '../common/orders_screen.dart';
import '../common/profile_screen.dart';
import '../common/unread_badge.dart';
import 'onboarding_screen.dart';
import 'work_screen.dart';

/// Няня: пока анкета не одобрена модератором — онбординг / ожидание, после — рабочий интерфейс.
class NannyRoot extends ConsumerWidget {
  const NannyRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider).value!;
    return switch (user.nannyStatus) {
      'approved' => const NannyHome(),
      'pending' => const PendingScreen(),
      _ => const OnboardingScreen(),
    };
  }
}

class NannyHome extends StatefulWidget {
  const NannyHome({super.key});

  @override
  State<NannyHome> createState() => _NannyHomeState();
}

class _NannyHomeState extends State<NannyHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return UnreadPoller(
      builder: (unread) => Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            const WorkScreen(),
            OrdersScreen(visible: _tab == 1),
            ChatsScreen(visible: _tab == 2),
            const ProfileScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            const NavigationDestination(icon: Icon(Icons.power_settings_new_rounded), label: 'Работа'),
            const NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'Заказы'),
            NavigationDestination(
              icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.chat_bubble_outline_rounded)),
              selectedIcon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.chat_bubble_rounded)),
              label: 'Чаты',
            ),
            const NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Профиль'),
          ],
        ),
      ),
    );
  }
}

class PendingScreen extends ConsumerWidget {
  const PendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(actions: [
        TextButton(onPressed: () => ref.read(sessionProvider.notifier).logout(), child: const Text('Выйти')),
      ]),
      body: SafeArea(
        child: EmptyView(
          icon: Icons.hourglass_top_rounded,
          title: 'Анкета на проверке',
          subtitle: 'Модератор проверяет паспорт, селфи, медкнижку и справку о несудимости. '
              'Обычно это занимает до 24 часов. После одобрения вы сможете выйти на линию.',
          action: SizedBox(
            width: 240,
            child: BusyButton(
              label: 'Проверить статус',
              icon: Icons.refresh_rounded,
              onPressed: () async {
                final user = await ref.read(sessionProvider.notifier).reload();
                if (user.nannyStatus == 'pending' && context.mounted) showMessage(context, 'Анкета всё ещё на проверке');
              },
            ),
          ),
        ),
      ),
      bottomNavigationBar: const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: InfoPlate(
            icon: Icons.shield_outlined,
            color: kOk,
            child: Text('Жёсткая проверка — главное отличие Супер Няни: родители доверяют только верифицированным исполнителям.'),
          ),
        ),
      ),
    );
  }
}
