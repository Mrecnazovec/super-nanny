import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/location.dart';
import '../core/theme.dart';
import 'common.dart';

/// Тревожная кнопка: срабатывает после удержания 3 секунды.
class SosButton extends StatefulWidget {
  const SosButton({super.key, this.orderId});

  final int? orderId;

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(vsync: this, duration: const Duration(seconds: 3))
    ..addListener(() => setState(() {}))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _fire();
    });
  bool _sending = false;

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _start() {
    if (_sending) return;
    HapticFeedback.mediumImpact();
    _hold.forward(from: 0);
  }

  void _cancel() {
    if (_hold.isAnimating) {
      _hold.reverse();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Удерживайте кнопку SOS 3 секунды'), duration: Duration(seconds: 2)));
    }
  }

  Future<void> _fire() async {
    setState(() => _sending = true);
    HapticFeedback.heavyImpact();
    try {
      final pos = await quickLocation();
      await Api.instance.post('/api/sos', {
        'order_id': ?widget.orderId,
        if (pos != null) 'lat': pos.latitude,
        if (pos != null) 'lng': pos.longitude,
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.shield_rounded, color: kPink, size: 40),
          title: const Text('Сигнал SOS отправлен'),
          content: Text(
            'Администратор уже получил тревогу${pos != null ? ' и ваши координаты' : ''} и свяжется с вами.\n\n'
            'При угрозе жизни звоните: 102 — полиция, 103 — скорая.',
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Понятно'))],
        ),
      );
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      _hold.reset();
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _start(),
      onPointerUp: (_) => _cancel(),
      onPointerCancel: (_) => _cancel(),
      child: SizedBox(
        width: 76,
        height: 76,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 76,
              height: 76,
              child: CircularProgressIndicator(
                value: _hold.value,
                strokeWidth: 5,
                color: kPink,
                backgroundColor: kPink.withValues(alpha: 0.15),
              ),
            ),
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: kPink,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: kPink.withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              alignment: Alignment.center,
              child: _sending
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                  : const Text('SOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}
