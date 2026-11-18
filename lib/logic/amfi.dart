import 'package:http/http.dart' as http;

/// Official daily NAV file published by AMFI (free, no key needed).
const amfiNavUrl = 'https://portal.amfiindia.com/spages/NAVAll.txt';

class AmfiScheme {
  const AmfiScheme({
    required this.code,
    required this.name,
    required this.nav,
    required this.date,
    this.fundHouse = '',
    this.category = '',
  });

  final String code;
  final String name;
  final double nav;
  final DateTime date;
  final String fundHouse;
  final String category;
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// "17-Nov-2026" → DateTime.
DateTime? parseAmfiDate(String s) {
  final parts = s.trim().split('-');
  if (parts.length != 3) return null;
  final d = int.tryParse(parts[0]);
  final m = _months[parts[1].toLowerCase()];
  final y = int.tryParse(parts[2]);
  if (d == null || m == null || y == null) return null;
  return DateTime(y, m, d);
}

/// Parses NAVAll.txt. Data lines look like
/// `119551;INF209KA12Z1;INF209KA13Z9;Some Fund - Direct - Growth;105.8442;17-Nov-2026`.
/// Lines without `;` are category headings ("Open Ended Schemes(…)") or
/// fund house names; they are remembered and attached to the schemes below.
List<AmfiScheme> parseNavAll(String text) {
  final out = <AmfiScheme>[];
  var category = '';
  var fundHouse = '';
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (!line.contains(';')) {
      if (line.contains('Schemes(') || line.contains('Schemes (')) {
        category = line;
      } else {
        fundHouse = line;
      }
      continue;
    }
    final f = line.split(';');
    if (f.length < 6) continue;
    final code = f[0].trim();
    if (int.tryParse(code) == null) continue; // header row
    final nav = double.tryParse(f[4].trim());
    final date = parseAmfiDate(f[5]);
    if (nav == null || date == null) continue; // "N.A." etc.
    out.add(
      AmfiScheme(
        code: code,
        name: f[3].trim(),
        nav: nav,
        date: date,
        fundHouse: fundHouse,
        category: category,
      ),
    );
  }
  return out;
}

/// Downloads and parses today's NAVs. Throws on network errors.
Future<List<AmfiScheme>> fetchAmfiNavs({http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res = await c
        .get(Uri.parse(amfiNavUrl))
        .timeout(const Duration(seconds: 40));
    if (res.statusCode != 200) {
      throw Exception('AMFI returned ${res.statusCode}');
    }
    return parseNavAll(res.body);
  } finally {
    if (client == null) c.close();
  }
}

/// Simple search: every word of [query] must appear in the scheme name.
List<AmfiScheme> searchSchemes(
  List<AmfiScheme> all,
  String query, {
  int limit = 30,
}) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return const [];
  final res = <AmfiScheme>[];
  for (final s in all) {
    final n = s.name.toLowerCase();
    if (words.every(n.contains) || s.code == query.trim()) {
      res.add(s);
      if (res.length >= limit) break;
    }
  }
  return res;
}
