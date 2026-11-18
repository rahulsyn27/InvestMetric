import 'package:http/http.dart' as http;

import '../core/dates.dart';
import 'amfi.dart';

/// AMFI's free NAV history report. Asked for a single date it returns every
/// scheme's NAV on that day (about 1.2 MB on a weekday).
///
/// On weekends and market holidays only a few overnight/liquid funds publish
/// a NAV, so [fetchNavsOn] steps back a day at a time.
Uri navHistoryUrl(DateTime date) => Uri.parse(
  'https://portal.amfiindia.com/DownloadNAVHistoryReport_Po.aspx'
  '?frmdt=${_amfiDate(date)}',
);

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// 7 → "07-Oct-2026".
String _amfiDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${_monthNames[d.month - 1]}-${d.year}';

/// A NAV and the date it is for.
typedef DatedNav = ({double nav, DateTime date});

/// Reads the NAV history report. Data lines look like
/// `119551;Fund name;Direct Plan;IDCW;INF209KA12Z1;INF209KA13Z9;106.7921;16-Oct-2026`
/// (code; name; plan; option; ISIN; ISIN; NAV; date). Headings and fund house
/// lines have no `;` and are skipped.
///
/// Only schemes in [codes] are kept, so the large file isn't held in memory.
/// If a scheme appears on several dates, the latest wins.
Map<String, DatedNav> parseNavHistory(String text, Set<String> codes) {
  final out = <String, DatedNav>{};
  for (final raw in text.split('\n')) {
    final semi = raw.indexOf(';');
    if (semi <= 0) continue;
    final code = raw.substring(0, semi).trim();
    if (!codes.contains(code)) continue;
    final f = raw.trim().split(';');
    if (f.length < 8) continue;
    final nav = double.tryParse(f[6].trim());
    final date = parseAmfiDate(f[7]);
    if (nav == null || nav <= 0 || date == null) continue;
    final prev = out[code];
    if (prev == null || date.isAfter(prev.date)) {
      out[code] = (nav: nav, date: date);
    }
  }
  return out;
}

/// Downloads the report for one day. Returns the raw text.
typedef NavDayFetcher = Future<String> Function(DateTime day);

Future<String> fetchNavHistoryDay(DateTime day, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res = await c
        .get(navHistoryUrl(day))
        .timeout(const Duration(seconds: 40));
    if (res.statusCode != 200) {
      throw Exception('AMFI returned ${res.statusCode}');
    }
    return res.body;
  } finally {
    if (client == null) c.close();
  }
}

/// The NAV of each scheme in [codes] on [date], or on the closest earlier
/// day that has one (looking back at most [maxDaysBack] days, which covers
/// weekends and long holiday breaks).
///
/// Schemes with no NAV in that window (e.g. launched later) are left out.
/// Throws if a download fails.
Future<Map<String, DatedNav>> fetchNavsOn(
  DateTime date,
  Set<String> codes, {
  NavDayFetcher fetch = fetchNavHistoryDay,
  int maxDaysBack = 7,
}) async {
  final found = <String, DatedNav>{};
  if (codes.isEmpty) return found;
  var day = dateOnly(date);
  for (var i = 0; i <= maxDaysBack; i++) {
    final missing = codes.difference(found.keys.toSet());
    if (missing.isEmpty) break;
    found.addAll(parseNavHistory(await fetch(day), missing));
    day = DateTime(day.year, day.month, day.day - 1);
  }
  return found;
}
