import 'package:flutter_test/flutter_test.dart';
import 'package:invest_tracker/core/dates.dart';
import 'package:invest_tracker/logic/ais_match.dart';
import 'package:invest_tracker/logic/ais_parser.dart';
import 'package:invest_tracker/logic/ais_pdf.dart';
import 'package:invest_tracker/models/ais.dart';
import 'package:invest_tracker/models/investment.dart';
import 'package:invest_tracker/models/member.dart';

import 'support/ais_fixture.dart';

void main() {
  group('AIS PDF', () {
    late final bytes = buildAisFixturePdf();

    test('reads every part of the statement', () {
      final r = readAisPdf(bytes, password: fixturePassword);
      expect(r.looksLikeAis, isTrue);
      expect(r.year, const TaxYear(2026));

      final salary = r.records.firstWhere((x) => x.code == 'TDS-392');
      expect(salary.part, 'B1');
      expect(salary.description, 'Salary received (Section 392)');
      expect(salary.source, 'ACME STEEL LIMITED');
      expect(salary.tan, 'MUMA12345B');
      expect(salary.count, 2);
      expect(salary.amount, 364812);
      expect(salary.entries, hasLength(2));
      expect(salary.entries.first.quarter, 'Q2(Jul-Sep)');
      expect(salary.entries.first.date, DateTime(2026, 9, 30));
      expect(salary.entries.first.amount, 179900);
      expect(salary.tdsDeducted, 17483 + 16803);
      expect(salary.isSalary, isTrue);

      // Description and source wrapped onto a second line.
      final interest = r.records.firstWhere((x) => x.code == 'TDS-393');
      expect(
        interest.description,
        'Interest other than interest on securities (Section 393)',
      );
      expect(interest.source, 'STATE BANK OF INDIA');
      expect(interest.tan, 'BLRS12345C');
      expect(interest.isInterest, isTrue);
      expect(interest.tdsDeducted, 1775);
      expect(interest.lastDate, DateTime(2026, 9, 30));

      final sft = r.records.firstWhere((x) => x.part == 'B2');
      expect(sft.code, 'SFT-016(SB)');
      expect(sft.source, 'CANARA BANK');
      expect(sft.amount, 2340);
      expect(sft.isInterest, isTrue);

      expect(r.payments.single.amount, 15000);
      expect(r.payments.single.label, 'Advance tax');
      expect(r.payments.single.date, DateTime(2026, 9, 14));

      expect(r.refunds.single.forYear, '2025-26');
      expect(r.refunds.single.amount, 61480);
      expect(r.refunds.single.date, DateTime(2026, 10, 30));

      final st = r.toStatement('m1');
      expect(st.totalTds, 17483 + 16803 + 1775);
      expect(st.docId, 'm1_2026');
      expect(AisStatement.fromMap(st.toMap()).toMap(), st.toMap());
    });

    test('password errors', () {
      expect(
        () => readAisPdf(bytes, password: 'wrong'),
        throwsA(
          isA<AisPdfException>().having(
            (e) => e.error,
            'error',
            AisPdfError.wrongPassword,
          ),
        ),
      );
      expect(() => readAisPdf(bytes), throwsA(isA<AisPdfException>()));
    });

    test('password from PAN and date of birth', () {
      final m = Member(
        id: 'x',
        name: 'X',
        pan: 'ABCDE1234F',
        dateOfBirth: DateTime(1960, 1, 1),
      );
      expect(aisPasswordFor(m), fixturePassword);
      expect(aisPasswordFor(const Member(id: 'y', name: 'Y')), isNull);
    });
  });

  group('line grouping', () {
    test('groups by row, orders by x and drops watermarks', () {
      final lines = groupIntoLines(const [
        PdfWord('b', 50, 10.5),
        PdfWord('a', 10, 10),
        PdfWord('c', 10, 30),
        PdfWord('WATERMARK', 10, 8, height: 30),
      ]);
      expect(lines.map((l) => l.map((w) => w.text).join(' ')), ['a b', 'c']);
    });
  });

  group('matching banks', () {
    test('names and acronyms', () {
      expect(sameInstitution('SBI', 'STATE BANK OF INDIA'), isTrue);
      expect(sameInstitution('HDFC Bank', 'HDFC BANK LIMITED'), isTrue);
      expect(sameInstitution('Canara', 'CANARA BANK'), isTrue);
      expect(sameInstitution('PNB', 'PUNJAB NATIONAL BANK'), isTrue);
      expect(sameInstitution('BOB', 'BANK OF BARODA'), isTrue);
      expect(sameInstitution('Post Office', 'DEPARTMENT OF POSTS'), isTrue);
      expect(sameInstitution('Union Bank', 'UNION BANK OF INDIA'), isTrue);
      expect(sameInstitution('SBI', 'HDFC BANK LIMITED'), isFalse);
      expect(sameInstitution('Canara Bank', 'CANFIN HOMES LIMITED'), isFalse);
      expect(sameInstitution('Bank', 'STATE BANK OF INDIA'), isFalse);
    });

    test('app interest vs AIS, counted to the same date', () {
      final st = readAisPdf(
        buildAisFixturePdf(),
        password: fixturePassword,
      ).toStatement('m1');
      final investments = [
        // 5,00,000 at 7.1% simple ≈ ₹17,800 for Apr–Sep: matches AIS ₹17,750.
        Investment(
          id: 'sbi',
          memberId: 'm1',
          type: AssetType.fixedDeposit,
          name: 'SBI FD',
          institution: 'SBI',
          principal: 500000,
          ratePct: 7.1,
          startDate: DateTime(2025, 6, 1),
          maturityDate: DateTime(2028, 6, 1),
          payout: Payout.quarterly,
          tdsApplicable: true,
        ),
        Investment(
          id: 'hdfc',
          memberId: 'm1',
          type: AssetType.fixedDeposit,
          name: 'HDFC FD',
          institution: 'HDFC Bank',
          principal: 200000,
          ratePct: 7,
          startDate: DateTime(2026, 4, 1),
          maturityDate: DateTime(2027, 4, 1),
          tdsApplicable: true,
        ),
        // Someone else's deposit is ignored.
        Investment(
          id: 'other',
          memberId: 'm2',
          type: AssetType.fixedDeposit,
          name: 'SBI FD',
          institution: 'SBI',
          principal: 900000,
          ratePct: 7,
          startDate: DateTime(2026, 4, 1),
          maturityDate: DateTime(2027, 4, 1),
        ),
      ];
      final res = compareInterest(
        statement: st,
        investments: investments,
        today: DateTime(2026, 11, 18),
      );
      final sbi = res.firstWhere((c) => c.payer == 'SBI');
      expect(sbi.check, InterestCheck.matches);
      expect(sbi.upTo, DateTime(2026, 9, 30));
      expect(sbi.appInterest, closeTo(17800, 100));
      expect(sbi.aisInterest, 17750);
      expect(sbi.aisTds, 1775);

      expect(
        res.firstWhere((c) => c.payer == 'HDFC Bank').check,
        InterestCheck.notInAis,
      );
      final canara = res.firstWhere((c) => c.payer == 'CANARA BANK');
      expect(canara.check, InterestCheck.notInApp);
      expect(canara.aisInterest, 2340);
    });
  });
}
