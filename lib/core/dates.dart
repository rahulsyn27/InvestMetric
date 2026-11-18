import 'package:intl/intl.dart';

/// Strips the time part.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole days from [a] to [b] (negative if b is before a). Uses UTC to avoid
/// daylight-saving surprises.
int daysBetween(DateTime a, DateTime b) {
  final ua = DateTime.utc(a.year, a.month, a.day);
  final ub = DateTime.utc(b.year, b.month, b.day);
  return ub.difference(ua).inDays;
}

/// Adds calendar months, clamping the day (31 Jan + 1 month = 28/29 Feb).
DateTime addMonths(DateTime d, int months) {
  final totalMonths = d.year * 12 + (d.month - 1) + months;
  final year = totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, d.day > lastDay ? lastDay : d.day);
}

/// Whole calendar months between two dates (start day counts as month 0).
int monthsBetween(DateTime from, DateTime to) {
  var m = (to.year - from.year) * 12 + (to.month - from.month);
  if (to.day < from.day) m -= 1;
  return m;
}

DateTime maxDate(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
DateTime minDate(DateTime a, DateTime b) => a.isBefore(b) ? a : b;

final _dmy = DateFormat('d MMM yyyy');
final _dm = DateFormat('d MMM');

String formatDate(DateTime d) => _dmy.format(d);
String formatDayMonth(DateTime d) => _dm.format(d);

/// ISO `yyyy-MM-dd` used for storage.
String toIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? fromIsoDate(Object? v) {
  if (v is! String || v.isEmpty) return null;
  return DateTime.tryParse(v);
}

/// An Indian tax year (financial year): 1 April to 31 March.
class TaxYear {
  const TaxYear(this.startYear);

  factory TaxYear.of(DateTime d) =>
      TaxYear(d.month >= DateTime.april ? d.year : d.year - 1);

  final int startYear;

  /// First day (inclusive).
  DateTime get start => DateTime(startYear, 4, 1);

  /// Day after the last day (exclusive), i.e. 1 April of the next year.
  DateTime get end => DateTime(startYear + 1, 4, 1);

  /// 31 March, the last day.
  DateTime get lastDay => DateTime(startYear + 1, 3, 31);

  /// "2026-27".
  String get label =>
      '$startYear-${((startYear + 1) % 100).toString().padLeft(2, '0')}';

  TaxYear get previous => TaxYear(startYear - 1);
  TaxYear get next => TaxYear(startYear + 1);

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  @override
  bool operator ==(Object other) =>
      other is TaxYear && other.startYear == startYear;

  @override
  int get hashCode => startYear.hashCode;

  @override
  String toString() => 'TaxYear($label)';
}
