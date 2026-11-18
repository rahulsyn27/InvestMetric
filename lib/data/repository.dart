import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../models/ais.dart';
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

  /// Imported AIS statements (one per member per tax year).
  Stream<List<AisStatement>> watchAisStatements();

  /// Saves an AIS statement, replacing an earlier import for the same
  /// member and year.
  Future<void> saveAisStatement(AisStatement statement);
  Future<void> deleteAisStatement(String docId);
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
  CollectionReference<Map<String, dynamic>> get _ais =>
      _db.collection('users').doc(uid).collection('ais');

  @override
  Stream<List<AisStatement>> watchAisStatements() => _ais.snapshots().map(
    (s) => s.docs.map((d) => AisStatement.fromMap(d.data())).toList(),
  );

  @override
  Future<void> saveAisStatement(AisStatement statement) async {
    _fire(_ais.doc(statement.docId).set(statement.toMap()));
  }

  @override
  Future<void> deleteAisStatement(String docId) async {
    _fire(_ais.doc(docId).delete());
  }

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
    final ais = await _ais.where('memberId', isEqualTo: id).get();
    for (final d in ais.docs) {
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
  final _ais = <String, AisStatement>{};
  final _aisCtrl = StreamController<List<AisStatement>>.broadcast();
  final _memberCtrl = StreamController<List<Member>>.broadcast();
  final _invCtrl = StreamController<List<Investment>>.broadcast();
  var _next = 0;

  String _id() => 'local-${_next++}';

  List<Member> get members => _members.values.toList();
  List<Investment> get investments => _investments.values.toList();
  List<AisStatement> get aisStatements => _ais.values.toList();

  @override
  Stream<List<AisStatement>> watchAisStatements() async* {
    yield aisStatements;
    yield* _aisCtrl.stream;
  }

  @override
  Future<void> saveAisStatement(AisStatement statement) async {
    _ais[statement.docId] = statement;
    _aisCtrl.add(aisStatements);
  }

  @override
  Future<void> deleteAisStatement(String docId) async {
    _ais.remove(docId);
    _aisCtrl.add(aisStatements);
  }

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
    _ais.removeWhere((_, a) => a.memberId == id);
    _aisCtrl.add(aisStatements);
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
