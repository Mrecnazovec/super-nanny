import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../models.dart';
import '../../widgets/common.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.orderId, required this.title});

  final int orderId;
  final String title;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messages = <ChatMessage>[];
  final _input = TextEditingController();
  Timer? _timer;
  bool _loaded = false;
  bool _sending = false;

  int get _lastId => _messages.isEmpty ? 0 : _messages.last.id;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final list = await Api.instance.get('/api/orders/${widget.orderId}/messages?after=$_lastId') as List;
      if (!mounted) return;
      final fresh = list.map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e as Map)));
      setState(() {
        for (final m in fresh) {
          if (m.id > _lastId) _messages.add(m);
        }
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await Api.instance.post('/api/orders/${widget.orderId}/messages', {'text': text});
      _input.clear();
      final m = ChatMessage.fromJson(Map<String, dynamic>.from(res as Map));
      setState(() {
        if (m.id > _lastId) _messages.add(m);
      });
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title),
          Text('Заказ №${widget.orderId}', style: const TextStyle(fontSize: 12, color: kMuted, fontWeight: FontWeight.w500)),
        ]),
      ),
      body: Column(
        children: [
          Expanded(
            child: !_loaded
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const EmptyView(icon: Icons.waving_hand_rounded, title: 'Напишите первое сообщение', subtitle: 'Уточните детали: подъезд, домофон, режим ребёнка')
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) => _Bubble(message: _messages[_messages.length - 1 - i]),
                      ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: kLine))),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Сообщение', fillColor: kBg),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: mine ? kPrimary : Colors.white,
          border: mine ? null : Border.all(color: kLine),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(message.text, style: TextStyle(color: mine ? Colors.white : kPrimary, fontSize: 15)),
          const SizedBox(height: 2),
          Text(timeOnly(message.createdAt), style: TextStyle(color: mine ? Colors.white60 : kMuted, fontSize: 11)),
        ]),
      ),
    );
  }
}
