import '../core/dates.dart';
import '../models/ais.dart';
import '../models/investment.dart';
import 'deposit_math.dart';

const _filler = {
  'limited',
  'ltd',
  'the',
  'of',
  'and',
  'bank',
  'co',
  'cooperative',
  'operative',
  'india',
  'indian',
  'branch',
  'pvt',
  'private',
  'society',
  'corporation',
  'company',
  'ltd.',
  '&',
};
const _small = {'of', 'the', 'and', '&'};

List<String> _tokens(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9& ]'), ' ')
    .split(RegExp(r'\s+'))
    .where((t) => t.isNotEmpty)
    .toList();

String _canonical(String s) {
  final l = s.toLowerCase();
  if (l.contains('post office') ||
      l.contains('india post') ||
      l.contains('department of post') ||
      l.contains('dept of post')) {
    return 'post office';
  }
  return s;
}

/// Whether a name typed in the app ("SBI", "HDFC Bank") and a source in AIS
/// ("STATE BANK OF INDIA", "HDFC BANK LIMITED") are the same institution.
bool sameInstitution(String appName, String aisSource) {
  final a = _tokens(_canonical(appName));
  final b = _tokens(_canonical(aisSource));
  if (a.isEmpty || b.isEmpty) return false;
  final compactA = a.join();
  final compactB = b.join();
  if (compactA == compactB) return true;

  // Acronyms: SBI = State Bank (of) India, BOB = Bank Of Baroda, PNB…
  String initials(List<String> t, {bool skipSmall = false}) => t
      .where((w) => !(skipSmall && _small.contains(w)))
      .where((w) => w != 'limited' && w != 'ltd')
      .map((w) => w[0])
      .join();
  for (final (short, long) in [(a, b), (b, a)]) {
    if (short.length == 1 && short.first.length >= 2) {
      final s = short.first;
      if (s == initials(long) || s == initials(long, skipSmall: true)) {
        return true;
      }
    }
  }

  // Meaningful words of one are all in the other: "Canara" ⊂ "CANARA BANK".
  final sa = a.where((t) => !_filler.contains(t)).toSet();
  final sb = b.where((t) => !_filler.contains(t)).toSet();
  if (sa.isEmpty || sb.isEmpty) return false;
  return sb.containsAll(sa) || sa.containsAll(sb);
}

enum InterestCheck {
  /// AIS and the app agree (within 5% or ₹500).
  matches,

  /// AIS shows more interest than the app expects: a deposit may be missing.
  aisHigher,

  /// AIS shows less: the bank may not have reported yet, or the rate differs.
  aisLower,

  /// The app expects interest here but AIS has nothing from this bank yet.
  notInAis,

  /// AIS shows interest from a bank that isn't in the app.
  notInApp,
}

class InterestComparison {
  const InterestComparison({
    required this.payer,
    required this.check,
    this.appInterest = 0,
    this.aisInterest = 0,
    this.aisTds = 0,
    this.upTo,
    this.records = const [],
  });

  /// Bank name (as typed in the app, or as in AIS when not in the app).
  final String payer;
  final InterestCheck check;

  /// What the app's deposits earned from the start of the year to [upTo].
  final double appInterest;
  final double aisInterest;
  final double aisTds;

  /// Last date covered by AIS for this bank.
  final DateTime? upTo;
  final List<AisRecord> records;

  double get difference => aisInterest - appInterest;
}

/// Compares the interest a member's deposits should have earned with what
/// banks reported in AIS for that year. Like-for-like: the app's estimate is
/// taken only up to the last date AIS covers.
List<InterestComparison> compareInterest({
  required AisStatement statement,
  required Iterable<Investment> investments,
  required DateTime today,
}) {
  final year = statement.year;
  final deposits = investments
      .where(
        (i) =>
            i.memberId == statement.memberId &&
            i.type.kind == ValuationKind.deposit,
      )
      .toList();
  final aisInterest = statement.records.where((r) => r.isInterest).toList();

  // Group app deposits by bank.
  final byBank = <String, List<Investment>>{};
  for (final d in deposits) {
    final name = d.institution.trim().isEmpty
        ? d.name.trim()
        : d.institution.trim();
    final key = byBank.keys.firstWhere(
      (k) => sameInstitution(k, name),
      orElse: () => name,
    );
    byBank.putIfAbsent(key, () => []).add(d);
  }

  final used = <AisRecord>{};
  final out = <InterestComparison>[];
  final yearEnd = minDate(
    year.end,
    dateOnly(today).add(const Duration(days: 1)),
  );

  for (final entry in byBank.entries) {
    final matched = aisInterest
        .where((r) => sameInstitution(entry.key, r.source))
        .toList();
    used.addAll(matched);
    final lastDates = matched
        .map((r) => r.lastDate)
        .whereType<DateTime>()
        .toList();
    final upTo = lastDates.isEmpty
        ? null
        : lastDates.reduce((a, b) => a.isAfter(b) ? a : b);
    final cutoff = upTo == null
        ? yearEnd
        : minDate(upTo.add(const Duration(days: 1)), year.end);
    final app = entry.value.fold(
      0.0,
      (s, inv) => s + DepositMath.interestBetween(inv, year.start, cutoff),
    );
    if (app <= 0 && matched.isEmpty) continue;
    final ais = matched.fold(0.0, (s, r) => s + r.total);
    final tds = matched.fold(0.0, (s, r) => s + r.tdsDeducted);
    final InterestCheck check;
    if (matched.isEmpty) {
      check = InterestCheck.notInAis;
    } else if ((ais - app).abs() <= 500 ||
        (app > 0 && (ais - app).abs() / app <= 0.05)) {
      check = InterestCheck.matches;
    } else {
      check = ais > app ? InterestCheck.aisHigher : InterestCheck.aisLower;
    }
    out.add(
      InterestComparison(
        payer: entry.key,
        check: check,
        appInterest: app,
        aisInterest: ais,
        aisTds: tds,
        upTo: upTo,
        records: matched,
      ),
    );
  }

  // AIS interest from banks the app doesn't know about.
  final leftover = <String, List<AisRecord>>{};
  for (final r in aisInterest.where((r) => !used.contains(r))) {
    final key = leftover.keys.firstWhere(
      (k) => sameInstitution(k, r.source),
      orElse: () => r.source,
    );
    leftover.putIfAbsent(key, () => []).add(r);
  }
  for (final e in leftover.entries) {
    out.add(
      InterestComparison(
        payer: e.key,
        check: InterestCheck.notInApp,
        aisInterest: e.value.fold(0.0, (s, r) => s + r.total),
        aisTds: e.value.fold(0.0, (s, r) => s + r.tdsDeducted),
        records: e.value,
      ),
    );
  }
  return out;
}
