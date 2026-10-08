import 'package:intl/intl.dart';

class Fmt {
  static String time(DateTime d) => DateFormat.jm().format(d.toLocal());
  static String day(DateTime d) => DateFormat.yMMMd().format(d.toLocal());
  static String dayShort(DateTime d) => DateFormat.MMMd().format(d.toLocal());
  static String monthYear(DateTime d) => DateFormat.yMMMM().format(d.toLocal());
  static String weekdayTime(DateTime d) => DateFormat('EEEE, h:mm a').format(d.toLocal());

  static String relative(DateTime d) {
    final now = DateTime.now();
    final diff = now.difference(d.toLocal());
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return dayShort(d);
  }

  static String chatDayLabel(DateTime d) {
    final local = d.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(local.year, local.month, local.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat.EEEE().format(local);
    return DateFormat.yMMMd().format(local);
  }

  /// Days until the next occurrence of [date] (yearly), 0 = today.
  static int daysUntil(DateTime date, {bool yearly = true}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!yearly) return DateTime(date.year, date.month, date.day).difference(today).inDays;
    var next = _safeDate(today.year, date.month, date.day);
    if (next.isBefore(today)) next = _safeDate(today.year + 1, date.month, date.day);
    return next.difference(today).inDays;
  }

  static DateTime _safeDate(int y, int m, int d) {
    final lastDay = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, d > lastDay ? lastDay : d);
  }

  static String countdown(int days, String title) {
    if (days == 0) return 'Today is $title ❤️';
    if (days == 1) return 'Tomorrow is $title ❤️';
    return '$days days until $title ❤️';
  }

  /// Money from minor units in the given ISO currency, localised.
  static String money(int amountMinor, String currency) {
    final f = NumberFormat.simpleCurrency(name: currency);
    final digits = f.decimalDigits ?? 2;
    var divisor = 1;
    for (var i = 0; i < digits; i++) {
      divisor *= 10;
    }
    return f.format(amountMinor / divisor);
  }

  static String duration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
  }

  static String initials(String name) {
    String first(String w) => w.runes.isEmpty ? '' : String.fromCharCode(w.runes.first).toUpperCase();
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '❤';
    if (parts.length == 1) return first(parts.first);
    return first(parts.first) + first(parts.last);
  }
}
