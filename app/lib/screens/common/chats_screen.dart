import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models.dart';
import '../../widgets/common.dart';
import 'chat_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key, this.visible = true});

  final bool visible;

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  List<ChatItem>? _items;
  Object? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.visible) _start();
  }

  @override
  void didUpdateWidget(ChatsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) _start();
    if (!widget.visible) _timer?.cancel();
  }

  void _start() {
    _load();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _load());
  }

  Future<void> _load() async {
    try {
      final list = await Api.instance.get('/api/chats') as List;
      if (!mounted) return;
      setState(() {
        _items = list.map((e) => ChatItem.fromJson(Map<String, dynamic>.from(e as Map))).toList();
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
    final items = _items;
    Widget body;
    if (items == null) {
      body = _error == null ? const Center(child: CircularProgressIndicator()) : ErrorView(message: '$_error', onRetry: _load);
    } else if (items.isEmpty) {
      body = const EmptyView(
        icon: Icons.forum_rounded,
        title: 'Чатов пока нет',
        subtitle: 'Чат с няней откроется автоматически, как только она примет заказ.',
      );
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(indent: 84),
          itemBuilder: (_, i) {
            final c = items[i];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Avatar(photoId: c.photoId, name: c.title, seed: c.orderId, size: 52),
              title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                c.lastText == null ? 'Заказ №${c.orderId} · ${orderStatusLabels[c.status] ?? ''}' : '${c.lastMine ? 'Вы: ' : ''}${c.lastText}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.unread > 0 ? kPrimary : kMuted, fontWeight: c.unread > 0 ? FontWeight.w600 : FontWeight.normal),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(shortDate(c.updatedAt), style: const TextStyle(color: kMuted, fontSize: 12)),
                  const SizedBox(height: 4),
                  if (c.unread > 0) Badge(label: Text('${c.unread}'), backgroundColor: kPink),
                ],
              ),
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(orderId: c.orderId, title: c.title)));
                _load();
              },
            );
          },
        ),
      );
    }
    return Scaffold(appBar: AppBar(title: const Text('Чаты')), body: body);
  }
}
