import '../core/dates.dart';

/// One TDS/TCS credit line in AIS (e.g. a salary month or an interest credit).
class AisEntry {
  const AisEntry({
    required this.quarter,
    required this.date,
    required this.amount,
    required this.tdsDeducted,
    required this.tdsDeposited,
    this.status = '',
  });

  /// "Q2(Jul-Sep)".
  final String quarter;
  final DateTime date;

  /// Amount paid / credited.
  final double amount;
  final double tdsDeducted;
  final double tdsDeposited;

  /// "Active", "Inactive"…
  final String status;

  Map<String, Object?> toMap() => {
    'quarter': quarter,
    'date': toIsoDate(date),
    'amount': amount,
    'tdsDeducted': tdsDeducted,
    'tdsDeposited': tdsDeposited,
    'status': status,
  };

  factory AisEntry.fromMap(Map<String, Object?> m) => AisEntry(
    quarter: (m['quarter'] as String?) ?? '',
    date: fromIsoDate(m['date']) ?? DateTime(2000),
    amount: _d(m['amount']),
    tdsDeducted: _d(m['tdsDeducted']),
    tdsDeposited: _d(m['tdsDeposited']),
    status: (m['status'] as String?) ?? '',
  );
}

/// One "information" row of AIS: a code (TDS-392, SFT-016…) from one source.
class AisRecord {
  const AisRecord({
    required this.part,
    required this.code,
    required this.description,
    required this.source,
    this.tan = '',
    this.count = 0,
    this.amount = 0,
    this.entries = const [],
  });

  /// "B1" (TDS/TCS), "B2" (SFT), "B7"…
  final String part;
  final String code;
  final String description;

  /// Who reported it: employer, bank, company.
  final String source;

  /// Deductor's TAN, when shown.
  final String tan;
  final int count;
  final double amount;
  final List<AisEntry> entries;

  bool get isTds => code.toUpperCase().startsWith('TDS');
  bool get isTcs => code.toUpperCase().startsWith('TCS');
  bool get isInterest => description.toLowerCase().contains('interest');
  bool get isSalary => description.toLowerCase().contains('salary');

  double get tdsDeducted => entries.fold(0, (s, e) => s + e.tdsDeducted);
  double get tdsDeposited => entries.fold(0, (s, e) => s + e.tdsDeposited);

  /// Total amount; falls back to the sum of entries.
  double get total =>
      amount > 0 ? amount : entries.fold(0, (s, e) => s + e.amount);

  DateTime? get lastDate => entries.isEmpty
      ? null
      : entries.map((e) => e.date).reduce((a, b) => a.isAfter(b) ? a : b);

  AisRecord copyWith({
    String? description,
    String? source,
    String? tan,
    List<AisEntry>? entries,
  }) => AisRecord(
    part: part,
    code: code,
    description: description ?? this.description,
    source: source ?? this.source,
    tan: tan ?? this.tan,
    count: count,
    amount: amount,
    entries: entries ?? this.entries,
  );

  Map<String, Object?> toMap() => {
    'part': part,
    'code': code,
    'description': description,
    'source': source,
    'tan': tan,
    'count': count,
    'amount': amount,
    'entries': [for (final e in entries) e.toMap()],
  };

  factory AisRecord.fromMap(Map<String, Object?> m) => AisRecord(
    part: (m['part'] as String?) ?? '',
    code: (m['code'] as String?) ?? '',
    description: (m['description'] as String?) ?? '',
    source: (m['source'] as String?) ?? '',
    tan: (m['tan'] as String?) ?? '',
    count: (m['count'] as num?)?.toInt() ?? 0,
    amount: _d(m['amount']),
    entries: [
      for (final e in (m['entries'] as List?) ?? const [])
        AisEntry.fromMap(Map<String, Object?>.from(e as Map)),
    ],
  );
}

