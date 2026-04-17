import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/loan_draft.dart';
import '../models/phone_contact.dart';
import '../models/uploaded_document.dart';

class ProfileRepository {
  ProfileRepository(this._firestore);

  final FirebaseFirestore _firestore;
  static const int _contactsBatchSize = 200;

  DocumentReference<Map<String, dynamic>> _userRef(String uid) {
    return _firestore.collection('users').doc(uid);
  }

  Stream<AppUser> streamProfile({
    required String uid,
    required String email,
  }) {
    return _userRef(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) {
        return AppUser.empty(uid: uid, email: email);
      }
      return AppUser.fromMap(snapshot.id, data);
    });
  }

  Future<void> ensureUserProfile({
    required String uid,
    required String email,
  }) async {
    final ref = _userRef(uid);
    final snapshot = await ref.get();
    if (snapshot.exists) return;

    final now = DateTime.now();
    await ref.set(
      AppUser.empty(uid: uid, email: email).toMap()
        ..['createdAt'] = now
        ..['updatedAt'] = now,
    );
  }

  Future<void> upsertProfile(AppUser user) async {
    await _userRef(user.uid).set(user.toMap(), SetOptions(merge: true));
  }

  Stream<LoanDraft> streamLoanDraft(String uid) {
    return _userRef(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null || data['loanDraft'] == null) {
        return LoanDraft.empty();
      }

      return LoanDraft.fromMap(
        Map<String, dynamic>.from(data['loanDraft'] as Map),
      );
    });
  }

  Future<void> saveLoanDraft({
    required String uid,
    required LoanDraft draft,
  }) async {
    await _userRef(uid).set(
      {
        'loanDraft': draft.toMap(),
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> clearLoanDraft(String uid) async {
    await _userRef(uid).set(
      {
        'loanDraft': FieldValue.delete(),
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> savePhoneContacts({
    required String uid,
    required List<PhoneContact> contacts,
  }) async {
    final contactsRef = _userRef(uid).collection('phoneContacts');
    final now = DateTime.now();
    for (var index = 0; index < contacts.length; index += _contactsBatchSize) {
      final batch = _firestore.batch();
      final chunk = contacts.skip(index).take(_contactsBatchSize);

      for (final contact in chunk) {
        final docRef = contactsRef.doc(contact.id);
        batch.set(
          docRef,
          contact.toMap()
            ..['syncedAt'] = now
            ..['updatedAt'] = now,
          SetOptions(merge: true),
        );
      }

      await batch.commit();
    }

    await _userRef(uid).set(
      {
        'contactsSync': {
          'count': contacts.length,
          'updatedAt': now,
        },
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );
  }

  Stream<List<UploadedDocument>> streamDocuments(String uid) {
    return _userRef(uid)
        .collection('documents')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => UploadedDocument.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Future<void> saveUploadedDocument({
    required String uid,
    required UploadedDocument document,
  }) async {
    await _userRef(uid)
        .collection('documents')
        .doc(document.id)
        .set(document.toMap());

    await syncKycStatus(uid);
  }

  Future<void> syncKycStatus(String uid) async {
    final docs = await _userRef(uid).collection('documents').get();
    final uploadedTypes =
        docs.docs.map((doc) => doc.data()['type']?.toString()).toSet();

    final ready = uploadedTypes.contains('id_front') &&
        uploadedTypes.contains('id_back') &&
        uploadedTypes.contains('selfie');

    await _userRef(uid).set(
      {
        'kycStatus': ready ? 'submitted' : 'pending',
        'updatedAt': DateTime.now(),
      },
      SetOptions(merge: true),
    );
  }
}
