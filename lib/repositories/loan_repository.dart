import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/loan.dart';
import '../models/loan_application.dart';
import '../models/repayment.dart';

class LoanRepository {
  LoanRepository({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
  })  : _firestore = firestore,
        _functions = functions;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  Stream<List<LoanApplication>> streamApplications(String uid) {
    return _firestore
        .collection('loanApplications')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => LoanApplication.fromMap(doc.id, doc.data()))
              .toList(),
        );
  }

  Stream<List<Loan>> streamLoans(String uid) {
    return _firestore
        .collection('loans')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Loan.fromMap(doc.id, doc.data())).toList(),
        );
  }

  Stream<List<Repayment>> streamRepaymentSchedule(String loanId) {
    return _firestore
        .collection('loans')
        .doc(loanId)
        .collection('repaymentSchedules')
        .orderBy('installmentNo')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) => Repayment.fromMap(doc.id, doc.data())).toList(),
        );
  }

  Future<Map<String, dynamic>> submitLoanApplication({
    required double amount,
    required int termMonths,
    required String purpose,
  }) async {
    final callable = _functions.httpsCallable('submitLoanApplication');
    final result = await callable.call<Map<String, dynamic>>({
      'amount': amount,
      'termMonths': termMonths,
      'purpose': purpose,
    });

    return Map<String, dynamic>.from(result.data);
  }

  Future<void> markRepaymentPaidMock({
    required String loanId,
    required String scheduleId,
  }) async {
    final callable = _functions.httpsCallable('markRepaymentPaidMock');
    await callable.call<Map<String, dynamic>>({
      'loanId': loanId,
      'scheduleId': scheduleId,
    });
  }
}
