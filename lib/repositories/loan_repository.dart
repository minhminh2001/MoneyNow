import 'dart:convert';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/constants/loan_policy.dart';
import '../core/utils/loan_calculator.dart';
import '../models/loan.dart';
import '../models/loan_application.dart';
import '../models/repayment.dart';

class LoanRepository {
  static const Duration _callableTimeout = Duration(seconds: 20);

  LoanRepository({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required FirebaseAuth auth,
  })  : _firestore = firestore,
        _functions = functions,
        _auth = auth;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  FirebaseFunctions _functionsForActiveSession() {
    return FirebaseFunctions.instanceFor(
      app: _functions.app,
      region: 'asia-southeast1',
    );
  }

  Future<(User, String)> _requireFreshUserForCurrentProject() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Bạn cần đăng nhập lại trước khi nộp hồ sơ vay.',
      );
    }

    final token = await user.getIdToken(true);
    if (token == null || token.isEmpty) {
      await _auth.signOut();
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Không thể xác minh phiên đăng nhập hiện tại. Vui lòng đăng nhập lại.',
      );
    }

    final configuredProjectId = _functions.app.options.projectId;
    final tokenProjectId = _extractProjectIdFromToken(token);

    if (configuredProjectId.isNotEmpty &&
        tokenProjectId != null &&
        tokenProjectId.isNotEmpty &&
        tokenProjectId != configuredProjectId) {
      await _auth.signOut();
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Phiên đăng nhập hiện tại thuộc cấu hình Firebase cũ. Vui lòng đăng nhập lại.',
      );
    }

    return (user, token);
  }

  String? _extractProjectIdFromToken(String token) {
    try {
      final segments = token.split('.');
      if (segments.length < 2) {
        return null;
      }

      final normalized = base64Url.normalize(segments[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final payload = jsonDecode(decoded);
      if (payload is! Map<String, dynamic>) {
        return null;
      }

      final audience = payload['aud']?.toString().trim();
      if (audience != null && audience.isNotEmpty) {
        return audience;
      }

      final issuer = payload['iss']?.toString().trim();
      if (issuer != null && issuer.isNotEmpty) {
        const prefix = 'https://securetoken.google.com/';
        if (issuer.startsWith(prefix)) {
          return issuer.substring(prefix.length);
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Stream<List<LoanApplication>> streamApplications(String uid) {
    return _firestore
        .collection('loanApplications')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final applications = <LoanApplication>[];
      for (final doc in snapshot.docs) {
        try {
          applications.add(LoanApplication.fromMap(doc.id, doc.data()));
        } catch (error, stackTrace) {
          debugPrint(
            'LoanApplication parse failed for ${doc.id}: $error\n$stackTrace',
          );
        }
      }
      return applications;
    });
  }

  Future<List<LoanApplication>> fetchAllApplications() async {
    final snapshot = await _firestore
        .collection('loanApplications')
        .orderBy('createdAt', descending: true)
        .get();
    final applications = <LoanApplication>[];
    for (final doc in snapshot.docs) {
      try {
        applications.add(LoanApplication.fromMap(doc.id, doc.data()));
      } catch (error, stackTrace) {
        debugPrint(
          'Admin loan application parse failed for ${doc.id}: $error\n$stackTrace',
        );
      }
    }
    return applications;
  }

  Future<Map<String, Map<String, dynamic>>> fetchUserSummariesByIds(
    Iterable<String> uids,
  ) async {
    final uniqueUids = uids.map((uid) => uid.trim()).where((uid) => uid.isNotEmpty).toSet();
    final result = <String, Map<String, dynamic>>{};

    for (final uid in uniqueUids) {
      try {
        final snapshot = await _firestore.collection('users').doc(uid).get();
        final data = snapshot.data();
        if (data != null) {
          result[uid] = Map<String, dynamic>.from(data);
        }
      } catch (error, stackTrace) {
        debugPrint('Admin user summary fetch failed for $uid: $error\n$stackTrace');
      }
    }

    return result;
  }

  Stream<List<Loan>> streamLoans(String uid) {
    return _firestore
        .collection('loans')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      final loans = <Loan>[];
      for (final doc in snapshot.docs) {
        try {
          loans.add(Loan.fromMap(doc.id, doc.data()));
        } catch (error, stackTrace) {
          debugPrint('Loan parse failed for ${doc.id}: $error\n$stackTrace');
        }
      }
      return loans;
    });
  }

  Stream<List<Repayment>> streamRepaymentSchedule(String loanId) {
    return _firestore
        .collection('loans')
        .doc(loanId)
        .collection('repaymentSchedules')
        .orderBy('installmentNo')
        .snapshots()
        .map((snapshot) {
      final schedules = <Repayment>[];
      for (final doc in snapshot.docs) {
        try {
          schedules.add(Repayment.fromMap(doc.id, doc.data()));
        } catch (error, stackTrace) {
          debugPrint(
            'Repayment parse failed for ${doc.id}: $error\n$stackTrace',
          );
        }
      }
      return schedules;
    });
  }

  Future<Map<String, dynamic>> submitLoanApplication({
    required double amount,
    required int termWeeks,
    required String purpose,
  }) async {
    try {
      final (_, token) = await _requireFreshUserForCurrentProject();
      final callable =
          _functionsForActiveSession().httpsCallable('submitLoanApplication');
      final result = await callable
          .call<Map<String, dynamic>>({
            'amount': amount,
            'termWeeks': termWeeks,
            'purpose': purpose,
            'idToken': token,
          })
          .timeout(_callableTimeout);

      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'unauthenticated') {
        return _submitLoanApplicationFallback(
          amount: amount,
          termWeeks: termWeeks,
          purpose: purpose,
        );
      }
      rethrow;
    }
  }

  Future<void> markRepaymentPaidMock({
    required String loanId,
    required String scheduleId,
  }) async {
    final (_, token) = await _requireFreshUserForCurrentProject();
    final callable =
        _functionsForActiveSession().httpsCallable('markRepaymentPaidMock');
    await callable
        .call<Map<String, dynamic>>({
          'loanId': loanId,
          'scheduleId': scheduleId,
          'idToken': token,
        })
        .timeout(_callableTimeout);
  }

  Future<Map<String, dynamic>> reviewLoanApplicationManual({
    required String applicationId,
    required String decision,
    String? decisionReason,
  }) async {
    final (_, token) = await _requireFreshUserForCurrentProject();
    final callable =
        _functionsForActiveSession().httpsCallable('reviewLoanApplicationManual');
    final result = await callable
        .call<Map<String, dynamic>>({
          'applicationId': applicationId,
          'decision': decision,
          'decisionReason': decisionReason,
          'idToken': token,
        })
        .timeout(_callableTimeout);

    return Map<String, dynamic>.from(result.data);
  }

  Future<Map<String, dynamic>> _submitLoanApplicationFallback({
    required double amount,
    required int termWeeks,
    required String purpose,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Bạn cần đăng nhập lại trước khi nộp hồ sơ vay.',
      );
    }

    final userSnap = await _firestore.collection('users').doc(user.uid).get();
    final monthlyIncome = ((userSnap.data() ?? const <String, dynamic>{})['monthlyIncome']
                as num?)
            ?.toDouble() ??
        0;

    final estimate = LoanCalculator.estimate(
      principal: amount,
      termWeeks: termWeeks,
    );

    final applicationRef = _firestore.collection('loanApplications').doc();
    await applicationRef.set({
      'uid': user.uid,
      'amount': amount,
      'termWeeks': termWeeks,
      'monthlyIncome': monthlyIncome,
      'weeklyInstallment': estimate.weeklyInstallment,
      'interestRate': LoanPolicy.fixedInterestRate,
      'overduePenaltyFee': LoanPolicy.overduePenaltyFee,
      'purpose': purpose,
      'status': 'reviewing',
      'riskLevel': 'medium',
      'decisionReason':
          'Hồ sơ đã được ghi nhận và đang chờ thẩm định thủ công.',
      'approvedLoanId': null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'source': 'client_fallback',
    });

    return {
      'applicationId': applicationRef.id,
      'loanId': null,
      'status': 'reviewing',
      'message': 'Hồ sơ đã được ghi nhận và đang chờ thẩm định thủ công.',
    };
  }
}

