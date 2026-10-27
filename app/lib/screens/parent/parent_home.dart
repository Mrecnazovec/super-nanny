import 'package:flutter/material.dart';

import '../common/chats_screen.dart';
import '../common/orders_screen.dart';
import '../common/profile_screen.dart';
import '../common/unread_badge.dart';
import 'feed_screen.dart';

class ParentHome extends StatefulWidget {
  const ParentHome({super.key});

  @override
  State<ParentHome> createState() => _ParentHomeState();
}

class _ParentHomeState extends State<ParentHome> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return UnreadPoller(
      builder: (unread) => Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            const FeedScreen(),
            OrdersScreen(visible: _tab == 1),
            ChatsScreen(visible: _tab == 2),
            const ProfileScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            const NavigationDestination(icon: Icon(Icons.style_outlined), selectedIcon: Icon(Icons.style_rounded), label: 'Лента'),
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
