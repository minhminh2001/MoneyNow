import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_user.dart';
import '../models/loan.dart';
import '../models/loan_application.dart';
import '../models/loan_draft.dart';
import '../models/repayment.dart';
import '../models/uploaded_document.dart';
import '../repositories/auth_repository.dart';
import '../repositories/loan_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/storage_repository.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final storageProvider = Provider<FirebaseStorage>((ref) {
  return FirebaseStorage.instance;
});

final functionsProvider = Provider<FirebaseFunctions>((ref) {
  return FirebaseFunctions.instanceFor(region: 'asia-southeast1');
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(firebaseAuthProvider));
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(firestoreProvider));
});

final storageRepositoryProvider = Provider<StorageRepository>((ref) {
  return StorageRepository(ref.watch(storageProvider));
});

final loanRepositoryProvider = Provider<LoanRepository>((ref) {
  return LoanRepository(
    firestore: ref.watch(firestoreProvider),
    functions: ref.watch(functionsProvider),
  );
});

final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateChangesProvider).value;
});

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider)?.uid;
});

final userProfileProvider = StreamProvider.autoDispose<AppUser?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return Stream<AppUser?>.value(null);
  }
  return ref
      .watch(profileRepositoryProvider)
      .streamProfile(uid: user.uid, email: user.email ?? '')
      .map((profile) => profile);
});

final userDocumentsProvider =
    StreamProvider.autoDispose<List<UploadedDocument>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream<List<UploadedDocument>>.value(const []);
  }
  return ref.watch(profileRepositoryProvider).streamDocuments(uid);
});

final loanDraftProvider = StreamProvider.autoDispose<LoanDraft>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream<LoanDraft>.value(LoanDraft.empty());
  }
  return ref.watch(profileRepositoryProvider).streamLoanDraft(uid);
});

final loanApplicationsProvider =
    StreamProvider.autoDispose<List<LoanApplication>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream<List<LoanApplication>>.value(const []);
  }
  return ref.watch(loanRepositoryProvider).streamApplications(uid);
});

final loansProvider = StreamProvider.autoDispose<List<Loan>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream<List<Loan>>.value(const []);
  }
  return ref.watch(loanRepositoryProvider).streamLoans(uid);
});

final repaymentScheduleProvider =
    StreamProvider.autoDispose.family<List<Repayment>, String>((ref, loanId) {
  return ref.watch(loanRepositoryProvider).streamRepaymentSchedule(loanId);
});
