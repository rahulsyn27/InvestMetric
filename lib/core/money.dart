/// Indian-style money formatting: ₹12,34,567 and compact ₹12.3 L / ₹1.25 Cr.
library;

String _groupIndian(String digits) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

/// Formats [value] as rupees with Indian digit grouping.
///
/// `formatInr(1234567)` → `₹12,34,567`. With [showSign], positive values get
/// a leading `+`. Negative values always get `−` (a real minus sign).
String formatInr(num value, {int decimals = 0, bool showSign = false}) {
  final negative = value < 0;
  final abs = value.abs();
  final fixed = abs.toStringAsFixed(decimals);
  final dot = fixed.indexOf('.');
  final intPart = dot == -1 ? fixed : fixed.substring(0, dot);
  final fracPart = dot == -1 ? '' : fixed.substring(dot);
  final body = '₹${_groupIndian(intPart)}$fracPart';
  if (negative && abs >= 0.5 / _pow10(decimals)) return '−$body';
  if (showSign && abs >= 0.5 / _pow10(decimals)) return '+$body';
  return body;
}

double _pow10(int n) {
  var r = 1.0;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}

/// Short form for big numbers: ₹85,000 · ₹12.4 L · ₹1.25 Cr.
String formatInrCompact(num value) {
  final abs = value.abs();
  final sign = value < 0 ? '−' : '';
  if (abs >= 1e7) return '$sign₹${_trim((abs / 1e7).toStringAsFixed(2))} Cr';
  if (abs >= 1e5) return '$sign₹${_trim((abs / 1e5).toStringAsFixed(2))} L';
  return value < 0 ? '−${formatInr(abs)}' : formatInr(abs);
}

String _trim(String s) {
  if (!s.contains('.')) return s;
  s = s.replaceAll(RegExp(r'0+$'), '');
  return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
}

/// `12.345` → `12.3%`; with [showSign] → `+12.3%`.
String formatPct(double value, {int decimals = 1, bool showSign = false}) {
  final s = value.abs().toStringAsFixed(decimals);
  if (value < 0 && double.parse(s) != 0) return '−$s%';
  if (showSign && double.parse(s) != 0) return '+$s%';
  return '$s%';
}

/// Parses user input like "1,50,000" or "₹ 2500.50" into a number.
double? parseAmount(String? input) {
  if (input == null) return null;
  final cleaned = input.replaceAll(RegExp(r'[₹,\s]'), '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}
