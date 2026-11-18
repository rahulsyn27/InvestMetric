import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/dates.dart';
import '../logic/amfi.dart';
import '../logic/nav_history.dart';
import '../logic/returns.dart';
import '../models/ais.dart';
import '../models/investment.dart';
import '../models/member.dart';
import '../models/snapshot.dart';
import 'auth_service.dart';
import 'repository.dart';

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(FirebaseAuth.instance),
);

/// The signed-in user's id, or null when signed out.
final userIdProvider = StreamProvider<String?>(
  (ref) => ref.watch(authServiceProvider).authStateChanges().map((u) => u?.uid),
);

/// Display info of the signed-in user (for the Self profile).
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(userIdProvider);
  return FirebaseAuth.instance.currentUser;
});

/// Storage for the signed-in user. Tests override this.
final repositoryProvider = Provider<Repository?>((ref) {
  final uid = ref.watch(userIdProvider).value;
  if (uid == null) return null;
  return FirestoreRepository(FirebaseFirestore.instance, uid);
});

final membersProvider = StreamProvider<List<Member>>((ref) {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return const Stream.empty();
  return repo.watchMembers();
});

final investmentsProvider = StreamProvider<List<Investment>>((ref) {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return const Stream.empty();
  return repo.watchInvestments();
});

final aisStatementsProvider = StreamProvider<List<AisStatement>>((ref) {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return const Stream.empty();
  return repo.watchAisStatements();
});

/// Which member the screens show; null = whole family.
class SelectedMember extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? memberId) => state = memberId;
}

final selectedMemberProvider = NotifierProvider<SelectedMember, String?>(
  SelectedMember.new,
);

/// Investments for the selected member (or everyone).
final visibleInvestmentsProvider = Provider<List<Investment>>((ref) {
  final all = ref.watch(investmentsProvider).value ?? const [];
  final member = ref.watch(selectedMemberProvider);
  if (member == null) return all;
  return all.where((i) => i.memberId == member).toList();
});

/// "Today", overridable in tests so numbers are stable.
final todayProvider = Provider<DateTime>((ref) => DateTime.now());

// ---- theme ----

const _themeKey = 'themeMode';

class ThemeModeSetting extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.dark;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_themeKey);
      final mode = ThemeMode.values.where((m) => m.name == saved).firstOrNull;
      if (mode != null) state = mode;
    } catch (_) {
      // Preferences unavailable: keep the default.
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, mode.name);
    } catch (_) {}
  }
}

final themeModeProvider = NotifierProvider<ThemeModeSetting, ThemeMode>(
  ThemeModeSetting.new,
);

// ---- mutual fund NAVs ----

/// The AMFI NAV list, downloaded on demand and kept for the session.
class AmfiNavs extends Notifier<AsyncValue<List<AmfiScheme>>?> {
  @override
  AsyncValue<List<AmfiScheme>>? build() => null;

  Future<List<AmfiScheme>> load({bool force = false}) async {
    final current = state;
    if (!force && current is AsyncData<List<AmfiScheme>>) return current.value;
    state = const AsyncLoading();
    try {
      final list = await fetchAmfiNavs();
      state = AsyncData(list);
      return list;
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}

final amfiNavsProvider =
    NotifierProvider<AmfiNavs, AsyncValue<List<AmfiScheme>>?>(AmfiNavs.new);

// ---- returns by period ----

/// The period chosen on the Returns cards (shared by Home and details).
class ReturnPeriodSetting extends Notifier<ReturnPeriod> {
  @override
  ReturnPeriod build() => ReturnPeriod.oneYear;

  void select(ReturnPeriod p) => state = p;
}

final returnPeriodProvider =
    NotifierProvider<ReturnPeriodSetting, ReturnPeriod>(
      ReturnPeriodSetting.new,
    );

/// Downloads one day of AMFI NAV history. Tests override this.
final navDayFetcherProvider = Provider<NavDayFetcher>(
  (ref) => fetchNavHistoryDay,
);

/// Which NAVs to look up: scheme codes (sorted, comma separated, so the
/// request compares by value) on a date.
typedef NavRequest = ({DateTime date, String codes});

NavRequest navRequest(DateTime date, Set<String> codes) =>
    (date: dateOnly(date), codes: (codes.toList()..sort()).join(','));

/// NAVs on (or just before) a past date. Past NAVs never change, so results
/// are kept on the phone and each date is downloaded only once.
final navsOnProvider = FutureProvider.family<Map<String, DatedNav>, NavRequest>(
  (ref, req) async {
    final codes = req.codes.split(',').where((c) => c.isNotEmpty).toSet();
    final cache = await _NavCache.open();
    final known = cache.read(req.date);
    final missing = codes.difference(known.keys.toSet());
    if (missing.isNotEmpty) {
      final fetched = await fetchNavsOn(
        req.date,
        missing,
        fetch: ref.read(navDayFetcherProvider),
      );
      for (final c in missing) {
        known[c] = fetched[c]; // null = no NAV that far back
      }
      await cache.write(req.date, known);
    }
    return {
      for (final c in codes)
        if (known[c] != null) c: known[c]!,
    };
  },
  // A failed download shows a retry button instead of retrying on its own.
  retry: (_, _) => null,
);

class _NavCache {
  _NavCache(this._prefs);

  static const _prefix = 'navHistory:';
  static const _keep = 40;

  final SharedPreferences? _prefs;

  static Future<_NavCache> open() async {
    try {
      return _NavCache(await SharedPreferences.getInstance());
    } catch (_) {
      return _NavCache(null);
    }
  }

  Map<String, DatedNav?> read(DateTime date) {
    final raw = _prefs?.getString('$_prefix${toIsoDate(date)}');
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in m.entries)
          e.key: e.value is List
              ? (
                  nav: ((e.value as List)[0] as num).toDouble(),
                  date: fromIsoDate((e.value as List)[1]) ?? date,
                )
              : null,
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> write(DateTime date, Map<String, DatedNav?> navs) async {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await prefs.setString(
        '$_prefix${toIsoDate(date)}',
        jsonEncode({
          for (final e in navs.entries)
            e.key: e.value == null
                ? null
                : [e.value!.nav, toIsoDate(e.value!.date)],
        }),
      );
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList()
        ..sort();
      for (final k in keys.take(keys.length - _keep)) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }
}

/// The latest saved value snapshot on or before a date.
final snapshotOnOrBeforeProvider =
    FutureProvider.family<ValueSnapshot?, DateTime>((ref, date) async {
      final repo = ref.watch(repositoryProvider);
      if (repo == null) return null;
      return repo.snapshotOnOrBefore(date);
    }, retry: (_, _) => null);

/// Saves today's value snapshot whenever the holdings change (app open,
/// price refresh, edits). One document per day; later saves replace it.
/// Watched by the home shell.
final snapshotRecorderProvider = Provider<void>((ref) {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return;
  String? last;
  ref.listen(investmentsProvider, (_, next) {
    final list = next.value;
    if (list == null || list.isEmpty) return;
    final snap = ValueSnapshot.of(list, ref.read(todayProvider));
    final sig = jsonEncode(snap.toMap());
    if (sig == last) return;
    last = sig;
    repo.saveSnapshot(snap);
  }, fireImmediately: true);
});
