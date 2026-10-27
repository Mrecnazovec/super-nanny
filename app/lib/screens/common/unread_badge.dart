import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';

/// Раз в 15 секунд считает непрочитанные сообщения во всех чатах.
class UnreadPoller extends StatefulWidget {
  const UnreadPoller({super.key, required this.builder});

  final Widget Function(int unread) builder;

  @override
  State<UnreadPoller> createState() => _UnreadPollerState();
}

class _UnreadPollerState extends State<UnreadPoller> {
  Timer? _timer;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      final list = await Api.instance.get('/api/chats') as List;
      final total = list.fold<int>(0, (sum, c) => sum + (((c as Map)['unread'] as num?)?.toInt() ?? 0));
      if (mounted && total != _unread) setState(() => _unread = total);
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_unread);
}
