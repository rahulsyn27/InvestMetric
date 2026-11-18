import '../core/dates.dart';
import '../core/money.dart';
import '../core/tax_rules.dart';
import '../models/investment.dart';
import 'deposit_math.dart';

enum EventKind { maturity, overdueMaturity, instalment, sip, payout, tax }

class UpcomingEvent {
  const UpcomingEvent({
    required this.date,
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.amount,
    this.investment,
  });

  final DateTime date;
  final EventKind kind;
  final String title;
  final String subtitle;
  final double? amount;
  final Investment? investment;

  bool get needsAction =>
      kind == EventKind.maturity || kind == EventKind.overdueMaturity;
}

/// Next date on or after [from] that falls on [day] of a month.
DateTime nextMonthlyDate(DateTime from, int day) {
  final f = dateOnly(from);
  final thisMonth = DateTime(f.year, f.month, _clampDay(f.year, f.month, day));
  if (!thisMonth.isBefore(f)) return thisMonth;
  final n = addMonths(DateTime(f.year, f.month, 1), 1);
  return DateTime(n.year, n.month, _clampDay(n.year, n.month, day));
}

int _clampDay(int y, int m, int day) {
  final last = DateTime(y, m + 1, 0).day;
  return day > last ? last : (day < 1 ? 1 : day);
}

/// Fixed tax dates in the window.
List<UpcomingEvent> taxDates(DateTime from, DateTime to) {
  final out = <UpcomingEvent>[];
  for (var y = from.year - 1; y <= to.year + 1; y++) {
    final fy = TaxYear(y);
    for (final (day, month, share) in TaxRules.advanceTaxInstalments) {
      final year = month <= 3 ? y + 1 : y;
      out.add(
        UpcomingEvent(
          date: DateTime(year, month, day),
          kind: EventKind.tax,
          title: 'Advance tax · ${(share * 100).round()}% of the year\'s tax',
          subtitle: 'Tax year ${fy.label} · needed if tax due is over ₹10,000',
        ),
      );
    }
    out.add(
      UpcomingEvent(
        date: DateTime(y + 1, 3, 31),
        kind: EventKind.tax,
        title: 'Last day of tax year ${fy.label}',
        subtitle: 'PPF yearly deposit, tax-saving investments, gains to book',
      ),
    );
    out.add(
      UpcomingEvent(
        date: DateTime(y + 1, 4, 10),
        kind: EventKind.tax,
        title: 'Submit Form 15G / 15H to banks',
        subtitle: 'For tax year ${fy.next.label}, if eligible',
      ),
    );
    out.add(
      UpcomingEvent(
        date: DateTime(y + 1, 7, 31),
        kind: EventKind.tax,
        title: 'Income tax return due',
        subtitle: 'For tax year ${fy.label} (non-audit cases)',
      ),
    );
    out.add(
      UpcomingEvent(
        date: DateTime(y + 1, 12, 31),
        kind: EventKind.tax,
        title: 'Last date for revised / belated return',
        subtitle: 'For tax year ${fy.label}',
      ),
    );
  }
  return out
      .where((e) => !e.date.isBefore(from) && !e.date.isAfter(to))
      .toList();
}

/// Everything coming up from [today] for the next [days] days, plus any
/// matured deposits still waiting for a decision.
List<UpcomingEvent> upcomingEvents(
  Iterable<Investment> investments,
  DateTime today, {
  int days = 365,
  bool includeTaxDates = true,
}) {
  final from = dateOnly(today);
  final to = from.add(Duration(days: days));
  final out = <UpcomingEvent>[];

  for (final inv in investments.where((i) => !i.isClosed)) {
    if (inv.type.kind == ValuationKind.deposit) {
      final m = inv.maturityDate;
      if (m != null) {
        final value = DepositMath.maturityValue(inv);
        if (m.isBefore(from)) {
          out.add(
            UpcomingEvent(
              date: m,
              kind: EventKind.overdueMaturity,
              title: '${inv.name} has matured',
              subtitle: 'Mark it as renewed or withdrawn',
              amount: value,
              investment: inv,
            ),
          );
        } else if (!m.isAfter(to)) {
          out.add(
            UpcomingEvent(
              date: m,
              kind: EventKind.maturity,
              title: '${inv.name} matures',
              subtitle: inv.institution.isEmpty
                  ? 'Renew or withdraw?'
                  : '${inv.institution} · renew or withdraw?',
              amount: value,
              investment: inv,
            ),
          );
        }
      }
      if (inv.isRecurring) {
        final next = DepositMath.rdInstalmentDates(inv)
            .where((d) => !d.isBefore(from))
            .firstOrNull;
        if (next != null && !next.isAfter(to)) {
          out.add(
            UpcomingEvent(
              date: next,
              kind: EventKind.instalment,
              title: 'RD instalment · ${inv.name}',
              subtitle: inv.institution,
              amount: inv.monthlyInstalment,
              investment: inv,
            ),
          );
        }
      }
      final payout = DepositMath.nextPayout(inv, from);
      if (payout != null && !payout.$1.isAfter(to)) {
        out.add(
          UpcomingEvent(
            date: payout.$1,
            kind: EventKind.payout,
            title: 'Interest payout · ${inv.name}',
            subtitle: 'Before TDS · ${formatInr(payout.$2)}',
            amount: payout.$2,
            investment: inv,
          ),
        );
      }
    }
    final sipDay = inv.sipDay;
    final sipAmount = inv.sipAmount;
    if (sipDay != null && sipAmount != null && sipAmount > 0) {
      final d = nextMonthlyDate(from, sipDay);
      if (!d.isAfter(to)) {
        out.add(
          UpcomingEvent(
            date: d,
            kind: EventKind.sip,
            title: 'SIP · ${inv.name}',
            subtitle: 'Keep money in the bank account',
            amount: sipAmount,
            investment: inv,
          ),
        );
      }
    }
  }

  if (includeTaxDates) out.addAll(taxDates(from, to));
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}
