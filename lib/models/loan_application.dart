import '../core/utils/firestore_value.dart';

class LoanApplication {
  const LoanApplication({
    required this.id,
    required this.uid,
    required this.amount,
    required this.termWeeks,
    required this.monthlyIncome,
    required this.weeklyInstallment,
    required this.interestRate,
    required this.overduePenaltyFee,
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
  final int termWeeks;
  final double monthlyIncome;
  final double weeklyInstallment;
  final double interestRate;
  final double overduePenaltyFee;
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
      termWeeks: () {
        final value = readInt(map['termWeeks']);
        if (value > 0) return value;
        final legacyValue = readInt(map['termMonths']);
        return legacyValue == 0 ? 6 : legacyValue;
      }(),
      monthlyIncome: readDouble(map['monthlyIncome']),
      weeklyInstallment: () {
        final value = readDouble(map['weeklyInstallment']);
        if (value > 0) return value;
        return readDouble(map['monthlyInstallment']);
      }(),
      interestRate: () {
        final value = readDouble(map['interestRate']);
        if (value > 0) return value;
        return readDouble(map['interestRateMonthly']);
      }(),
      overduePenaltyFee: readDouble(map['overduePenaltyFee']),
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
