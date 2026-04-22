import '../core/utils/firestore_value.dart';

class Loan {
  const Loan({
    required this.id,
    required this.uid,
    required this.applicationId,
    required this.principal,
    required this.interestRate,
    required this.termWeeks,
    required this.weeklyInstallment,
    required this.overduePenaltyFee,
    required this.status,
    required this.nextDueDate,
    required this.createdAt,
    required this.approvedAt,
  });

  final String id;
  final String uid;
  final String applicationId;
  final double principal;
  final double interestRate;
  final int termWeeks;
  final double weeklyInstallment;
  final double overduePenaltyFee;
  final String status;
  final DateTime? nextDueDate;
  final DateTime? createdAt;
  final DateTime? approvedAt;

  int get termDays => termWeeks * 7;

  factory Loan.fromMap(String id, Map<String, dynamic> map) {
    return Loan(
      id: id,
      uid: readString(map['uid']),
      applicationId: readString(map['applicationId']),
      principal: readDouble(map['principal']),
      interestRate: () {
        final value = readDouble(map['interestRate']);
        if (value > 0) return value;
        return readDouble(map['interestRateMonthly']);
      }(),
      termWeeks: () {
        final value = readInt(map['termWeeks']);
        if (value > 0) return value;
        final legacyValue = readInt(map['termMonths']);
        return legacyValue == 0 ? 6 : legacyValue;
      }(),
      weeklyInstallment: () {
        final value = readDouble(map['weeklyInstallment']);
        if (value > 0) return value;
        return readDouble(map['monthlyInstallment']);
      }(),
      overduePenaltyFee: () {
        final value = readDouble(map['overduePenaltyFee']);
        if (value > 0) return value;
        return readDouble(map['lateFeeAmount']);
      }(),
      status: readString(map['status']),
      nextDueDate: readDateTime(map['nextDueDate']),
      createdAt: readDateTime(map['createdAt']),
      approvedAt: readDateTime(map['approvedAt']),
    );
  }
}
