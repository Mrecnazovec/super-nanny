import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../state/session.dart';
import '../../widgets/common.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.phone, this.demoCode});

  final String phone;
  final String? demoCode;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _code = TextEditingController();
  String? _demoCode;
  int _resendIn = 60;
  Timer? _timer;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _demoCode = widget.demoCode;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendIn = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendIn <= 1) t.cancel();
      if (mounted) setState(() => _resendIn--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_busy || _code.text.length != 4) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await Api.instance.post('/api/auth/verify', {'phone': widget.phone, 'code': _code.text});
      await ref.read(sessionProvider.notifier).signIn(Map<String, dynamic>.from(res as Map));
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
      _code.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      final res = Map<String, dynamic>.from(await Api.instance.post('/api/auth/otp', {'phone': widget.phone}) as Map);
      setState(() => _demoCode = res['demo_code'] as String?);
      _startTimer();
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Text('Введите код', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Мы отправили SMS с кодом на ${formatPhone(widget.phone)}', style: const TextStyle(color: kMuted, fontSize: 15)),
            if (_demoCode != null) ...[
              const SizedBox(height: 20),
              InfoPlate(
                icon: Icons.science_outlined,
                child: Row(
                  children: [
                    Expanded(child: Text('Демо-режим: SMS-шлюз не подключён.\nВаш код: $_demoCode')),
                    TextButton(
                      onPressed: () {
                        _code.text = _demoCode!;
                        _verify();
                      },
                      child: const Text('Вставить'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 28),
            TextField(
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 18),
              decoration: InputDecoration(counterText: '', hintText: '••••', errorText: _error),
              onChanged: (v) {
                if (v.length == 4) _verify();
              },
            ),
            const SizedBox(height: 20),
            if (_busy) const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 8),
            Center(
              child: _resendIn > 0
                  ? Text('Отправить код повторно через $_resendIn сек', style: const TextStyle(color: kMuted))
                  : TextButton(onPressed: _resend, child: const Text('Отправить код ещё раз')),
            ),
          ],
        ),
      ),
    );
  }
}