String translateFunctionsError(Object error) {
  if (error is TimeoutException) {
    return 'Hệ thống xử lý hồ sơ đang phản hồi chậm. Vui lòng thử lại sau ít phút.';
  }
  if (error is FirebaseFunctionsException) {
    switch (error.code) {
      case 'unauthenticated':
        final message = error.message?.trim();
        if (message != null && message.isNotEmpty) {
          return message;
        }
        return 'Phiên đăng nhập không hợp lệ hoặc đã hết hạn. Vui lòng đăng xuất, đăng nhập lại rồi thử nộp hồ sơ.';
      case 'failed-precondition':
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'Dữ liệu hồ sơ chưa đủ điều kiện để thực hiện thao tác này.';
      case 'invalid-argument':
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'Dữ liệu gửi lên chưa hợp lệ.';
      default:
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'Không thể kết nối tới hệ thống xử lý hồ sơ lúc này.';
    }
  }

  final text = error.toString();
  if (text.contains('UNAUTHENTICATED')) {
    return 'Phiên đăng nhập không hợp lệ hoặc đã hết hạn. Vui lòng đăng xuất, đăng nhập lại rồi thử nộp hồ sơ.';
  }
  return 'Không thể kết nối tới hệ thống xử lý hồ sơ lúc này.';
}
