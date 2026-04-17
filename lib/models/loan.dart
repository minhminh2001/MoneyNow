import '../core/utils/firestore_value.dart';

class Loan {
  const Loan({
    required this.id,
    required this.uid,
    required this.applicationId,
    required this.principal,
    required this.interestRateMonthly,
    required this.termMonths,
    required this.monthlyInstallment,
    required this.status,
    required this.nextDueDate,
    required this.createdAt,
    required this.approvedAt,
  });

  final String id;
  final String uid;
  final String applicationId;
  final double principal;
  final double interestRateMonthly;
  final int termMonths;
  final double monthlyInstallment;
  final String status;
  final DateTime? nextDueDate;
  final DateTime? createdAt;
  final DateTime? approvedAt;

  factory Loan.fromMap(String id, Map<String, dynamic> map) {
    return Loan(
      id: id,
      uid: readString(map['uid']),
      applicationId: readString(map['applicationId']),
      principal: readDouble(map['principal']),
      interestRateMonthly: readDouble(map['interestRateMonthly']),
      termMonths: readInt(map['termMonths']),
      monthlyInstallment: readDouble(map['monthlyInstallment']),
      status: readString(map['status']),
      nextDueDate: readDateTime(map['nextDueDate']),
      createdAt: readDateTime(map['createdAt']),
      approvedAt: readDateTime(map['approvedAt']),
    );
  }
}
