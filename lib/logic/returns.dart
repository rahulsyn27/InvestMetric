import '../core/dates.dart';
import '../models/investment.dart';
import '../models/snapshot.dart';
import 'deposit_math.dart';
import 'nav_history.dart';
import 'valuation.dart';

/// The period buttons on the Returns card.
enum ReturnPeriod {
  oneMonth('1M'),
  threeMonths('3M'),
  sixMonths('6M'),
  oneYear('1Y'),
  taxYear('This tax year'),
  allTime('All time');

  const ReturnPeriod(this.label);
  final String label;

  /// First day of the period, or null for all time.
  DateTime? startFor(DateTime today) {
    final d = dateOnly(today);
    return switch (this) {
      oneMonth => addMonths(d, -1),
      threeMonths => addMonths(d, -3),
      sixMonths => addMonths(d, -6),
      oneYear => addMonths(d, -12),
      taxYear => TaxYear.of(d).start,
      allTime => null,
    };
  }
}

/// What is known about the start of the period, beyond the holdings
/// themselves.
class ReturnInputs {
  const ReturnInputs({this.navs = const {}, this.snapshot});

  static const none = ReturnInputs();

  /// AMFI NAV on (or just before) the start date, by scheme code.
  final Map<String, DatedNav> navs;

  /// The latest saved snapshot on or before the start date.
  final ValueSnapshot? snapshot;
}

/// The return of one holding over a period.
class HoldingReturn {
  const HoldingReturn({
    required this.startValue,
    required this.endValue,
    required this.added,
    required this.weightedAdded,
    required this.interest,
    required this.marketChange,
  });

  static const zero = HoldingReturn(
    startValue: 0,
    endValue: 0,
    added: 0,
    weightedAdded: 0,
    interest: 0,
    marketChange: 0,
  );

  final double startValue;
  final double endValue;

  /// Money put in during the period (negative if taken out).
  final double added;

  /// [added], each amount weighted by the share of the period it was
  /// invested for (Modified Dietz).
  final double weightedAdded;

  /// Interest earned in the period, including interest already paid out.
  final double interest;

  /// Change in market price (or in a hand-updated balance).
  final double marketChange;

  double get gain => interest + marketChange;

  HoldingReturn operator +(HoldingReturn o) => HoldingReturn(
    startValue: startValue + o.startValue,
    endValue: endValue + o.endValue,
    added: added + o.added,
    weightedAdded: weightedAdded + o.weightedAdded,
    interest: interest + o.interest,
    marketChange: marketChange + o.marketChange,
  );
}

/// The return of several holdings over a period.
class PeriodReturn {
  const PeriodReturn({
    required this.period,
    required this.from,
    required this.to,
    required this.total,
    required this.included,
    required this.leftOut,
  });

  final ReturnPeriod period;

  /// Null for all time.
  final DateTime? from;
  final DateTime to;
  final HoldingReturn total;

  /// Holdings counted.
  final int included;

  /// Holdings that couldn't be valued at the start of the period (no price
  /// history or snapshot that far back).
  final List<Investment> leftOut;

  double get gain => total.gain;
  double get interest => total.interest;
  double get marketChange => total.marketChange;
  double get startValue => total.startValue;
  double get endValue => total.endValue;
  double get added => total.added;

  /// Interest that was paid out to the bank account during the period, so it
  /// is in the gain but no longer in the holding's value.
  double get paidOut => gain - (endValue - startValue - added);

  /// What the gain is measured against: the value at the start plus money
  /// added, weighted by how long it was invested. For all time, everything
  /// put in.
  double get base =>
      from == null ? total.added : total.startValue + total.weightedAdded;

  /// Gain as % of [base] (not annualised), or null when there's no base.
  double? get gainPct => base > 0 ? gain / base * 100 : null;

  bool get isEmpty => included == 0;
}

/// Scheme codes whose NAV on [from] is needed: mutual funds held since
/// before the period started.
Set<String> navCodesNeeded(Iterable<Investment> items, DateTime from) => {
  for (final i in items)
    if (!i.isClosed &&
        i.type == AssetType.mutualFund &&
        (i.schemeCode?.isNotEmpty ?? false) &&
        !_boughtAfter(i, from))
      i.schemeCode!,
};

bool _boughtAfter(Investment inv, DateTime from) {
  final s = inv.startDate;
  return s != null && s.isAfter(from);
}

