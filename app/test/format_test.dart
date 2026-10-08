import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:lovebird/core/utils/format.dart';

void main() {
  setUpAll(() => initializeDateFormatting());

  test('countdown copy', () {
    expect(Fmt.countdown(0, 'your anniversary'), 'Today is your anniversary ❤️');
    expect(Fmt.countdown(14, 'your anniversary'), '14 days until your anniversary ❤️');
  });

  test('daysUntil handles Feb 29 in non-leap years', () {
    final d = Fmt.daysUntil(DateTime(2024, 2, 29));
    expect(d, inInclusiveRange(0, 366));
  });

  test('money formats minor units per currency', () {
    expect(Fmt.money(500000, 'NGN'), contains('5,000'));
    expect(Fmt.money(499, 'USD'), contains('4.99'));
    expect(Fmt.money(500, 'JPY'), contains('500'));
  });

  test('initials', () {
    expect(Fmt.initials('Mercy Ade'), 'MA');
    expect(Fmt.initials('david'), 'D');
    expect(Fmt.initials(''), '❤');
  });
}
