import '../core/dates.dart';
import '../models/ais.dart';

/// A word on a PDF page with its position (points, top-left origin).
/// [page] keeps pages in order.
class PdfWord {
  const PdfWord(
    this.text,
    this.x,
    this.y, {
    this.width = 0,
    this.height = 8,
    this.page = 0,
  });

  final String text;
  final double x;
  final double y;
  final double width;
  final double height;
  final int page;

  double get centerY => y + height / 2;
}

/// Groups words into visual lines (same page, overlapping vertically), each
/// sorted left to right; lines are returned top to bottom.
List<List<PdfWord>> groupIntoLines(Iterable<PdfWord> words) {
  final all = words.where((w) => w.text.trim().isNotEmpty).toList();
  if (all.isEmpty) return const [];
  // Watermarks ("INCOME TAX DEPARTMENT") are much bigger than table text and
  // would merge into table rows: leave them out.
  final heights = all.map((w) => w.height).toList()..sort();
  final typical = heights[heights.length ~/ 2];
  final sorted = all.where((w) => w.height <= typical * 2.2).toList()
    ..sort((a, b) {
      final p = a.page.compareTo(b.page);
      if (p != 0) return p;
      return a.centerY.compareTo(b.centerY);
    });
  final lines = <List<PdfWord>>[];
  for (final w in sorted) {
    final last = lines.isEmpty ? null : lines.last;
    if (last != null &&
        last.first.page == w.page &&
        (w.centerY - _avgCenter(last)).abs() <= w.height * 0.45) {
      last.add(w);
    } else {
      lines.add([w]);
    }
  }
  for (final l in lines) {
    l.sort((a, b) => a.x.compareTo(b.x));
  }
  return lines;
}

double _avgCenter(List<PdfWord> line) =>
    line.fold(0.0, (s, w) => s + w.centerY) / line.length;

String _text(List<PdfWord> line) => line.map((w) => w.text).join(' ').trim();

double? _num(String s) {
  final cleaned = s.replaceAll(',', '').trim();
  if (cleaned.isEmpty || cleaned == '-') return null;
  return double.tryParse(cleaned);
}

DateTime? _dmy(String s) {
  final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(s.trim());
  if (m == null) return null;
  return DateTime(int.parse(m[3]!), int.parse(m[2]!), int.parse(m[1]!));
}

final _infoCode = RegExp(
  r'^[A-Z]{2,5}-[A-Z0-9]+(?:-[A-Z0-9]+)*(?:\([A-Z0-9]+\))?$',
);
final _amount = RegExp(r'^-?[\d,]+(?:\.\d+)?$');
final _tan = RegExp(r'^(.*?)\s*\(([A-Z]{4}\d{5}[A-Z])\)\s*$');
final _partHeading = RegExp(r'^Part\s+([A-Z]\d*)\b', caseSensitive: false);
final _taxYear = RegExp(
  r'(?:Tax\s+Year|Financial\s+Year|F\.\s?Y\.|T\.\s?Y\.)[^0-9]{0,20}(\d{4})\s*-\s*(\d{2,4})',
  caseSensitive: false,
);
final _anyYear = RegExp(r'\b(20\d{2})-(\d{2})\b');

final _detailRow = RegExp(
  r'^\d+\s+(Q[1-4]\s*(?:\([^)]*\))?)\s+(\d{2}/\d{2}/\d{4})\s+([\d,]+(?:\.\d+)?)\s+([\d,]+(?:\.\d+)?)\s+([\d,]+(?:\.\d+)?)(?:\s+([A-Za-z]+))?\s*$',
);
final _refundRow = RegExp(
  r'^\d+\s+(\d{4}-\d{2})\s+(\S+)\s+(.+?)\s+([\d,]+(?:\.\d+)?)\s+(\d{2}/\d{2}/\d{4})\s*$',
);
final _paymentRow = RegExp(
  r'^\d+\s+(\d{4}-\d{2})\s+(\d{4})\s+(\d{3})\s+([\d,.]+)\s+([\d,.]+)\s+([\d,.]+)\s+([\d,.]+)\s+([\d,.]+)\s+\d{7}\s+(\d{2}/\d{2}/\d{4})',
);

class AisParseResult {
  const AisParseResult({
    required this.year,
    required this.records,
    required this.payments,
    required this.refunds,
    required this.lines,
  });

  /// Null if the tax year couldn't be found.
  final TaxYear? year;
  final List<AisRecord> records;
  final List<AisTaxPayment> payments;
  final List<AisRefund> refunds;

  /// The text lines read from the PDF (for troubleshooting).
  final List<String> lines;

  bool get looksLikeAis =>
      lines.any((l) => l.contains('Annual Information Statement')) ||
      records.isNotEmpty;

  AisStatement toStatement(String memberId, {TaxYear? fallbackYear}) =>
      AisStatement(
        memberId: memberId,
        year: year ?? fallbackYear ?? TaxYear.of(DateTime.now()),
        records: records,
        payments: payments,
        refunds: refunds,
        importedAt: DateTime.now(),
      );
}

/// Column positions of an AIS information table, from its header row.
class _Columns {
  _Columns(this.description, this.source, this.count);

  final double description;
  final double source;
  final double count;
}

_Columns? _headerColumns(List<PdfWord> line) {
  final info = line
      .where((w) => w.text.toUpperCase() == 'INFORMATION')
      .toList();
  final count = line.where((w) => w.text.toUpperCase() == 'COUNT').firstOrNull;
  if (info.length < 3 || count == null) return null;
  return _Columns(info[1].x, info[2].x, count.x);
}

