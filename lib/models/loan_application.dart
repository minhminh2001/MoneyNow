import '../core/utils/firestore_value.dart';

class LoanApplication {
  const LoanApplication({
    required this.id,
    required this.uid,
    required this.amount,
    required this.termMonths,
    required this.monthlyIncome,
    required this.monthlyInstallment,
    required this.purpose,
    required this.status,
    required this.riskLevel,
    required this.decisionReason,
    required this.approvedLoanId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String uid;
  final double amount;
  final int termMonths;
  final double monthlyIncome;
  final double monthlyInstallment;
  final String purpose;
  final String status;
  final String riskLevel;
  final String decisionReason;
  final String? approvedLoanId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory LoanApplication.fromMap(String id, Map<String, dynamic> map) {
    final approvedLoanId = readString(map['approvedLoanId']);
    return LoanApplication(
      id: id,
      uid: readString(map['uid']),
      amount: readDouble(map['amount']),
      termMonths: readInt(map['termMonths']),
      monthlyIncome: readDouble(map['monthlyIncome']),
      monthlyInstallment: readDouble(map['monthlyInstallment']),
      purpose: readString(map['purpose']),
      status: readString(map['status']),
      riskLevel: readString(map['riskLevel']),
      decisionReason: readString(map['decisionReason']),
      approvedLoanId: approvedLoanId.isEmpty ? null : approvedLoanId,
      createdAt: readDateTime(map['createdAt']),
      updatedAt: readDateTime(map['updatedAt']),
    );
  }
}
