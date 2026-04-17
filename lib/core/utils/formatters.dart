import 'package:intl/intl.dart';

class AppFormatters {
  static final NumberFormat _currency = NumberFormat.currency(
    locale: 'vi_VN',
    symbol: '₫',
    decimalDigits: 0,
  );

  static String currency(num value) => _currency.format(value);

  static String date(DateTime? value) {
    if (value == null) return '--';
    return DateFormat('dd/MM/yyyy').format(value);
  }

  static String dateTime(DateTime? value) {
    if (value == null) return '--';
    return DateFormat('dd/MM/yyyy HH:mm').format(value);
  }
}
