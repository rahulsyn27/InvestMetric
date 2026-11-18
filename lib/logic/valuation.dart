import 'dart:math' as math;

import '../core/dates.dart';
import '../models/investment.dart';
import 'deposit_math.dart';

class Valuation {
  const Valuation({required this.invested, required this.current});

  static const zero = Valuation(invested: 0, current: 0);

  final double invested;
  final double current;

  double get gain => current - invested;

  /// Gain as % of invested, or null when nothing was invested.
  double? get gainPct => invested > 0 ? gain / invested * 100 : null;

  Valuation operator +(Valuation o) =>
      Valuation(invested: invested + o.invested, current: current + o.current);
}

Valuation valuationOf(Investment inv, DateTime today) {
  switch (inv.type.kind) {
    case ValuationKind.market:
      final units = inv.units ?? 0;
      final cost = inv.avgCost ?? 0;
      final price = inv.currentPrice ?? cost;
      return Valuation(invested: units * cost, current: units * price);
    case ValuationKind.deposit:
      return Valuation(
        invested: DepositMath.investedOn(inv, today),
        current: DepositMath.valueOn(inv, today),
      );
    case ValuationKind.balance:
      final invested = inv.investedAmount ?? 0;
      return Valuation(
        invested: invested,
        current: inv.currentValue ?? invested,
      );
  }
}

Valuation totalValuation(Iterable<Investment> items, DateTime today) => items
    .where((i) => !i.isClosed)
    .fold(Valuation.zero, (sum, i) => sum + valuationOf(i, today));

/// Yearly growth rate (CAGR) in %, only meaningful after about a year.
/// Returns null when there isn't enough information.
double? annualisedReturnPct(Investment inv, DateTime today) {
  final start = inv.startDate;
  if (start == null) return null;
  final days = daysBetween(start, today);
  if (days < 365) return null;
  if (inv.type.kind == ValuationKind.deposit) return inv.ratePct;
  final v = valuationOf(inv, today);
  if (v.invested <= 0 || v.current <= 0) return null;
  return (math.pow(v.current / v.invested, 365 / days) - 1) * 100;
}

/// Totals by asset type, largest first.
List<(AssetType, Valuation)> byAssetType(
  Iterable<Investment> items,
  DateTime today,
) {
  final map = <AssetType, Valuation>{};
  for (final i in items.where((i) => !i.isClosed)) {
    map[i.type] = (map[i.type] ?? Valuation.zero) + valuationOf(i, today);
  }
  final list = map.entries.map((e) => (e.key, e.value)).toList()
    ..sort((a, b) => b.$2.current.compareTo(a.$2.current));
  return list;
}
