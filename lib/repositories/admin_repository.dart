import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/admin_payment_settings.dart';
import '../models/loan.dart';
import '../models/loan_application.dart';

class AdminDashboardData {
  const AdminDashboardData({
    required this.applications,
    required this.loans,
    required this.userSummaries,
  });

  final List<LoanApplication> applications;
  final List<Loan> loans;
  final Map<String, Map<String, dynamic>> userSummaries;
}

class AccountDeletionRequest {
  const AccountDeletionRequest({
    required this.uid,
    required this.status,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.activeLoanCount,
    required this.loanCount,
    required this.applicationCount,
    required this.requestedAt,
  });

  final String uid;
  final String status;
  final String fullName;
  final String phone;
  final String email;
  final int activeLoanCount;
  final int loanCount;
  final int applicationCount;
  final DateTime? requestedAt;

  factory AccountDeletionRequest.fromMap(Map<String, dynamic> map) {
    String readString(Object? value) => (value ?? '').toString();
    int readInt(Object? value) => int.tryParse((value ?? 0).toString()) ?? 0;
    DateTime? readDate(Object? value) {
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is num) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      }
      return null;
    }

    return AccountDeletionRequest(
      uid: readString(map['uid'] ?? map['id']),
      status: readString(map['status']),
      fullName: readString(map['fullName']),
      phone: readString(map['phone']),
      email: readString(map['email']),
      activeLoanCount: readInt(map['activeLoanCount']),
      loanCount: readInt(map['loanCount']),
      applicationCount: readInt(map['applicationCount']),
      requestedAt: readDate(map['requestedAt']),
    );
  }
}

class AdminRepository {
  AdminRepository({
    required FirebaseFirestore firestore,
    required FirebaseFunctions functions,
    required FirebaseAuth auth,
  })  : _firestore = firestore,
        _functions = functions,
        _auth = auth;

  static const Duration _callableTimeout = Duration(seconds: 20);

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
        message: 'Bạn cần đăng nhập lại trước khi vào khu quản trị.',
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

  Future<AdminDashboardData> fetchDashboard() async {
    try {
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

      return AdminDashboardData(
        applications: applications,
        loans: loans,
        userSummaries: userSummaries,
      );
    } on FirebaseFunctionsException catch (error) {
      if (error.code != 'internal') rethrow;
      return _fetchDashboardFromFirestore();
    }
  }

  Future<AdminDashboardData> _fetchDashboardFromFirestore() async {
    final applicationsSnapshot = await _firestore
        .collection('loanApplications')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .get()
        .timeout(_callableTimeout);

    final loansSnapshot = await _firestore
        .collection('loans')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .get()
        .timeout(_callableTimeout);

    final applications = applicationsSnapshot.docs
        .map((doc) => LoanApplication.fromMap(doc.id, doc.data()))
        .toList();
    final loans = loansSnapshot.docs
        .map((doc) => Loan.fromMap(doc.id, doc.data()))
        .toList();

    final neededUids = <String>{
      ...applications.map((item) => item.uid.trim()).where((item) => item.isNotEmpty),
      ...loans.map((item) => item.uid.trim()).where((item) => item.isNotEmpty),
    };

    final userDocs = await Future.wait(
      neededUids.map(
        (uid) => _firestore.collection('users').doc(uid).get(),
      ),
    );

    final userSummaries = <String, Map<String, dynamic>>{};
    for (final userDoc in userDocs) {
      final data = userDoc.data();
      if (data == null) continue;
      userSummaries[userDoc.id] = {
        'uid': userDoc.id,
        'fullName': (data['fullName'] ?? '').toString(),
        'email': (data['email'] ?? '').toString(),
        'phone': (data['phone'] ?? '').toString(),
        'role': (data['role'] ?? '').toString(),
        'kycStatus': (data['kycStatus'] ?? '').toString(),
      };
    }

    return AdminDashboardData(
      applications: applications,
      loans: loans,
      userSummaries: userSummaries,
    );
  }

  Future<Map<String, dynamic>> reviewLoanApplication({
    required String applicationId,
    required String decision,
    String? decisionReason,
  }) async {
    final (_, token) = await _requireFreshUserForCurrentProject();
    final callable = _functionsForActiveSession().httpsCallable(
      'reviewLoanApplicationManual',
    );
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

  Future<AdminPaymentSettings> fetchPaymentSettings() async {
    final (_, token) = await _requireFreshUserForCurrentProject();
    final callable = _functionsForActiveSession().httpsCallable(
      'fetchAdminPaymentSettings',
    );
    final result = await callable
        .call<Map<String, dynamic>>({
          'idToken': token,
        })
        .timeout(_callableTimeout);
    return AdminPaymentSettings.fromMap(Map<String, dynamic>.from(result.data));
  }

  Future<AdminPaymentSettings> savePaymentSettings({
    required String repaymentAccountHolder,
    required String repaymentBankName,
    required String repaymentAccountNumber,
  }) async {
    final (_, token) = await _requireFreshUserForCurrentProject();
    final callable = _functionsForActiveSession().httpsCallable(
      'saveAdminPaymentSettings',
    );
    final result = await callable
        .call<Map<String, dynamic>>({
          'idToken': token,
          'repaymentAccountHolder': repaymentAccountHolder,
          'repaymentBankName': repaymentBankName,
          'repaymentAccountNumber': repaymentAccountNumber,
        })
        .timeout(_callableTimeout);
    return AdminPaymentSettings.fromMap(Map<String, dynamic>.from(result.data));
  }

  Future<List<AccountDeletionRequest>> fetchAccountDeletionRequests() async {
    final (_, token) = await _requireFreshUserForCurrentProject();
    final callable = _functionsForActiveSession().httpsCallable(
      'fetchAccountDeletionRequests',
    );
    final result = await callable.call<Map<String, dynamic>>({
      'idToken': token,
    }).timeout(_callableTimeout);
    final data = Map<String, dynamic>.from(result.data);
    final requestsRaw = (data['requests'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    return requestsRaw.map(AccountDeletionRequest.fromMap).toList();
  }

  Future<void> rejectAccountDeletionRequest({
    required String uid,
    String reason = '',
  }) async {
    final (_, token) = await _requireFreshUserForCurrentProject();
    final callable = _functionsForActiveSession().httpsCallable(
      'rejectAccountDeletionRequest',
    );
    await callable.call<Map<String, dynamic>>({
      'idToken': token,
      'uid': uid,
      'reason': reason,
    }).timeout(_callableTimeout);
  }

  Future<void> approveAccountDeletionRequest({
    required String uid,
  }) async {
    final (_, token) = await _requireFreshUserForCurrentProject();
    final callable = _functionsForActiveSession().httpsCallable(
      'approveAccountDeletionRequest',
    );
    await callable.call<Map<String, dynamic>>({
      'idToken': token,
      'uid': uid,
    }).timeout(const Duration(seconds: 60));
  }
}
