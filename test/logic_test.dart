import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/core/dates.dart';
import 'package:invest_tracker/core/money.dart';
import 'package:invest_tracker/logic/amfi.dart';
import 'package:invest_tracker/logic/deposit_math.dart';
import 'package:invest_tracker/logic/interest_report.dart';
import 'package:invest_tracker/logic/upcoming_events.dart';
import 'package:invest_tracker/logic/valuation.dart';
import 'package:invest_tracker/models/investment.dart';
import 'package:invest_tracker/models/member.dart';

Investment fd({
  String id = 'fd',
  String member = 'm1',
  String bank = 'SBI',
  double principal = 100000,
  double rate = 7,
  required DateTime start,
  required DateTime maturity,
  Compounding compounding = Compounding.quarterly,
  Payout payout = Payout.cumulative,
  bool tds = true,
  bool form15 = false,
}) => Investment(
  id: id,
  memberId: member,
  type: AssetType.fixedDeposit,
  name: '$bank FD',
  institution: bank,
  principal: principal,
  ratePct: rate,
  startDate: start,
  maturityDate: maturity,
  compounding: compounding,
  payout: payout,
  tdsApplicable: tds,
  form15Submitted: form15,
);

void main() {
  group('money formatting', () {
    test('Indian digit grouping', () {
      expect(formatInr(0), '₹0');
      expect(formatInr(999), '₹999');
      expect(formatInr(1000), '₹1,000');
      expect(formatInr(100000), '₹1,00,000');
      expect(formatInr(8642310), '₹86,42,310');
      expect(formatInr(123456789), '₹12,34,56,789');
      expect(formatInr(274.912, decimals: 2), '₹274.91');
    });

    test('signs', () {
      expect(formatInr(1827310, showSign: true), '+₹18,27,310');
      expect(formatInr(-50000), '−₹50,000');
      expect(formatInr(0, showSign: true), '₹0');
    });

    test('compact', () {
      expect(formatInrCompact(85000), '₹85,000');
      expect(formatInrCompact(1241000), '₹12.41 L');
      expect(formatInrCompact(1240500), '₹12.4 L');
      expect(formatInrCompact(500000), '₹5 L');
      expect(formatInrCompact(12500000), '₹1.25 Cr');
    });

    test('parse user input', () {
      expect(parseAmount('1,50,000'), 150000);
      expect(parseAmount(' ₹ 2500.50 '), 2500.5);
      expect(parseAmount(''), isNull);
      expect(parseAmount('abc'), isNull);
    });
  });

  group('dates', () {
    test('tax year', () {
      expect(TaxYear.of(DateTime(2026, 11, 17)).label, '2026-27');
      expect(TaxYear.of(DateTime(2027, 3, 31)).label, '2026-27');
      expect(TaxYear.of(DateTime(2027, 4, 1)).label, '2027-28');
      expect(TaxYear.of(DateTime(2026, 1, 5)).label, '2025-26');
      expect(const TaxYear(2099).label, '2099-00');
    });

    test('addMonths clamps the day', () {
      expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
      expect(addMonths(DateTime(2028, 1, 31), 1), DateTime(2028, 2, 29));
      expect(addMonths(DateTime(2026, 11, 15), 3), DateTime(2027, 2, 15));
    });

    test('senior citizen for a tax year', () {
      final turns60InMarch = Member(
        id: 'a',
        name: 'A',
        dateOfBirth: DateTime(1967, 3, 20),
      );
      expect(turns60InMarch.isSeniorIn(const TaxYear(2026)), isTrue);
      final turns60InApril = Member(
        id: 'b',
        name: 'B',
        dateOfBirth: DateTime(1967, 4, 2),
      );
      expect(turns60InApril.isSeniorIn(const TaxYear(2026)), isFalse);
      expect(
        const Member(id: 'c', name: 'C').isSeniorIn(const TaxYear(2026)),
        isFalse,
      );
    });
  });

  group('deposit maths', () {
    test('cumulative FD, quarterly compounding, 1 year', () {
      final inv = fd(
        start: DateTime(2025, 1, 1),
        maturity: DateTime(2026, 1, 1),
      );
      // 1,00,000 × (1 + 0.07/4)^4 = 1,07,185.90
      expect(DepositMath.maturityValue(inv), closeTo(107185.90, 0.5));
      expect(
        DepositMath.valueOn(inv, DateTime(2030)),
        closeTo(107185.90, 0.5),
        reason: 'value stops growing after maturity',
      );
      expect(DepositMath.investedOn(inv, DateTime(2025, 6, 1)), 100000);
    });

    test('interest split across tax years adds up to the total', () {
      final inv = fd(
        principal: 500000,
        rate: 7.1,
        start: DateTime(2025, 10, 1),
        maturity: DateTime(2027, 10, 1),
      );
      final total = DepositMath.interestEarnedUntil(inv, inv.maturityDate!);
      final parts = [2025, 2026, 2027]
          .map(
            (y) => DepositMath.interestBetween(
              inv,
              TaxYear(y).start,
              TaxYear(y).end,
            ),
          )
          .fold(0.0, (a, b) => a + b);
      expect(parts, closeTo(total, 0.01));
      expect(
        DepositMath.interestBetween(
          inv,
          const TaxYear(2024).start,
          const TaxYear(2024).end,
        ),
        0,
      );
    });

    test('payout FD keeps value at principal and pays simple interest', () {
      final inv = fd(
        principal: 400000,
        rate: 7.25,
        start: DateTime(2026, 3, 14),
        maturity: DateTime(2027, 3, 14),
        payout: Payout.quarterly,
      );
      expect(DepositMath.valueOn(inv, DateTime(2026, 11, 1)), 400000);
      expect(
        DepositMath.interestEarnedUntil(inv, inv.maturityDate!),
        closeTo(29000, 1),
      );
      final next = DepositMath.nextPayout(inv, DateTime(2026, 11, 17))!;
      expect(next.$1, DateTime(2026, 12, 14));
      expect(next.$2, closeTo(7250, 0.01));
    });

    test('recurring deposit', () {
      final rd = Investment(
        id: 'rd',
        memberId: 'm1',
        type: AssetType.recurringDeposit,
        name: 'RD',
        monthlyInstalment: 1000,
        ratePct: 6.5,
        startDate: DateTime(2025, 1, 10),
        maturityDate: DateTime(2026, 1, 10),
      );
      expect(DepositMath.rdInstalments(rd), 12);
      expect(DepositMath.investedOn(rd, DateTime(2025, 3, 10)), 3000);
      expect(DepositMath.investedOn(rd, DateTime(2027)), 12000);
      // Banks quote about ₹12,430 for this RD.
      expect(DepositMath.maturityValue(rd), closeTo(12430, 15));
    });

    test('simple interest', () {
      final inv = fd(
        start: DateTime(2025, 1, 1),
        maturity: DateTime(2027, 1, 1),
        compounding: Compounding.simple,
      );
      expect(DepositMath.maturityValue(inv), closeTo(114000, 30));
    });
  });

  group('valuation', () {
    test('market holding', () {
      const inv = Investment(
        id: 'mf',
        memberId: 'm1',
        type: AssetType.mutualFund,
        name: 'Index fund',
        units: 4512.318,
        avgCost: 209.2,
        currentPrice: 274.91,
      );
      final v = valuationOf(inv, DateTime(2026, 11, 17));
      expect(v.invested, closeTo(943977, 1));
      expect(v.current, closeTo(1240481, 1));
      expect(v.gainPct, closeTo(31.41, 0.01));
    });

    test('closed holdings are left out of totals', () {
      const a = Investment(
        id: 'a',
        memberId: 'm',
        type: AssetType.ppf,
        name: 'PPF',
        investedAmount: 100,
        currentValue: 150,
      );
      const b = Investment(
        id: 'b',
        memberId: 'm',
        type: AssetType.ppf,
        name: 'Old PPF',
        investedAmount: 100,
        currentValue: 150,
        isClosed: true,
      );
      final total = totalValuation([a, b], DateTime(2026));
      expect(total.current, 150);
      expect(total.invested, 100);
    });

    test('map round trip', () {
      final inv = fd(
        start: DateTime(2025, 1, 1),
        maturity: DateTime(2026, 1, 1),
        form15: true,
      );
      final back = Investment.fromMap('fd', inv.toMap());
      expect(back.toMap(), inv.toMap());
      final m = Member(
        id: 'x',
        name: 'Asha',
        pan: 'ABCDE1234F',
        dateOfBirth: DateTime(1960, 5, 6),
      );
      expect(Member.fromMap('x', m.toMap()).toMap(), m.toMap());
      expect(m.maskedPan, 'ABC••••34F');
    });
  });

  group('interest & TDS report', () {
    const fy = TaxYear(2026);
    final members = [
      const Member(id: 'young', name: 'Ravi'),
      Member(id: 'senior', name: 'Asha', dateOfBirth: DateTime(1958, 1, 1)),
    ];

    test('interest from the same bank is added up for the TDS limit', () {
      final items = [
        fd(
          id: 'a',
          member: 'young',
          principal: 400000,
          rate: 7,
          start: DateTime(2026, 4, 1),
          maturity: DateTime(2028, 4, 1),
        ),
        fd(
          id: 'b',
          member: 'young',
          principal: 400000,
          rate: 7,
          start: DateTime(2026, 4, 1),
          maturity: DateTime(2028, 4, 1),
        ),
        fd(
          id: 'c',
          member: 'young',
          bank: 'HDFC Bank',
          principal: 100000,
          rate: 7,
          start: DateTime(2026, 4, 1),
          maturity: DateTime(2028, 4, 1),
        ),
      ];
      final r = buildInterestReport(
        investments: items,
        members: members,
        year: fy,
      );
      final sbi = r.payers.firstWhere((p) => p.payer == 'SBI');
      expect(sbi.items, hasLength(2));
      expect(sbi.interest, greaterThan(50000));
      expect(sbi.crossesThreshold, isTrue);
      expect(sbi.expectedTds, closeTo(sbi.interest * 0.10, 0.01));
      final hdfc = r.payers.firstWhere((p) => p.payer == 'HDFC Bank');
      expect(hdfc.crossesThreshold, isFalse);
      expect(hdfc.expectedTds, 0);
      expect(r.expectedTds, sbi.expectedTds);
    });

    test('seniors get the ₹1 lakh limit; 15H removes TDS', () {
      final big = fd(
        id: 'a',
        member: 'senior',
        principal: 1100000,
        rate: 7.5,
        start: DateTime(2026, 4, 1),
        maturity: DateTime(2028, 4, 1),
      );
      var r = buildInterestReport(
        investments: [big],
        members: members,
        year: fy,
      );
      expect(r.payers.single.threshold, 100000);
      expect(r.payers.single.nearThreshold, isTrue);
      expect(r.payers.single.expectedTds, 0);

      final huge = fd(
        id: 'b',
        member: 'senior',
        principal: 2000000,
        rate: 7.5,
        start: DateTime(2026, 4, 1),
        maturity: DateTime(2028, 4, 1),
        form15: true,
      );
      r = buildInterestReport(investments: [huge], members: members, year: fy);
      expect(r.payers.single.crossesThreshold, isTrue);
      expect(r.payers.single.expectedTds, 0);
    });

    test('PPF interest is listed as tax-free', () {
      const ppf = Investment(
        id: 'p',
        memberId: 'young',
        type: AssetType.ppf,
        name: 'PPF',
        investedAmount: 800000,
        currentValue: 1000000,
        ratePct: 7.1,
      );
      final r = buildInterestReport(
        investments: [ppf],
        members: members,
        year: fy,
      );
      expect(r.payers, isEmpty);
      expect(r.taxFreeTotal, closeTo(71000, 0.01));
    });
  });

  group('AMFI NAV file', () {
    const sample = '''
Scheme Code;ISIN Div Payout/ ISIN Growth;ISIN Div Reinvestment;Scheme Name;Net Asset Value;Date

Open Ended Schemes(Equity Scheme - Flexi Cap Fund)

Example Mutual Fund

120000;INF000A01AA1;-;Example Flexi Cap Fund - Direct Plan - Growth;85.4321;17-Nov-2026
120001;INF000A01AB9;INF000A01AC7;Example Flexi Cap Fund - Regular Plan - IDCW;31.0100;17-Nov-2026
120002;INF000A01AD5;-;Example Closed Fund - Direct Plan - Growth;N.A.;17-Nov-2026

Other Mutual Fund

130000;INF111B01AA0;-;Other Nifty 50 Index Fund - Direct Plan - Growth;274.91;14-Nov-2026
''';

    test('parses schemes with fund house and skips bad rows', () {
      final list = parseNavAll(sample);
      expect(list, hasLength(3));
      expect(list.first.code, '120000');
      expect(list.first.nav, 85.4321);
      expect(list.first.date, DateTime(2026, 11, 17));
      expect(list.first.fundHouse, 'Example Mutual Fund');
      expect(list.first.category, contains('Flexi Cap'));
      expect(list.last.fundHouse, 'Other Mutual Fund');
    });

    test('search matches all words', () {
      final list = parseNavAll(sample);
      expect(searchSchemes(list, 'flexi direct').map((s) => s.code), [
        '120000',
      ]);
      expect(searchSchemes(list, 'nifty'), hasLength(1));
      expect(searchSchemes(list, '130000'), hasLength(1));
      expect(searchSchemes(list, '  '), isEmpty);
    });
  });

  group('upcoming events', () {
    final today = DateTime(2026, 11, 17);

    test('maturities, SIPs and overdue deposits', () {
      final soon = fd(
        id: 'soon',
        principal: 500000,
        rate: 7.1,
        start: DateTime(2025, 11, 28),
        maturity: DateTime(2026, 11, 28),
      );
      final old = fd(
        id: 'old',
        start: DateTime(2024, 1, 1),
        maturity: DateTime(2025, 1, 1),
      );
      const sip = Investment(
        id: 'sip',
        memberId: 'm1',
        type: AssetType.mutualFund,
        name: 'Index fund',
        sipAmount: 10000,
        sipDay: 20,
      );
      final events = upcomingEvents(
        [soon, old, sip],
        today,
        days: 30,
        includeTaxDates: false,
      );
      expect(events.map((e) => e.kind), [
        EventKind.overdueMaturity,
        EventKind.sip,
        EventKind.maturity,
      ]);
      expect(events[1].date, DateTime(2026, 11, 20));
      expect(events[2].amount, closeTo(536500, 1000));
    });

    test('SIP day rolls to next month and clamps', () {
      expect(
        nextMonthlyDate(DateTime(2026, 11, 21), 20),
        DateTime(2026, 12, 20),
      );
      expect(nextMonthlyDate(DateTime(2027, 2, 1), 31), DateTime(2027, 2, 28));
    });

    test('tax dates in the window', () {
      final dates = taxDates(
        today,
        DateTime(2027, 4, 30),
      ).map((e) => e.date).toList();
      expect(
        dates,
        containsAll([
          DateTime(2026, 12, 15),
          DateTime(2026, 12, 31),
          DateTime(2027, 3, 15),
          DateTime(2027, 3, 31),
          DateTime(2027, 4, 10),
        ]),
      );
      expect(dates.every((d) => !d.isBefore(today)), isTrue);
    });
  });
}