/// Return of [inv] from [from] (null = since it was bought) to [today].
///
/// Returns null when its value at [from] isn't known.
HoldingReturn? holdingReturn(
  Investment inv,
  DateTime? from,
  DateTime today, [
  ReturnInputs inputs = ReturnInputs.none,
]) {
  final to = dateOnly(today);
  final start = inv.startDate;
  if (start != null && start.isAfter(to)) return HoldingReturn.zero;

  if (inv.type.kind == ValuationKind.deposit) {
    return _depositReturn(inv, from, to);
  }

  final now = valuationOf(inv, to);
  final isInterest = inv.type.interestTaxFree; // PPF, EPF grow by interest
  HoldingReturn result({
    required double startValue,
    required double added,
    required double weightedAdded,
  }) {
    final change = now.current - startValue - added;
    return HoldingReturn(
      startValue: startValue,
      endValue: now.current,
      added: added,
      weightedAdded: weightedAdded,
      interest: isInterest ? change : 0,
      marketChange: isInterest ? 0 : change,
    );
  }

  // Bought during the period (or all time): starts from nothing.
  if (from == null || _boughtAfter(inv, from)) {
    return result(
      startValue: 0,
      added: now.invested,
      weightedAdded: now.invested * _weight(start ?? from, from, to),
    );
  }

  final snap = inputs.snapshot?.items[inv.id];
  double startValue;
  double investedThen;
  if (inv.type.kind == ValuationKind.market) {
    final code = inv.schemeCode;
    final price = (code == null ? null : inputs.navs[code]?.nav) ?? snap?.price;
    if (price == null) return null;
    final units = snap?.units ?? inv.units ?? 0;
    startValue = units * price;
    investedThen = snap?.invested ?? units * (inv.avgCost ?? 0);
  } else {
    if (snap == null) return null;
    startValue = snap.value;
    investedThen = snap.invested;
  }
  final added = now.invested - investedThen;
  // The dates of these top-ups aren't known: assume mid-period.
  return result(
    startValue: startValue,
    added: added,
    weightedAdded: added * 0.5,
  );
}

HoldingReturn _depositReturn(Investment inv, DateTime? from, DateTime to) {
  if (from == null) {
    final added = DepositMath.investedOn(inv, to);
    return HoldingReturn(
      startValue: 0,
      endValue: DepositMath.valueOn(inv, to),
      added: added,
      weightedAdded: added,
      interest: DepositMath.interestEarnedUntil(inv, to),
      marketChange: 0,
    );
  }
  double weighted;
  if (inv.isRecurring) {
    final m = inv.monthlyInstalment ?? 0;
    weighted = 0;
    for (final d in DepositMath.rdInstalmentDates(inv)) {
      if (d.isAfter(to)) break;
      if (d.isAfter(from)) weighted += m * _weight(d, from, to);
    }
  } else {
    final s = inv.startDate;
    weighted = (s != null && s.isAfter(from))
        ? (inv.principal ?? 0) * _weight(s, from, to)
        : 0;
  }
  return HoldingReturn(
    startValue: DepositMath.valueOn(inv, from),
    endValue: DepositMath.valueOn(inv, to),
    added: DepositMath.investedOn(inv, to) - DepositMath.investedOn(inv, from),
    weightedAdded: weighted,
    interest: DepositMath.interestBetween(inv, from, to),
    marketChange: 0,
  );
}

/// Share of the period [from, to] that money put in on [day] was invested.
double _weight(DateTime? day, DateTime? from, DateTime to) {
  if (day == null || from == null) return 1;
  final total = daysBetween(from, to);
  if (total <= 0) return 0;
  return (daysBetween(day, to) / total).clamp(0.0, 1.0);
}

/// Return of all open holdings in [items] over [period].
PeriodReturn periodReturn(
  Iterable<Investment> items,
  ReturnPeriod period,
  DateTime today, [
  ReturnInputs inputs = ReturnInputs.none,
]) {
  final from = period.startFor(today);
  var total = HoldingReturn.zero;
  var included = 0;
  final leftOut = <Investment>[];
  for (final inv in items.where((i) => !i.isClosed)) {
    final r = holdingReturn(inv, from, today, inputs);
    if (r == null) {
      leftOut.add(inv);
    } else {
      total += r;
      included++;
    }
  }
  return PeriodReturn(
    period: period,
    from: from,
    to: dateOnly(today),
    total: total,
    included: included,
    leftOut: leftOut,
  );
}
