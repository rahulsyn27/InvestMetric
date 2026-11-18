/// Tax numbers the app relies on, kept in one place so they are easy to
/// update when the Budget changes them.
///
/// Values are for tax year 2026-27 (Income-tax Act, 2025). They are used for
/// estimates and reminders only: always confirm with the bank / a CA.
class TaxRules {
  const TaxRules._();

  /// TDS on interest from a bank, co-operative bank or post office kicks in
  /// once interest from that payer in a tax year crosses this amount.
  static const double interestTdsThreshold = 50000;

  /// Same threshold for senior citizens (60+).
  static const double interestTdsThresholdSenior = 100000;

  /// TDS rate on interest when PAN is given.
  static const double interestTdsRate = 0.10;

  /// Age from which someone counts as a senior citizen.
  static const int seniorAge = 60;

  /// Long-term gains on listed equity / equity funds that are tax-free each year.
  static const double equityLtcgExemption = 125000;
  static const double equityLtcgRate = 0.125;
  static const double equityStcgRate = 0.20;

  /// Equity counts as long-term after this many months.
  static const int equityLongTermMonths = 12;

  /// Cumulative advance tax due by each date (day, month, share of the year's tax).
  static const List<(int, int, double)> advanceTaxInstalments = [
    (15, 6, 0.15),
    (15, 9, 0.45),
    (15, 12, 0.75),
    (15, 3, 1.00),
  ];
}
