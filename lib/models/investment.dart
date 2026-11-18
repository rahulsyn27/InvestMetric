import 'dart:ui' show Color;

import '../core/dates.dart';

/// How an investment's value is worked out.
enum ValuationKind {
  /// Units × price (mutual funds, stocks, gold bonds).
  market,

  /// Principal + interest from a rate (FD, RD, bonds, post office schemes).
  deposit,

  /// A balance you update yourself (PPF, EPF, NPS, property, insurance).
  balance,
}

enum AssetType {
  mutualFund('Mutual fund', 'MF', Color(0xFF6E9BFF), ValuationKind.market),
  stock('Stock', 'EQ', Color(0xFF3CC8B4), ValuationKind.market),
  fixedDeposit('Fixed deposit', 'FD', Color(0xFFF2A65A), ValuationKind.deposit),
  recurringDeposit(
    'Recurring deposit',
    'RD',
    Color(0xFFE88A5C),
    ValuationKind.deposit,
  ),
  postOffice(
    'Post office scheme',
    'PO',
    Color(0xFFD98C9E),
    ValuationKind.deposit,
  ),
  bond('Bond', 'BD', Color(0xFFB59CF0), ValuationKind.deposit),
  ppf('PPF', 'PPF', Color(0xFF9F86F5), ValuationKind.balance),
  epf('EPF', 'EPF', Color(0xFF8A7BD8), ValuationKind.balance),
  nps('NPS', 'NPS', Color(0xFFE77FB3), ValuationKind.balance),
  gold('Gold / SGB', 'AU', Color(0xFFE0C068), ValuationKind.market),
  realEstate('Property', 'RE', Color(0xFF8FB8A8), ValuationKind.balance),
  insurance('Insurance', 'IN', Color(0xFF9AB0C9), ValuationKind.balance),
  other('Other', 'OT', Color(0xFFA0A8B8), ValuationKind.balance);

  const AssetType(this.label, this.code, this.color, this.kind);

  final String label;
  final String code;
  final Color color;
  final ValuationKind kind;

  /// Interest on these is tax-free (so no TDS / taxable interest).
  bool get interestTaxFree => this == ppf || this == epf;

  /// Banks / post office usually deduct TDS on this interest.
  bool get tdsByDefault =>
      this == fixedDeposit || this == recurringDeposit || this == postOffice;

  static AssetType fromName(String? name) => AssetType.values.firstWhere(
    (t) => t.name == name,
    orElse: () => AssetType.other,
  );
}

/// How often interest is added to the balance.
enum Compounding {
  simple('Simple interest', 0),
  monthly('Monthly', 12),
  quarterly('Quarterly', 4),
  halfYearly('Half-yearly', 2),
  yearly('Yearly', 1);

  const Compounding(this.label, this.perYear);
  final String label;
  final int perYear;

  static Compounding fromName(String? name) => Compounding.values.firstWhere(
    (c) => c.name == name,
    orElse: () => Compounding.quarterly,
  );
}

/// Whether interest stays in the deposit or is paid out to the bank account.
enum Payout {
  cumulative('Added to deposit (cumulative)', 0),
  monthly('Paid out monthly', 1),
  quarterly('Paid out quarterly', 3),
  halfYearly('Paid out half-yearly', 6),
  yearly('Paid out yearly', 12);

  const Payout(this.label, this.months);
  final String label;

  /// Months between payouts (0 = cumulative).
  final int months;

  static Payout fromName(String? name) => Payout.values.firstWhere(
    (p) => p.name == name,
    orElse: () => Payout.cumulative,
  );
}

/// One holding: an FD, a mutual fund, a PPF account…
///
/// A single flexible record; which fields matter depends on [type].kind.
class Investment {
  const Investment({
    required this.id,
    required this.memberId,
    required this.type,
    required this.name,
    this.institution = '',
    this.reference = '',
    this.notes = '',
    this.startDate,
    this.isClosed = false,
    // deposit
    this.principal,
    this.monthlyInstalment,
    this.ratePct,
    this.maturityDate,
    this.compounding = Compounding.quarterly,
    this.payout = Payout.cumulative,
    this.tdsApplicable = false,
    this.form15Submitted = false,
    // market
    this.units,
    this.avgCost,
    this.currentPrice,
    this.priceDate,
    this.schemeCode,
    this.sipAmount,
    this.sipDay,
    // balance
    this.investedAmount,
    this.currentValue,
  });

  final String id;
  final String memberId;
  final AssetType type;

