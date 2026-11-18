import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../logic/amfi.dart';
import '../models/ais.dart';
import '../models/investment.dart';
import '../models/member.dart';
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
