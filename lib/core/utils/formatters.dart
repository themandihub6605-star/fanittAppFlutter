import 'package:intl/intl.dart';

/// Every amount from the backend is in paise.
abstract final class Fmt {
  static final NumberFormat _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
  static final NumberFormat _inrPrecise = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
  static final NumberFormat _compact = NumberFormat.compact(locale: 'en_IN');

  static String money(int paise) {
    final rupees = paise / 100;
    return paise % 100 == 0 ? _inr.format(rupees) : _inrPrecise.format(rupees);
  }

  static String compact(num value) => _compact.format(value);

  /// "1,500" → 150000 paise. Returns null for empty or invalid input.
  static int? rupeesToPaise(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    final value = double.tryParse(cleaned);
    return value == null ? null : (value * 100).round();
  }

  static String paiseToRupeesInput(int paise) {
    final rupees = paise / 100;
    return paise % 100 == 0 ? rupees.toStringAsFixed(0) : rupees.toStringAsFixed(2);
  }

  static String date(DateTime date) => DateFormat('d MMM yyyy').format(date);
  static String shortDate(DateTime date) => DateFormat('d MMM').format(date);
  static String dateTime(DateTime date) => DateFormat('d MMM, h:mm a').format(date);
  static String time(DateTime date) => DateFormat('h:mm a').format(date);
  static String weekdayDateTime(DateTime date) => DateFormat('EEE, d MMM · h:mm a').format(date);

  static String relative(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return shortDate(date);
  }

  static String chatTimestamp(DateTime date) {
    final now = DateTime.now();
    final sameDay = now.year == date.year && now.month == date.month && now.day == date.day;
    if (sameDay) return time(date);
    if (now.difference(date).inDays < 7) return DateFormat('EEE').format(date);
    return shortDate(date);
  }

  static String titleCase(String value) => value
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
