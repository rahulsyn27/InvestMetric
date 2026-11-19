import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/data/repository.dart';
import 'package:invest_tracker/logic/deposit_math.dart';
import 'package:invest_tracker/logic/nav_history.dart';
import 'package:invest_tracker/logic/returns.dart';
import 'package:invest_tracker/models/investment.dart';
import 'package:invest_tracker/models/snapshot.dart';

final today = DateTime(2026, 11, 17);

Investment fd({
  String id = 'fd',
  DateTime? start,
  Payout payout = Payout.cumulative,
}) => Investment(
  id: id,
  memberId: 'self',
  type: AssetType.fixedDeposit,
  name: 'SBI FD',
  institution: 'SBI',
  principal: 100000,
  ratePct: 7,
  startDate: start ?? DateTime(2025, 1, 1),
  maturityDate: DateTime(2030, 1, 1),
  payout: payout,
);

Investment fund({
  DateTime? start,
  double units = 100,
  String? code = '119551',
}) => Investment(
  id: 'mf',
  memberId: 'self',
  type: AssetType.mutualFund,
  name: 'Index Fund',
  units: units,
  avgCost: 100,
  currentPrice: 150,
  schemeCode: code,
  startDate: start,
);

void main() {
  group('periods', () {
    test('start dates', () {
      expect(ReturnPeriod.oneMonth.startFor(today), DateTime(2026, 10, 17));
      expect(ReturnPeriod.threeMonths.startFor(today), DateTime(2026, 8, 17));
      expect(ReturnPeriod.sixMonths.startFor(today), DateTime(2026, 5, 17));
      expect(ReturnPeriod.oneYear.startFor(today), DateTime(2025, 11, 17));
      expect(ReturnPeriod.taxYear.startFor(today), DateTime(2026, 4, 1));
      expect(ReturnPeriod.allTime.startFor(today), isNull);
    });
  });

  group('deposits', () {
    test('held all period: gain is the interest for the period', () {
      final inv = fd();
      final from = DateTime(2025, 11, 17);
      final r = periodReturn([inv], ReturnPeriod.oneYear, today);
      expect(r.leftOut, isEmpty);
      expect(
        r.interest,
        closeTo(DepositMath.interestBetween(inv, from, today), 0.01),
      );
      expect(r.marketChange, 0);
      expect(r.added, 0);
      expect(r.startValue, closeTo(DepositMath.valueOn(inv, from), 0.01));
      expect(r.gainPct, closeTo(r.gain / r.startValue * 100, 1e-9));
      // About 7% a year compounded quarterly.
      expect(r.gainPct, closeTo(7.19, 0.05));
    });

    test('opened during the period counts the principal as added', () {
      final inv = fd(start: DateTime(2026, 5, 17));
      final r = periodReturn([inv], ReturnPeriod.oneYear, today);
      expect(r.startValue, 0);
      expect(r.added, 100000);
      // Invested for half of the year, so the base is about half.
      expect(r.total.weightedAdded, closeTo(100000 * 184 / 365, 1));
      // Half a year at 7% is ~3.5% of the money, ~7% of the weighted base.
      expect(r.gainPct, closeTo(7.1, 0.2));
    });

    test('payout deposits: interest paid out is part of the gain', () {
      final inv = fd(payout: Payout.quarterly);
      final r = periodReturn([inv], ReturnPeriod.oneYear, today);
      expect(r.endValue, 100000);
      expect(r.startValue, 100000);
      expect(r.interest, closeTo(7000, 1));
      expect(r.paidOut, closeTo(r.interest, 0.01));
    });

    test('RD instalments in the period are money added', () {
      final rd = Investment(
        id: 'rd',
        memberId: 'self',
        type: AssetType.recurringDeposit,
        name: 'RD',
        monthlyInstalment: 5000,
        ratePct: 6.5,
        startDate: DateTime(2026, 1, 5),
        maturityDate: DateTime(2028, 1, 5),
      );
      final r = periodReturn([rd], ReturnPeriod.threeMonths, today);
      // 5 Sep, 5 Oct, 5 Nov.
      expect(r.added, 15000);
      expect(r.interest, greaterThan(0));
      expect(r.endValue - r.startValue - r.added, closeTo(r.interest, 0.01));
    });
  });

  group('mutual funds', () {
    test('market change from the AMFI NAV at the start', () {
      final inputs = ReturnInputs(
        navs: {'119551': (nav: 120.0, date: DateTime(2026, 10, 16))},
      );
      final r = periodReturn([fund()], ReturnPeriod.oneMonth, today, inputs);
      expect(r.startValue, 12000);
      expect(r.endValue, 15000);
      expect(r.marketChange, 3000);
      expect(r.interest, 0);
      expect(r.gainPct, closeTo(25, 1e-9));
    });

    test('left out without a NAV or a snapshot', () {
      final r = periodReturn([fund()], ReturnPeriod.oneMonth, today);
      expect(r.leftOut.map((i) => i.id), ['mf']);
      expect(r.isEmpty, isTrue);
    });

    test('NAV codes are only needed for funds held before the start', () {
      final from = DateTime(2026, 10, 17);
      expect(navCodesNeeded([fund()], from), {'119551'});
      expect(
        navCodesNeeded([fund(start: DateTime(2026, 11, 1))], from),
        isEmpty,
      );
      expect(navCodesNeeded([fund(code: null)], from), isEmpty);
    });

    test('bought during the period starts from the cost', () {
      final r = periodReturn(
        [fund(start: DateTime(2026, 11, 1))],
        ReturnPeriod.oneMonth,
        today,
      );
      expect(r.leftOut, isEmpty);
      expect(r.startValue, 0);
      expect(r.added, 10000);
      expect(r.marketChange, 5000);
    });

    test('a snapshot gives the units held then (SIP top-ups)', () {
      final snap = ValueSnapshot(
        date: DateTime(2026, 10, 15),
        items: {
          'mf': const SnapshotItem(
            value: 9000,
            invested: 8000,
            units: 80,
            price: 112.5,
          ),
        },
      );
      final inputs = ReturnInputs(
        navs: {'119551': (nav: 120.0, date: DateTime(2026, 10, 16))},
        snapshot: snap,
      );
      final r = periodReturn([fund()], ReturnPeriod.oneMonth, today, inputs);
      // 80 units at the AMFI NAV of 120; 20 more units (₹2,000) bought since.
      expect(r.startValue, 9600);
      expect(r.added, 2000);
      expect(r.marketChange, 15000 - 9600 - 2000);
    });
  });

  group('stocks and balances use snapshots', () {
    test('stock price from the snapshot', () {
      const stock = Investment(
        id: 'eq',
        memberId: 'self',
        type: AssetType.stock,
        name: 'Infosys',
        units: 10,
        avgCost: 1500,
        currentPrice: 1800,
      );
      final snap = ValueSnapshot(
        date: DateTime(2026, 10, 10),
        items: {
          'eq': const SnapshotItem(
            value: 16000,
            invested: 15000,
            units: 10,
            price: 1600,
          ),
        },
      );
      final r = periodReturn(
        [stock],
        ReturnPeriod.oneMonth,
        today,
        ReturnInputs(snapshot: snap),
      );
      expect(r.marketChange, 2000);
      expect(r.gainPct, closeTo(12.5, 1e-9));
      expect(periodReturn([stock], ReturnPeriod.oneMonth, today).leftOut, [
        stock,
      ]);
    });

    test('PPF growth counts as interest; contributions are money added', () {
      const ppf = Investment(
        id: 'ppf',
        memberId: 'self',
        type: AssetType.ppf,
        name: 'PPF',
        investedAmount: 160000,
        currentValue: 200000,
      );
      final snap = ValueSnapshot(
        date: DateTime(2026, 4, 1),
        items: {'ppf': const SnapshotItem(value: 180000, invested: 150000)},
      );
      final r = periodReturn(
        [ppf],
        ReturnPeriod.taxYear,
        today,
        ReturnInputs(snapshot: snap),
      );
      expect(r.added, 10000);
      expect(r.interest, 10000);
      expect(r.marketChange, 0);
    });
  });

  test('all time: gain on everything put in, closed ones left out', () {
    final r = periodReturn(
      [
        fund(),
        fd(payout: Payout.quarterly),
        const Investment(
          id: 'old',
          memberId: 'self',
          type: AssetType.stock,
          name: 'Sold',
          units: 1,
          avgCost: 10,
          isClosed: true,
        ),
      ],
      ReturnPeriod.allTime,
      today,
    );
    expect(r.included, 2);
    expect(r.added, 110000);
    expect(r.marketChange, 5000);
    expect(r.interest, closeTo(100000 * 0.07 * 685 / 365, 1));
    expect(r.gainPct, closeTo(r.gain / 110000 * 100, 1e-9));
  });

  group('AMFI NAV history', () {
    const sample = '''
Scheme Code;NAV Name;Plan;Option;ISIN Div Payout/ISIN Growth;ISIN Div Reinvestment;Net Asset Value;Date

Open Ended Schemes ( Debt Scheme - Banking and PSU Fund )

Aditya Birla Sun Life Mutual Fund
119551;Aditya Birla Sun Life Banking & PSU Debt Fund  - DIRECT - IDCW;Direct Plan;IDCW;INF209KA12Z1;INF209KA13Z9;106.7921;16-Oct-2026
120000;Other Fund;Direct Plan;Growth;INF000;;N.A.;16-Oct-2026
''';

    test('reads only the codes asked for', () {
      final m = parseNavHistory(sample, {'119551', '120000', '999'});
      expect(m.keys, ['119551']);
      expect(m['119551']!.nav, 106.7921);
      expect(m['119551']!.date, DateTime(2026, 10, 16));
    });

    test('steps back over weekends', () async {
      final asked = <DateTime>[];
      final m = await fetchNavsOn(
        DateTime(2026, 10, 18), // Sunday
        {'119551'},
        fetch: (day) async {
          asked.add(day);
          return day == DateTime(2026, 10, 16) ? sample : 'no data';
        },
      );
      expect(m['119551']!.nav, 106.7921);
      expect(asked, [
        DateTime(2026, 10, 18),
        DateTime(2026, 10, 17),
        DateTime(2026, 10, 16),
      ]);
    });

    test('gives up after a week', () async {
      var calls = 0;
      final m = await fetchNavsOn(
        DateTime(2026, 10, 18),
        {'119551'},
        fetch: (_) async {
          calls++;
          return '';
        },
      );
      expect(m, isEmpty);
      expect(calls, 8);
    });
  });

  group('snapshots', () {
    test('round trip and only open holdings', () {
      final s = ValueSnapshot.of([
        fund(),
        fd(),
        fd(id: 'x').copyWith(isClosed: true),
      ], today);
      expect(s.docId, '2026-11-17');
      expect(s.items.keys, unorderedEquals(['mf', 'fd']));
      expect(s.items['mf']!.units, 100);
      expect(s.items['mf']!.price, 150);
      expect(s.items['fd']!.units, isNull);
      final back = ValueSnapshot.fromMap(s.toMap());
      expect(back.date, today);
      expect(back.items['mf']!.value, 15000);
      expect(back.items['fd']!.invested, 100000);
    });

    test('latest on or before a date', () async {
      final repo = InMemoryRepository(
        snapshots: [
          ValueSnapshot(date: DateTime(2026, 10, 1), items: const {}),
          ValueSnapshot(date: DateTime(2026, 10, 20), items: const {}),
        ],
      );
      expect((await repo.snapshotOnOrBefore(DateTime(2026, 9, 30))), isNull);
      expect(
        (await repo.snapshotOnOrBefore(DateTime(2026, 10, 17)))!.date,
        DateTime(2026, 10, 1),
      );
      expect(
        (await repo.snapshotOnOrBefore(DateTime(2026, 10, 20)))!.date,
        DateTime(2026, 10, 20),
      );
    });
  });
}
