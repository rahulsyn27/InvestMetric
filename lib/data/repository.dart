import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/investment.dart';
import '../models/member.dart';

/// Storage for one signed-in account. Everything lives under
/// `users/{uid}/members` and `users/{uid}/investments`.
abstract class Repository {
  Stream<List<Member>> watchMembers();
  Stream<List<Investment>> watchInvestments();

  /// Creates (empty id) or updates a member; returns its id.
  Future<String> saveMember(Member member);
  Future<void> deleteMember(String id);

  /// Creates (empty id) or updates an investment; returns its id.
  Future<String> saveInvestment(Investment investment);
  Future<void> deleteInvestment(String id);

  /// Writes many price updates at once.
  Future<void> updatePrices(Map<String, (double price, DateTime date)> byId);
}

/// Firestore writes finish when the server confirms them, which can take a
/// long time offline. The local cache updates straight away, so don't wait;
/// just log failures (e.g. permission errors).
void _fire(Future<void> write) {
  write.catchError((Object e) => debugPrint('Firestore write failed: $e'));
}

class FirestoreRepository implements Repository {
  FirestoreRepository(this._db, this.uid);

  final FirebaseFirestore _db;
  final String uid;

  CollectionReference<Map<String, dynamic>> get _members =>
      _db.collection('users').doc(uid).collection('members');
  CollectionReference<Map<String, dynamic>> get _investments =>
      _db.collection('users').doc(uid).collection('investments');

  @override
  Stream<List<Member>> watchMembers() => _members.snapshots().map((s) {
    final list = s.docs.map((d) => Member.fromMap(d.id, d.data())).toList()
      ..sort((a, b) {
        if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  });

  @override
  Stream<List<Investment>> watchInvestments() => _investments.snapshots().map(
    (s) => s.docs.map((d) => Investment.fromMap(d.id, d.data())).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
  );

  @override
  Future<String> saveMember(Member member) async {
    final data = {...member.toMap(), 'updatedAt': FieldValue.serverTimestamp()};
    if (member.id.isEmpty) {
      final ref = _members.doc();
      _fire(ref.set(data));
      return ref.id;
    }
    _fire(_members.doc(member.id).set(data, SetOptions(merge: true)));
    return member.id;
  }

  @override
  Future<void> deleteMember(String id) async {
    final batch = _db.batch();
    final owned = await _investments.where('memberId', isEqualTo: id).get();
    for (final d in owned.docs) {
      batch.delete(d.reference);
    }
    batch.delete(_members.doc(id));
    _fire(batch.commit());
  }

  @override
  Future<String> saveInvestment(Investment investment) async {
    final data = {
      ...investment.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (investment.id.isEmpty) {
      final ref = _investments.doc();
      _fire(ref.set(data));
      return ref.id;
    }
    _fire(_investments.doc(investment.id).set(data));
    return investment.id;
  }

  @override
  Future<void> deleteInvestment(String id) async {
    _fire(_investments.doc(id).delete());
  }

  @override
  Future<void> updatePrices(
    Map<String, (double price, DateTime date)> byId,
  ) async {
    final entries = byId.entries.toList();
    // Firestore batches hold at most 500 writes.
    for (var i = 0; i < entries.length; i += 400) {
      final batch = _db.batch();
      for (final e in entries.skip(i).take(400)) {
        batch.update(_investments.doc(e.key), {
          'currentPrice': e.value.$1,
          'priceDate': toIsoDateOrNull(e.value.$2),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      _fire(batch.commit());
    }
  }
}

/// Keeps data in memory. Used by tests and the offline demo.
class InMemoryRepository implements Repository {
  InMemoryRepository({List<Member>? members, List<Investment>? investments}) {
    for (final m in members ?? const <Member>[]) {
      _members[m.id] = m;
    }
    for (final i in investments ?? const <Investment>[]) {
      _investments[i.id] = i;
    }
  }

  final _members = <String, Member>{};
  final _investments = <String, Investment>{};
  final _memberCtrl = StreamController<List<Member>>.broadcast();
  final _invCtrl = StreamController<List<Investment>>.broadcast();
  var _next = 0;

  String _id() => 'local-${_next++}';

  List<Member> get members => _members.values.toList();
  List<Investment> get investments => _investments.values.toList();

  void _emit() {
    _memberCtrl.add(members);
    _invCtrl.add(investments);
  }

  @override
  Stream<List<Member>> watchMembers() async* {
    yield members;
    yield* _memberCtrl.stream;
  }

  @override
  Stream<List<Investment>> watchInvestments() async* {
    yield investments;
    yield* _invCtrl.stream;
  }

  @override
  Future<String> saveMember(Member member) async {
    final id = member.id.isEmpty ? _id() : member.id;
    _members[id] = member.copyWith(id: id);
    _emit();
    return id;
  }

  @override
  Future<void> deleteMember(String id) async {
    _members.remove(id);
    _investments.removeWhere((_, i) => i.memberId == id);
    _emit();
  }

  @override
  Future<String> saveInvestment(Investment investment) async {
    final id = investment.id.isEmpty ? _id() : investment.id;
    _investments[id] = Investment.fromMap(id, investment.toMap());
    _emit();
    return id;
  }

  @override
  Future<void> deleteInvestment(String id) async {
    _investments.remove(id);
    _emit();
  }

  @override
  Future<void> updatePrices(
    Map<String, (double price, DateTime date)> byId,
  ) async {
    for (final e in byId.entries) {
      final inv = _investments[e.key];
      if (inv == null) continue;
      _investments[e.key] = inv.copyWith(
        currentPrice: e.value.$1,
        priceDate: e.value.$2,
      );
    }
    _emit();
  }
}
