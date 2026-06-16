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

  Future<
      ({
        List<LoanApplication> applications,
        List<Loan> loans,
        Map<String, Map<String, dynamic>> userSummaries,
      })> fetchAdminDashboard() async {
    final (_, token) = await _requireFreshUserForCurrentProject();
    final callable = _functionsForActiveSession().httpsCallable(
      'fetchAdminDashboard',
    );
    final result = await callable
        .call<Map<String, dynamic>>({
          'idToken': token,
        })
        .timeout(_callableTimeout);

    final data = Map<String, dynamic>.from(result.data);
    final applicationsRaw = (data['applications'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final loansRaw = (data['loans'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final userSummariesRaw =
        Map<String, dynamic>.from(data['userSummaries'] as Map? ?? const {});

    final applications = <LoanApplication>[];
    for (final item in applicationsRaw) {
      final id = (item['id'] ?? '').toString();
      if (id.isEmpty) continue;
      applications.add(LoanApplication.fromMap(id, item));
    }

    final loans = <Loan>[];
    for (final item in loansRaw) {
      final id = (item['id'] ?? '').toString();
      if (id.isEmpty) continue;
      loans.add(Loan.fromMap(id, item));
    }

    final userSummaries = <String, Map<String, dynamic>>{};
    userSummariesRaw.forEach((key, value) {
      if (value is Map) {
        userSummaries[key] = Map<String, dynamic>.from(value);
      }
    });

    return (
      applications: applications,
      loans: loans,
      userSummaries: userSummaries,
    );
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
        .get()
        .timeout(_callableTimeout);
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
        final snapshot = await _firestore
            .collection('users')
            .doc(uid)
            .get()
            .timeout(_callableTimeout);
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

  Future<List<Loan>> fetchAllLoans() async {
    final snapshot = await _firestore
        .collection('loans')
        .orderBy('createdAt', descending: true)
        .get()
        .timeout(_callableTimeout);
    final loans = <Loan>[];
    for (final doc in snapshot.docs) {
      try {
        loans.add(Loan.fromMap(doc.id, doc.data()));
      } catch (error, stackTrace) {
        debugPrint('Admin loan parse failed for ${doc.id}: $error\n$stackTrace');
      }
    }
    return loans;
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
      if (error.code == 'unauthenticated' ||
          error.code == 'not-found' ||
          error.code == 'internal' ||
          error.code == 'unimplemented') {
        return _submitLoanApplicationFallback(
          amount: amount,
          termWeeks: termWeeks,
          purpose: purpose,
        );
      }
      rethrow;
    } on TimeoutException {
      return _submitLoanApplicationFallback(
        amount: amount,
        termWeeks: termWeeks,
        purpose: purpose,
      );
    }
  }

  Future<void> markRepaymentPaidMock({
    required String loanId,
    required String scheduleId,
  }) async {
    try {
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
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'unauthenticated' ||
          error.code == 'not-found' ||
          error.code == 'internal' ||
          error.code == 'unimplemented') {
        await _markRepaymentPaidFallback(
          loanId: loanId,
          scheduleId: scheduleId,
        );
        return;
      }
      rethrow;
    } on TimeoutException {
      await _markRepaymentPaidFallback(
        loanId: loanId,
        scheduleId: scheduleId,
      );
      return;
    }
  }

  Future<Map<String, dynamic>> reviewLoanApplicationManual({
    required String applicationId,
    required String decision,
    String? decisionReason,
  }) async {
    try {
      final (_, token) = await _requireFreshUserForCurrentProject();
      final callable = _functionsForActiveSession()
          .httpsCallable('reviewLoanApplicationManual');
      final result = await callable
          .call<Map<String, dynamic>>({
            'applicationId': applicationId,
            'decision': decision,
            'decisionReason': decisionReason,
            'idToken': token,
          })
          .timeout(_callableTimeout);

      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'unauthenticated' ||
          error.code == 'permission-denied' ||
          error.code == 'not-found' ||
          error.code == 'internal' ||
          error.code == 'unimplemented') {
        return _reviewLoanApplicationFallback(
          applicationId: applicationId,
          decision: decision,
          decisionReason: decisionReason,
        );
      }
      rethrow;
    } on TimeoutException {
      return _reviewLoanApplicationFallback(
        applicationId: applicationId,
        decision: decision,
        decisionReason: decisionReason,
      );
    }
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

    final userSnap = await _firestore
        .collection('users')
        .doc(user.uid)
        .get()
        .timeout(_callableTimeout);
    final userData = userSnap.data() ?? const <String, dynamic>{};
    final monthlyIncome = (userData['monthlyIncome'] as num?)
            ?.toDouble() ??
        0;
    final insuranceNumber = (userData['insuranceNumber']?.toString() ?? '').trim();
    final payoutAccountHolder =
        (userData['payoutAccountHolder']?.toString() ?? '').trim();
    final payoutBankName =
        (userData['payoutBankName']?.toString() ?? '').trim();
    final payoutAccountNumber =
        (userData['payoutAccountNumber']?.toString() ?? '').trim();
    if (insuranceNumber.isEmpty) {
      throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message:
            'Bạn cần nhập số bảo hiểm trước khi nộp hồ sơ vay.',
      );
    }

    final estimate = LoanCalculator.estimate(
      principal: amount,
      termWeeks: termWeeks,
    );

    final applicationRef = _firestore.collection('loanApplications').doc();
    await applicationRef
        .set({
          'uid': user.uid,
          'amount': amount,
          'appraisalFee': estimate.appraisalFee,
          'serviceFee': estimate.serviceFee,
          'netDisbursement': estimate.netDisbursement,
          'termWeeks': termWeeks,
          'monthlyIncome': monthlyIncome,
          'borrowerPayoutAccountHolder': payoutAccountHolder,
          'borrowerPayoutBankName': payoutBankName,
          'borrowerPayoutAccountNumber': payoutAccountNumber,
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
        })
        .timeout(_callableTimeout);

    return {
      'applicationId': applicationRef.id,
      'loanId': null,
      'status': 'reviewing',
      'message': 'Hồ sơ đã được ghi nhận và đang chờ thẩm định thủ công.',
    };
  }

  Future<void> _markRepaymentPaidFallback({
    required String loanId,
    required String scheduleId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Bạn cần đăng nhập lại trước khi cập nhật thanh toán.',
      );
    }

    final loanRef = _firestore.collection('loans').doc(loanId);
    final scheduleRef = loanRef.collection('repaymentSchedules').doc(scheduleId);

    await _firestore.runTransaction((transaction) async {
      final loanSnap = await transaction.get(loanRef);
      final scheduleSnap = await transaction.get(scheduleRef);

      if (!loanSnap.exists) {
        throw FirebaseFunctionsException(
          code: 'not-found',
          message: 'Không tìm thấy khoản vay.',
        );
      }

      if (!scheduleSnap.exists) {
        throw FirebaseFunctionsException(
          code: 'not-found',
          message: 'Không tìm thấy kỳ thanh toán.',
        );
      }

      final loan = loanSnap.data() ?? const <String, dynamic>{};
      if ((loan['uid'] ?? '').toString() != user.uid) {
        throw FirebaseFunctionsException(
          code: 'permission-denied',
          message: 'Bạn không có quyền cập nhật khoản vay này.',
        );
      }

      final schedule = scheduleSnap.data() ?? const <String, dynamic>{};
      if ((schedule['status'] ?? '').toString() == 'paid') {
        return;
      }

      final amountDue = ((schedule['totalDue'] ?? schedule['amount'] ?? 0) as num)
          .toDouble();

      transaction.update(scheduleRef, {
        'status': 'paid',
        'paidAmount': amountDue,
        'paidAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }).timeout(_callableTimeout);

    final remainingSchedules = await loanRef
        .collection('repaymentSchedules')
        .orderBy('installmentNo')
        .get()
        .timeout(_callableTimeout);

    final unpaidDocs = remainingSchedules.docs
        .where((doc) => (doc.data()['status'] ?? '').toString() != 'paid')
        .toList();

    await loanRef
        .set(
          {
            'status': unpaidDocs.isEmpty ? 'closed' : 'active',
            'nextDueDate':
                unpaidDocs.isEmpty ? null : unpaidDocs.first.data()['dueDate'],
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        )
        .timeout(_callableTimeout);
  }

  Future<Map<String, dynamic>> _reviewLoanApplicationFallback({
    required String applicationId,
    required String decision,
    String? decisionReason,
  }) async {
    final reviewer = _auth.currentUser;
    if (reviewer == null) {
      throw FirebaseFunctionsException(
        code: 'unauthenticated',
        message: 'Bạn cần đăng nhập lại trước khi duyệt hồ sơ.',
      );
    }

    final reviewerSnap = await _firestore
        .collection('users')
        .doc(reviewer.uid)
        .get()
        .timeout(_callableTimeout);
    final reviewerRole =
        ((reviewerSnap.data() ?? const <String, dynamic>{})['role'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    final reviewerData = reviewerSnap.data() ?? const <String, dynamic>{};
    if (reviewerRole != 'admin') {
      throw FirebaseFunctionsException(
        code: 'permission-denied',
        message: 'Chỉ tài khoản admin mới có quyền duyệt hồ sơ vay.',
      );
    }

    final normalizedDecision = decision.trim().toLowerCase();
    if (!const {'approved', 'rejected', 'reviewing'}
        .contains(normalizedDecision)) {
      throw FirebaseFunctionsException(
        code: 'invalid-argument',
        message: 'Trạng thái duyệt hồ sơ không hợp lệ.',
      );
    }

    final applicationRef =
        _firestore.collection('loanApplications').doc(applicationId);
    final applicationSnap =
        await applicationRef.get().timeout(_callableTimeout);
    if (!applicationSnap.exists) {
      throw FirebaseFunctionsException(
        code: 'not-found',
        message: 'Không tìm thấy hồ sơ vay.',
      );
    }

    final application = applicationSnap.data() ?? const <String, dynamic>{};
    final applicantUid = (application['uid'] ?? '').toString().trim();
    if (applicantUid.isEmpty) {
      throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Hồ sơ vay không có uid hợp lệ.',
      );
    }

    final resolvedReason = (decisionReason ?? '').trim().isNotEmpty
        ? decisionReason!.trim()
        : switch (normalizedDecision) {
            'approved' => 'Hồ sơ đã được duyệt thủ công.',
            'rejected' =>
              'Hồ sơ chưa được chấp thuận sau khi thẩm định thủ công.',
            _ => 'Hồ sơ đang được thẩm định thủ công.',
          };

    if (normalizedDecision == 'approved') {
      final existingLoanId = (application['approvedLoanId'] ?? '').toString();
      if (existingLoanId.trim().isNotEmpty) {
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Hồ sơ này đã được duyệt và có khoản vay đi kèm.',
        );
      }

      final amount = ((application['amount'] ?? 0) as num).toDouble();
      final termWeeks = ((application['termWeeks'] ?? 0) as num).toInt();
      if (amount <= 0 || termWeeks <= 0) {
        throw FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Hồ sơ vay đang thiếu dữ liệu để phê duyệt.',
        );
      }

      final estimate = LoanCalculator.estimate(
        principal: amount,
        termWeeks: termWeeks,
      );
      final loanRef = _firestore.collection('loans').doc();
      final now = FieldValue.serverTimestamp();
      final startDate = DateTime.now();
      final batch = _firestore.batch();

      batch.set(applicationRef, {
        'status': 'approved',
        'riskLevel': 'medium',
        'decisionReason': resolvedReason,
        'approvedLoanId': loanRef.id,
        'updatedAt': now,
      }, SetOptions(merge: true));

      batch.set(loanRef, {
        'uid': applicantUid,
        'applicationId': applicationId,
        'principal': amount,
        'appraisalFee': estimate.appraisalFee,
        'serviceFee': estimate.serviceFee,
        'netDisbursement': estimate.netDisbursement,
        'borrowerPayoutAccountHolder':
            (application['borrowerPayoutAccountHolder'] ?? '').toString(),
        'borrowerPayoutBankName':
            (application['borrowerPayoutBankName'] ?? '').toString(),
        'borrowerPayoutAccountNumber':
            (application['borrowerPayoutAccountNumber'] ?? '').toString(),
        'repaymentAccountHolder':
            (reviewerData['repaymentAccountHolder'] ?? '').toString(),
        'repaymentBankName':
            (reviewerData['repaymentBankName'] ?? '').toString(),
        'repaymentAccountNumber':
            (reviewerData['repaymentAccountNumber'] ?? '').toString(),
        'repaymentTransferNote': 'TRA NO ${loanRef.id}',
        'interestRate': LoanPolicy.fixedInterestRate,
        'termWeeks': termWeeks,
        'weeklyInstallment': estimate.weeklyInstallment,
        'totalInterest': estimate.totalInterest,
        'totalPayable': estimate.totalPayable,
        'overduePenaltyFee': LoanPolicy.overduePenaltyFee,
        'status': 'active',
        'nextDueDate': Timestamp.fromDate(_addDays(startDate, 7)),
        'createdAt': now,
        'approvedAt': now,
        'source': 'client_admin_fallback',
      });

      for (final installment in _buildRepaymentSchedule(
        loanId: loanRef.id,
        amount: amount,
        termWeeks: termWeeks,
        startDate: startDate,
      )) {
        batch.set(
          loanRef.collection('repaymentSchedules').doc(),
          installment,
        );
      }

      batch.set(
        _firestore.collection('users').doc(applicantUid),
        {
          'kycStatus': 'verified',
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );

      await batch.commit().timeout(_callableTimeout);

      return {
        'ok': true,
        'applicationId': applicationId,
        'loanId': loanRef.id,
        'status': 'approved',
        'message': resolvedReason,
      };
    }

    final existingLoanId = (application['approvedLoanId'] ?? '').toString();
    if (existingLoanId.trim().isNotEmpty) {
      throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message:
            'Hồ sơ này đã có khoản vay được tạo. Không thể đổi trạng thái.',
      );
    }

    final batch = _firestore.batch();
    final now = FieldValue.serverTimestamp();
    batch.set(applicationRef, {
      'status': normalizedDecision,
      'decisionReason': resolvedReason,
      'updatedAt': now,
    }, SetOptions(merge: true));
    batch.set(
      _firestore.collection('users').doc(applicantUid),
      {
        'kycStatus': 'submitted',
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );
    await batch.commit().timeout(_callableTimeout);

    return {
      'ok': true,
      'applicationId': applicationId,
      'loanId': null,
      'status': normalizedDecision,
      'message': resolvedReason,
    };
  }

  DateTime _addDays(DateTime baseDate, int days) {
    return DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day + days,
      9,
    );
  }

  List<Map<String, dynamic>> _buildRepaymentSchedule({
    required String loanId,
    required double amount,
    required int termWeeks,
    required DateTime startDate,
  }) {
    final dailyInterestRate = LoanPolicy.fixedInterestRate / 30;
    final weeklyInterestRate = dailyInterestRate * 7;
    
    final baseInterest = (amount * weeklyInterestRate).round();
    final totalInterest = baseInterest * termWeeks;
    
    final basePrincipal = amount ~/ termWeeks;
    var remainingPrincipal = amount;
    var remainingInterest = totalInterest.toDouble();

    return List.generate(termWeeks, (index) {
      final installmentNo = index + 1;
      final principalAmount =
          installmentNo == termWeeks ? remainingPrincipal : basePrincipal.toDouble();
      final interestAmount =
          installmentNo == termWeeks ? remainingInterest : baseInterest.toDouble();
      final openingBalance = remainingPrincipal;
      final closingBalance = (openingBalance - principalAmount).clamp(0, amount);
      final amountDue = principalAmount + interestAmount;

      remainingPrincipal = closingBalance.toDouble();
      remainingInterest = (remainingInterest - interestAmount).clamp(0, totalInterest.toDouble());

      return {
        'loanId': loanId,
        'installmentNo': installmentNo,
        'dueDate': Timestamp.fromDate(_addDays(startDate, installmentNo * 7)),
        'amount': amountDue,
        'principalAmount': principalAmount,
        'interestAmount': interestAmount,
        'openingBalance': openingBalance,
        'closingBalance': closingBalance,
        'overduePenaltyFee': LoanPolicy.overduePenaltyFee,
        'lateFeeAmount': 0,
        'totalDue': amountDue,
        'paidAmount': 0,
        'status': 'unpaid',
        'paidAt': null,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
    });
  }
}

String translateFunctionsError(Object error) {
  if (error is TimeoutException) {
    return 'Hệ thống đang phản hồi chậm. Vui lòng thử lại sau ít phút.';
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
      case 'not-found':
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'Không tìm thấy dữ liệu cần cập nhật.';
      case 'permission-denied':
        return error.message?.trim().isNotEmpty == true
            ? error.message!.trim()
            : 'Bạn không có quyền thực hiện thao tác này.';
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