/// Reads AIS tables from positioned words.
///
/// Understands the layout of the AIS PDF from the e-filing portal:
/// - Part B1: information rows (code, description, source, count, amount)
///   each followed by TDS/TCS credit rows (quarter, date, amount, TDS…)
/// - Part B2/B7: information rows only
/// - Part B3: tax payments, Part B4: refunds
AisParseResult parseAis(List<List<PdfWord>> lines) {
  TaxYear? year;
  final records = <AisRecord>[];
  final payments = <AisTaxPayment>[];
  final refunds = <AisRefund>[];
  final texts = <String>[];

  var part = '';
  _Columns? cols;
  // Index in [records] of the row that detail lines and wrapped text attach to.
  int? current;
  var currentHasDetails = false;

  for (final line in lines) {
    final text = _text(line);
    if (text.isEmpty) continue;
    texts.add(text);

    if (year == null) {
      final m = _taxYear.firstMatch(text);
      if (m != null && !text.toLowerCase().contains('assessment year')) {
        year = TaxYear(int.parse(m[1]!));
      }
    }

    final heading = _partHeading.firstMatch(text);
    if (heading != null) {
      part = heading[1]!.toUpperCase();
      current = null;
      continue;
    }

    final header = _headerColumns(line);
    if (header != null) {
      cols = header;
      current = null;
      continue;
    }

    final words = line.map((w) => w.text).toList();

    // Information row: "1  TDS-392  Salary received (Section 392)  JSW … (TAN)  6  11,14,164"
    if (words.length >= 4 &&
        int.tryParse(words[0]) != null &&
        _infoCode.hasMatch(words[1])) {
      final rest = line.sublist(2);
      // Trailing numbers: count and amount.
      final nums = <PdfWord>[];
      for (var i = rest.length - 1; i >= 0 && nums.length < 2; i--) {
        if (_amount.hasMatch(rest[i].text)) {
          nums.insert(0, rest[i]);
        } else {
          break;
        }
      }
      final middle = rest.sublist(0, rest.length - nums.length);
      final desc = <String>[];
      final src = <String>[];
      if (cols != null) {
        for (final w in middle) {
          (w.x >= cols.source - 2 ? src : desc).add(w.text);
        }
      } else {
        desc.addAll(middle.map((w) => w.text));
      }
      var source = src.join(' ');
      var description = desc.join(' ');
      if (source.isEmpty) {
        // No column positions: split at the TAN "(ABCD12345E)" if present.
        final all = middle.map((w) => w.text).join(' ');
        final m = _tan.firstMatch(all);
        if (m != null) {
          description = m[1]!;
        }
      }
      var tan = '';
      final t = _tan.firstMatch(source);
      if (t != null) {
        source = t[1]!.trim();
        tan = t[2]!;
      }
      records.add(
        AisRecord(
          part: part,
          code: words[1],
          description: description.trim(),
          source: source.trim(),
          tan: tan,
          count: nums.length == 2 ? (_num(nums[0].text)?.toInt() ?? 0) : 0,
          amount: nums.isEmpty ? 0 : (_num(nums.last.text) ?? 0),
        ),
      );
      current = records.length - 1;
      currentHasDetails = false;
      continue;
    }

    // TDS/TCS credit row under the last information row.
    final d = _detailRow.firstMatch(text);
    if (d != null && current != null) {
      final r = records[current];
      records[current] = r.copyWith(
        entries: [
          ...r.entries,
          AisEntry(
            quarter: d[1]!.replaceAll(' ', ''),
            date: _dmy(d[2]!)!,
            amount: _num(d[3]!) ?? 0,
            tdsDeducted: _num(d[4]!) ?? 0,
            tdsDeposited: _num(d[5]!) ?? 0,
            status: d[6] ?? '',
          ),
        ],
      );
      currentHasDetails = true;
      continue;
    }

    if (part == 'B3') {
      final p = _paymentRow.firstMatch(text);
      if (p != null) {
        payments.add(
          AisTaxPayment(
            date: _dmy(p[9]!)!,
            amount: _num(p[8]!) ?? 0,
            minorHead: p[3]!,
          ),
        );
        continue;
      }
    }

    if (part == 'B4') {
      final r = _refundRow.firstMatch(text);
      if (r != null) {
        refunds.add(
          AisRefund(
            forYear: r[1]!,
            mode: r[2]!,
            amount: _num(r[4]!) ?? 0,
            date: _dmy(r[5]!),
          ),
        );
        continue;
      }
    }

    // Wrapped description / source text of the row above.
    if (current != null &&
        !currentHasDetails &&
        cols != null &&
        int.tryParse(words.first) == null &&
        line.every(
          (w) => w.x >= cols!.description - 2 && w.x < cols.count - 2,
        )) {
      final r = records[current];
      final desc = line
          .where((w) => w.x < cols!.source - 2)
          .map((w) => w.text)
          .join(' ');
      var src = line
          .where((w) => w.x >= cols!.source - 2)
          .map((w) => w.text)
          .join(' ');
      var tan = r.tan;
      var source = [r.source, src].where((s) => s.isNotEmpty).join(' ');
      final t = _tan.firstMatch(source);
      if (t != null) {
        source = t[1]!.trim();
        tan = t[2]!;
      }
      records[current] = r.copyWith(
        description: [r.description, desc].where((s) => s.isNotEmpty).join(' '),
        source: source,
        tan: tan,
      );
      continue;
    }
  }

  if (year == null) {
    for (final t in texts.take(15)) {
      final m = _anyYear.firstMatch(t);
      if (m != null) {
        year = TaxYear(int.parse(m[1]!));
        break;
      }
    }
  }

  return AisParseResult(
    year: year,
    records: records,
    payments: payments,
    refunds: refunds,
    lines: texts,
  );
}