/// A tax payment shown in AIS Part B3 (advance tax, self-assessment tax).
class AisTaxPayment {
  const AisTaxPayment({
    required this.date,
    required this.amount,
    this.minorHead = '',
  });

  final DateTime date;
  final double amount;

  /// "100" advance tax, "300" self-assessment tax, "400" regular assessment.
  final String minorHead;

  String get label => switch (minorHead) {
    '100' => 'Advance tax',
    '300' => 'Self-assessment tax',
    '400' => 'Tax on regular assessment',
    _ => 'Tax paid',
  };

  Map<String, Object?> toMap() => {
    'date': toIsoDate(date),
    'amount': amount,
    'minorHead': minorHead,
  };

  factory AisTaxPayment.fromMap(Map<String, Object?> m) => AisTaxPayment(
    date: fromIsoDate(m['date']) ?? DateTime(2000),
    amount: _d(m['amount']),
    minorHead: (m['minorHead'] as String?) ?? '',
  );
}

/// A refund shown in AIS Part B4.
class AisRefund {
  const AisRefund({
    required this.forYear,
    required this.amount,
    this.date,
    this.mode = '',
  });

  /// "2025-26".
  final String forYear;
  final double amount;
  final DateTime? date;
  final String mode;

  Map<String, Object?> toMap() => {
    'forYear': forYear,
    'amount': amount,
    'date': date == null ? null : toIsoDate(date!),
    'mode': mode,
  };

  factory AisRefund.fromMap(Map<String, Object?> m) => AisRefund(
    forYear: (m['forYear'] as String?) ?? '',
    amount: _d(m['amount']),
    date: fromIsoDate(m['date']),
    mode: (m['mode'] as String?) ?? '',
  );
}

/// Everything read from one member's AIS for one tax year.
class AisStatement {
  const AisStatement({
    required this.memberId,
    required this.year,
    required this.records,
    this.payments = const [],
    this.refunds = const [],
    this.importedAt,
  });

  final String memberId;
  final TaxYear year;
  final List<AisRecord> records;
  final List<AisTaxPayment> payments;
  final List<AisRefund> refunds;
  final DateTime? importedAt;

  /// Firestore document id: one statement per member per year.
  String get docId => '${memberId}_${year.startYear}';

  Iterable<AisRecord> get tdsRecords =>
      records.where((r) => r.isTds || r.isTcs);

  double get totalTds => tdsRecords.fold(0, (s, r) => s + r.tdsDeducted);

  AisStatement copyWith({String? memberId, DateTime? importedAt}) =>
      AisStatement(
        memberId: memberId ?? this.memberId,
        year: year,
        records: records,
        payments: payments,
        refunds: refunds,
        importedAt: importedAt ?? this.importedAt,
      );

  Map<String, Object?> toMap() => {
    'memberId': memberId,
    'taxYear': year.startYear,
    'records': [for (final r in records) r.toMap()],
    'payments': [for (final p in payments) p.toMap()],
    'refunds': [for (final r in refunds) r.toMap()],
    'importedAt': importedAt?.toIso8601String(),
  };

  factory AisStatement.fromMap(Map<String, Object?> m) => AisStatement(
    memberId: (m['memberId'] as String?) ?? '',
    year: TaxYear((m['taxYear'] as num?)?.toInt() ?? 2000),
    records: [
      for (final r in (m['records'] as List?) ?? const [])
        AisRecord.fromMap(Map<String, Object?>.from(r as Map)),
    ],
    payments: [
      for (final p in (m['payments'] as List?) ?? const [])
        AisTaxPayment.fromMap(Map<String, Object?>.from(p as Map)),
    ],
    refunds: [
      for (final r in (m['refunds'] as List?) ?? const [])
        AisRefund.fromMap(Map<String, Object?>.from(r as Map)),
    ],
    importedAt: m['importedAt'] is String
        ? DateTime.tryParse(m['importedAt'] as String)
        : null,
  );
}

double _d(Object? v) => v is num ? v.toDouble() : 0;
