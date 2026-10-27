import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'otp_screen.dart';

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _phone = TextEditingController();

  String get _digits => _phone.text.replaceAll(RegExp(r'\D'), '');

  @override
  void initState() {
    super.initState();
    _phone.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = '+998$_digits';
    final res = Map<String, dynamic>.from(await Api.instance.post('/api/auth/otp', {'phone': phone}) as Map);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OtpScreen(phone: phone, demoCode: res['demo_code'] as String?)),
    );
  }

  /// Скрытая настройка адреса сервера (долгое нажатие на логотип).
  Future<void> _serverDialog() async {
    final ctrl = TextEditingController(text: Api.instance.baseUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Адрес сервера'),
        content: TextField(controller: ctrl, keyboardType: TextInputType.url),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Сохранить')),
        ],
      ),
    );
    if (url != null && url.startsWith('http')) await Api.instance.setBaseUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight - 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 32),
                  GestureDetector(onLongPress: _serverDialog, child: const AppLogo(size: 72)),
                  const SizedBox(height: 28),
                  Text('Супер Няня', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: kPrimary)),
                  const SizedBox(height: 8),
                  const Text(
                    'Проверенные няни рядом с вами.\nКаждая проходит проверку документов, медкнижки и МВД.',
                    style: TextStyle(color: kMuted, fontSize: 15, height: 1.4),
                  ),
                  const SizedBox(height: 36),
                  const Text('Номер телефона', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phone,
                    autofocus: true,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [UzPhoneFormatter()],
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 1),
                    decoration: const InputDecoration(
                      prefixText: '+998 ',
                      prefixStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kPrimary),
                      hintText: '90 123 45 67',
                    ),
                    onSubmitted: (_) {
                      if (_digits.length == 9) _submit().catchError((Object e) { if (context.mounted) showMessage(context, e); });
                    },
                  ),
                  const SizedBox(height: 24),
                  BusyButton(label: 'Получить код', onPressed: _digits.length == 9 ? _submit : null),
                  const SizedBox(height: 16),
                  const Text(
                    'Нажимая «Получить код», вы соглашаетесь с условиями сервиса и обработкой персональных данных.',
                    style: TextStyle(color: kMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Center(child: Text('v$kAppVersion', style: const TextStyle(color: kLine, fontSize: 11))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
