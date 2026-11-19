import '../core/dates.dart';
import '../logic/valuation.dart';
import 'investment.dart';

/// One holding as it stood on a snapshot day.
class SnapshotItem {
  const SnapshotItem({
    required this.value,
    required this.invested,
    this.units,
    this.price,
  });

  final double value;
  final double invested;

  /// Market holdings only.
  final double? units;
  final double? price;

  Map<String, Object?> toMap() => {
    'v': value,
    'i': invested,
    if (units != null) 'u': units,
    if (price != null) 'p': price,
  };

  factory SnapshotItem.fromMap(Map<String, Object?> m) => SnapshotItem(
    value: _d(m['v']) ?? 0,
    invested: _d(m['i']) ?? 0,
    units: _d(m['u']),
    price: _d(m['p']),
  );
}

/// What every open holding was worth at the end of a day.
///
/// Stocks, gold and hand-updated balances (PPF, EPF, NPS…) have no free price
/// history, so period returns for them are worked out from these. Stored at
/// `users/{uid}/snapshots/{yyyy-MM-dd}`, one per day (later saves that day
/// replace earlier ones).
class ValueSnapshot {
  const ValueSnapshot({required this.date, required this.items});

  final DateTime date;

  /// By investment id.
  final Map<String, SnapshotItem> items;

  String get docId => toIsoDate(date);

  Map<String, Object?> toMap() => {
    'date': toIsoDate(date),
    'items': {for (final e in items.entries) e.key: e.value.toMap()},
  };

  factory ValueSnapshot.fromMap(Map<String, Object?> m) {
    final raw = m['items'];
    return ValueSnapshot(
      date: fromIsoDate(m['date']) ?? DateTime(1970),
      items: {
        if (raw is Map)
          for (final e in raw.entries)
            if (e.value is Map)
              e.key as String: SnapshotItem.fromMap(
                Map<String, Object?>.from(e.value as Map),
              ),
      },
    );
  }

  /// Today's snapshot of [investments] (closed ones are left out).
  factory ValueSnapshot.of(Iterable<Investment> investments, DateTime today) {
    final day = dateOnly(today);
    return ValueSnapshot(
      date: day,
      items: {
        for (final inv in investments)
          if (!inv.isClosed) inv.id: _itemOf(inv, day),
      },
    );
  }

  static SnapshotItem _itemOf(Investment inv, DateTime day) {
    final v = valuationOf(inv, day);
    final market = inv.type.kind == ValuationKind.market;
    return SnapshotItem(
      value: v.current,
      invested: v.invested,
      units: market ? inv.units : null,
      price: market ? (inv.currentPrice ?? inv.avgCost) : null,
    );
  }
}

double? _d(Object? v) => v is num ? v.toDouble() : null;
