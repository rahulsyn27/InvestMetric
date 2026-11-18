import 'dart:math' as math;

import '../core/dates.dart';
import '../models/investment.dart';

/// Interest maths for FDs, RDs, bonds and post office schemes.
///
/// Time is measured in days / 365. Banks round and post interest on fixed
/// dates, so results are close estimates (usually within a few rupees), not
/// the bank's exact figures.
class DepositMath {
  const DepositMath._();

  /// Growth factor of ₹1 after [days] at [ratePct] with [compounding].
  static double growth(double ratePct, Compounding compounding, int days) {
    if (days <= 0) return 1;
    final r = ratePct / 100;
    final years = days / 365;
    if (compounding == Compounding.simple) return 1 + r * years;
    final n = compounding.perYear;
    return math.pow(1 + r / n, n * years).toDouble();
  }

  /// Number of RD instalments in the full tenure.
  static int rdInstalments(Investment inv) {
    final start = inv.startDate;
    final end = inv.maturityDate;
    if (start == null || end == null) return 0;
    return math.max(0, monthsBetween(start, end));
  }

  /// Dates on which RD instalments are paid.
  static List<DateTime> rdInstalmentDates(Investment inv) {
    final start = inv.startDate;
    if (start == null) return const [];
    return [for (var k = 0; k < rdInstalments(inv); k++) addMonths(start, k)];
  }

  /// The date valuation stops moving (maturity, if it has passed).
  static DateTime _cap(Investment inv, DateTime date) {
    final m = inv.maturityDate;
    return (m != null && date.isAfter(m)) ? m : date;
  }

  /// Money put in up to [date].
  static double investedOn(Investment inv, DateTime date) {
    if (inv.isRecurring) {
      final m = inv.monthlyInstalment ?? 0;
      final paid = rdInstalmentDates(inv).where((d) => !d.isAfter(date)).length;
      return m * paid;
    }
    final start = inv.startDate;
    if (start != null && date.isBefore(start)) return 0;
    return inv.principal ?? 0;
  }

  /// Interest that has built up (earned, whether paid out or not) from the
  /// start until [date].
  static double interestEarnedUntil(Investment inv, DateTime date) {
    final rate = inv.ratePct;
    final start = inv.startDate;
    if (rate == null || start == null) return 0;
    final until = _cap(inv, date);
    if (!until.isAfter(start)) return 0;

    if (inv.isRecurring) {
      final m = inv.monthlyInstalment ?? 0;
      var total = 0.0;
      for (final d in rdInstalmentDates(inv)) {
        if (d.isAfter(until)) break;
        total += m * (growth(rate, inv.compounding, daysBetween(d, until)) - 1);
      }
      return total;
    }

    final p = inv.principal ?? 0;
    final days = daysBetween(start, until);
    if (inv.payout != Payout.cumulative) {
      // Interest is paid out, so it never compounds.
      return p * rate / 100 * days / 365;
    }
    return p * (growth(rate, inv.compounding, days) - 1);
  }

  /// Interest earned within [from, to) — e.g. a tax year.
  static double interestBetween(Investment inv, DateTime from, DateTime to) {
    final v = interestEarnedUntil(inv, to) - interestEarnedUntil(inv, from);
    return v < 0 ? 0 : v;
  }

  /// What the deposit is worth on [date]. Paid-out interest is not included
  /// (it is already in the bank account).
  static double valueOn(Investment inv, DateTime date) {
    final invested = investedOn(inv, date);
    if (!inv.isRecurring && inv.payout != Payout.cumulative) return invested;
    return invested + interestEarnedUntil(inv, date);
  }

  /// Amount received at maturity (cumulative deposits), or the principal.
  static double? maturityValue(Investment inv) {
    final m = inv.maturityDate;
    if (m == null) return null;
    return valueOn(inv, m);
  }

  /// Next interest payout on or after [after], for payout deposits.
  static (DateTime, double)? nextPayout(Investment inv, DateTime after) {
    final start = inv.startDate;
    final rate = inv.ratePct;
    final p = inv.principal;
    if (inv.isRecurring ||
        inv.payout == Payout.cumulative ||
        start == null ||
        rate == null ||
        p == null) {
      return null;
    }
    var k = 1;
    while (true) {
      final d = addMonths(start, k * inv.payout.months);
      final m = inv.maturityDate;
      if (m != null && d.isAfter(m)) return null;
      if (!d.isBefore(dateOnly(after))) {
        return (d, p * rate / 100 * inv.payout.months / 12);
      }
      k++;
      if (k > 2400) return null;
    }
  }
}
