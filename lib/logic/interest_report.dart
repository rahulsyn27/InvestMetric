import '../core/dates.dart';
import '../core/tax_rules.dart';
import '../models/investment.dart';
import '../models/member.dart';
import 'deposit_math.dart';

/// Interest one member earns from one bank / payer in a tax year, and the TDS
/// that bank is likely to deduct.
class PayerInterest {
  PayerInterest({
    required this.memberId,
    required this.payer,
    required this.items,
    required this.interest,
    required this.threshold,
    required this.tdsApplicable,
    required this.form15Submitted,
  });

  final String memberId;
  final String payer;
  final List<(Investment, double)> items;
  final double interest;
  final double threshold;

  /// At least one deposit here normally has TDS deducted.
  final bool tdsApplicable;

  /// Form 15G/15H given for every deposit at this payer.
  final bool form15Submitted;

  bool get crossesThreshold => tdsApplicable && interest > threshold;

  /// Expected TDS for the year (0 if under the limit or 15G/15H given).
  double get expectedTds => crossesThreshold && !form15Submitted
      ? interest * TaxRules.interestTdsRate
      : 0;

  /// Close to the limit (80%+) but not over: a good time to think about 15G/15H.
  bool get nearThreshold =>
      tdsApplicable && !crossesThreshold && interest >= threshold * 0.8;
}

class InterestReport {
  InterestReport({
    required this.year,
    required this.payers,
    required this.taxFreeInterest,
  });

  final TaxYear year;
  final List<PayerInterest> payers;

  /// PPF / EPF interest (estimated from balance × rate).
  final List<(Investment, double)> taxFreeInterest;

  double get taxableInterest => payers.fold(0, (s, p) => s + p.interest);
  double get expectedTds => payers.fold(0, (s, p) => s + p.expectedTds);
  double get taxFreeTotal => taxFreeInterest.fold(0, (s, e) => s + e.$2);
}

String _payerKey(Investment i) {
  final p = i.institution.trim().isEmpty ? i.name.trim() : i.institution.trim();
  return p.toLowerCase();
}

/// Builds the interest picture for [year]. Closed deposits still count for
/// the interest they earned in that year.
InterestReport buildInterestReport({
  required Iterable<Investment> investments,
  required Iterable<Member> members,
  required TaxYear year,
}) {
  final membersById = {for (final m in members) m.id: m};
  final groups = <String, List<(Investment, double)>>{};
  final taxFree = <(Investment, double)>[];

  for (final inv in investments) {
    if (inv.type.kind == ValuationKind.deposit) {
      final interest = DepositMath.interestBetween(inv, year.start, year.end);
      if (interest <= 0) continue;
      final key = '${inv.memberId}|${_payerKey(inv)}';
      groups.putIfAbsent(key, () => []).add((inv, interest));
    } else if (inv.type.interestTaxFree && !inv.isClosed) {
      final rate = inv.ratePct;
      final balance = inv.currentValue ?? inv.investedAmount;
      if (rate != null && balance != null && balance > 0) {
        taxFree.add((inv, balance * rate / 100));
      }
    }
  }

  final payers = <PayerInterest>[];
  for (final entry in groups.entries) {
    final items = entry.value;
    final first = items.first.$1;
    final member = membersById[first.memberId];
    final senior = member?.isSeniorIn(year) ?? false;
    final tdsItems = items.where((e) => e.$1.tdsApplicable).toList();
    payers.add(
      PayerInterest(
        memberId: first.memberId,
        payer: first.institution.trim().isEmpty
            ? first.name
            : first.institution.trim(),
        items: items,
        interest: items.fold(0.0, (s, e) => s + e.$2),
        threshold: senior
            ? TaxRules.interestTdsThresholdSenior
            : TaxRules.interestTdsThreshold,
        tdsApplicable: tdsItems.isNotEmpty,
        form15Submitted:
            tdsItems.isNotEmpty && tdsItems.every((e) => e.$1.form15Submitted),
      ),
    );
  }
  payers.sort((a, b) => b.interest.compareTo(a.interest));
  return InterestReport(year: year, payers: payers, taxFreeInterest: taxFree);
}
