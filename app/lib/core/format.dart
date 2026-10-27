import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final _money = NumberFormat.decimalPattern('ru');

String money(num? v) => '${_money.format(v ?? 0)} сум';

String km(int? meters) {
  if (meters == null) return '';
  if (meters < 1000) return '$meters м';
  return '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} км';
}

String dateTime(int? ms) => ms == null ? '—' : DateFormat('d MMM, HH:mm', 'ru').format(DateTime.fromMillisecondsSinceEpoch(ms));

String timeOnly(int? ms) => ms == null ? '' : DateFormat('HH:mm', 'ru').format(DateTime.fromMillisecondsSinceEpoch(ms));

String shortDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) return timeOnly(ms);
  return DateFormat('d MMM', 'ru').format(d);
}

String duration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

String years(int n) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return '$n год';
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return '$n года';
  return '$n лет';
}

String formatPhone(String phone) {
  final d = phone.replaceAll(RegExp(r'\D'), '');
  if (d.length != 12) return phone;
  return '+${d.substring(0, 3)} ${d.substring(3, 5)} ${d.substring(5, 8)} ${d.substring(8, 10)} ${d.substring(10)}';
}

const orderStatusLabels = {
  'pending': 'Ждём ответа няни',
  'accepted': 'Заказ принят',
  'on_the_way': 'Няня в пути',
  'arrived': 'Няня на месте',
  'in_progress': 'Идёт работа',
  'completed': 'Завершён',
  'cancelled': 'Отменён',
  'declined': 'Няня отклонила',
  'expired': 'Нет ответа',
};

const activeStatuses = {'pending', 'accepted', 'on_the_way', 'arrived', 'in_progress'};

/// Маска телефона Узбекистана: XX XXX XX XX (префикс +998 показывается отдельно).
class UzPhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 9) digits = digits.substring(0, 9);
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i == 2 || i == 5 || i == 7) buf.write(' ');
      buf.write(digits[i]);
    }
    final text = buf.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Группировка цифр: «XXXX XXXX XXXX XXXX» для карты, «MM/YY» для срока.
class GroupedDigitsFormatter extends TextInputFormatter {
  GroupedDigitsFormatter(this.groups, this.separator);

  final List<int> groups;
  final String separator;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final max = groups.fold<int>(0, (a, b) => a + b);
    if (digits.length > max) digits = digits.substring(0, max);
    final buf = StringBuffer();
    var pos = 0;
    for (final g in groups) {
      if (pos >= digits.length) break;
      if (pos > 0) buf.write(separator);
      final end = (pos + g).clamp(0, digits.length);
      buf.write(digits.substring(pos, end));
      pos = end;
    }
    final text = buf.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
