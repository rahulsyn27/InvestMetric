import '../core/dates.dart';
import '../core/tax_rules.dart';

/// A family member whose investments are tracked. Members don't need to use
/// the app: the account owner adds and manages everything for them.
class Member {
  const Member({
    required this.id,
    required this.name,
    this.relation = '',
    this.email = '',
    this.pan = '',
    this.dateOfBirth,
    this.isSelf = false,
  });

  final String id;
  final String name;

  /// "Self", "Mother", "Sister"…
  final String relation;

  /// The email their investments are registered with (where CAS / bank
  /// statements arrive). Just for reference: it is not a login.
  final String email;
  final String pan;
  final DateTime? dateOfBirth;
  final bool isSelf;

  /// Senior citizen for the given tax year (60+ at any point in it).
  bool isSeniorIn(TaxYear year) {
    final dob = dateOfBirth;
    if (dob == null) return false;
    return ageOn(year.lastDay)! >= TaxRules.seniorAge;
  }

  /// Age in completed years on [date], or null without a date of birth.
  int? ageOn(DateTime date) {
    final dob = dateOfBirth;
    if (dob == null) return null;
    var age = date.year - dob.year;
    if (date.month < dob.month ||
        (date.month == dob.month && date.day < dob.day)) {
      age -= 1;
    }
    return age;
  }

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.take(2).map((p) => p[0].toUpperCase()).join();
    return letters.isEmpty ? '?' : letters;
  }

  /// "ABCDE1234F" → "ABC••••34F".
  String get maskedPan {
    if (pan.length < 6) return pan;
    return '${pan.substring(0, 3)}••••${pan.substring(pan.length - 3)}';
  }

  Member copyWith({
    String? id,
    String? name,
    String? relation,
    String? email,
    String? pan,
    DateTime? dateOfBirth,
    bool clearDateOfBirth = false,
    bool? isSelf,
  }) => Member(
    id: id ?? this.id,
    name: name ?? this.name,
    relation: relation ?? this.relation,
    email: email ?? this.email,
    pan: pan ?? this.pan,
    dateOfBirth: clearDateOfBirth ? null : (dateOfBirth ?? this.dateOfBirth),
    isSelf: isSelf ?? this.isSelf,
  );

  Map<String, Object?> toMap() => {
    'name': name,
    'relation': relation,
    'email': email,
    'pan': pan,
    'dateOfBirth': dateOfBirth == null ? null : toIsoDate(dateOfBirth!),
    'isSelf': isSelf,
  };

  factory Member.fromMap(String id, Map<String, Object?> m) => Member(
    id: id,
    name: (m['name'] as String?) ?? '',
    relation: (m['relation'] as String?) ?? '',
    email: (m['email'] as String?) ?? '',
    pan: (m['pan'] as String?) ?? '',
    dateOfBirth: fromIsoDate(m['dateOfBirth']),
    isSelf: (m['isSelf'] as bool?) ?? false,
  );
}