  /// "SBI FD", "Nifty 50 Index Fund – Direct Growth", "HDFC Bank".
  final String name;

  /// Bank / AMC / broker / post office. FD interest is grouped by this for TDS.
  final String institution;

  /// FD number, folio, account number (store only the last digits).
  final String reference;
  final String notes;

  /// Date opened / bought.
  final DateTime? startDate;

  /// Matured, sold or closed: kept for history, left out of totals.
  final bool isClosed;

  // ---- deposit fields ----
  final double? principal;

  /// RD only: amount paid every month.
  final double? monthlyInstalment;

  /// Interest rate, % per year (also used to estimate PPF/EPF interest).
  final double? ratePct;
  final DateTime? maturityDate;
  final Compounding compounding;
  final Payout payout;
  final bool tdsApplicable;

  /// Form 15G/15H given to the bank for the current tax year.
  final bool form15Submitted;

  // ---- market fields ----
  final double? units;

  /// Average buying price per unit.
  final double? avgCost;
  final double? currentPrice;
  final DateTime? priceDate;

  /// AMFI scheme code, used to refresh mutual fund NAVs.
  final String? schemeCode;
  final double? sipAmount;

  /// Day of month the SIP is debited (1–28).
  final int? sipDay;

  // ---- balance fields ----
  final double? investedAmount;
  final double? currentValue;

  bool get isRecurring => type == AssetType.recurringDeposit;

  Investment copyWith({
    String? id,
    String? memberId,
    double? currentPrice,
    DateTime? priceDate,
    bool? isClosed,
    bool? form15Submitted,
  }) => Investment.fromMap(id ?? this.id, {
    ...toMap(),
    'memberId': memberId ?? this.memberId,
    'currentPrice': currentPrice ?? this.currentPrice,
    'priceDate': toIsoDateOrNull(priceDate ?? this.priceDate),
    'isClosed': isClosed ?? this.isClosed,
    'form15Submitted': form15Submitted ?? this.form15Submitted,
  });

  Map<String, Object?> toMap() => {
    'memberId': memberId,
    'type': type.name,
    'name': name,
    'institution': institution,
    'reference': reference,
    'notes': notes,
    'startDate': toIsoDateOrNull(startDate),
    'isClosed': isClosed,
    'principal': principal,
    'monthlyInstalment': monthlyInstalment,
    'ratePct': ratePct,
    'maturityDate': toIsoDateOrNull(maturityDate),
    'compounding': compounding.name,
    'payout': payout.name,
    'tdsApplicable': tdsApplicable,
    'form15Submitted': form15Submitted,
    'units': units,
    'avgCost': avgCost,
    'currentPrice': currentPrice,
    'priceDate': toIsoDateOrNull(priceDate),
    'schemeCode': schemeCode,
    'sipAmount': sipAmount,
    'sipDay': sipDay,
    'investedAmount': investedAmount,
    'currentValue': currentValue,
  };

  factory Investment.fromMap(String id, Map<String, Object?> m) => Investment(
    id: id,
    memberId: (m['memberId'] as String?) ?? '',
    type: AssetType.fromName(m['type'] as String?),
    name: (m['name'] as String?) ?? '',
    institution: (m['institution'] as String?) ?? '',
    reference: (m['reference'] as String?) ?? '',
    notes: (m['notes'] as String?) ?? '',
    startDate: fromIsoDate(m['startDate']),
    isClosed: (m['isClosed'] as bool?) ?? false,
    principal: _d(m['principal']),
    monthlyInstalment: _d(m['monthlyInstalment']),
    ratePct: _d(m['ratePct']),
    maturityDate: fromIsoDate(m['maturityDate']),
    compounding: Compounding.fromName(m['compounding'] as String?),
    payout: Payout.fromName(m['payout'] as String?),
    tdsApplicable: (m['tdsApplicable'] as bool?) ?? false,
    form15Submitted: (m['form15Submitted'] as bool?) ?? false,
    units: _d(m['units']),
    avgCost: _d(m['avgCost']),
    currentPrice: _d(m['currentPrice']),
    priceDate: fromIsoDate(m['priceDate']),
    schemeCode: m['schemeCode'] as String?,
    sipAmount: _d(m['sipAmount']),
    sipDay: (m['sipDay'] as num?)?.toInt(),
    investedAmount: _d(m['investedAmount']),
    currentValue: _d(m['currentValue']),
  );
}

String? toIsoDateOrNull(DateTime? d) => d == null ? null : toIsoDate(d);

double? _d(Object? v) => v is num ? v.toDouble() : null;
