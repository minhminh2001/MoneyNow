import '../core/utils/firestore_value.dart';

class Loan {
  const Loan({
    required this.id,
    required this.uid,
    required this.applicationId,
    required this.principal,
    required this.appraisalFee,
    required this.serviceFee,
    required this.netDisbursement,
    required this.interestRate,
    required this.termWeeks,
    required this.weeklyInstallment,
    required this.overduePenaltyFee,
    required this.borrowerPayoutAccountHolder,
    required this.borrowerPayoutBankName,
    required this.borrowerPayoutAccountNumber,
    required this.repaymentAccountHolder,
    required this.repaymentBankName,
    required this.repaymentAccountNumber,
    required this.repaymentTransferNote,
    required this.status,
    required this.nextDueDate,
    required this.createdAt,
    required this.approvedAt,
  });

  final String id;
  final String uid;
  final String applicationId;
  final double principal;
  final double appraisalFee;
  final double serviceFee;
  final double netDisbursement;
  final double interestRate;
  final int termWeeks;
  final double weeklyInstallment;
  final double overduePenaltyFee;
  final String borrowerPayoutAccountHolder;
  final String borrowerPayoutBankName;
  final String borrowerPayoutAccountNumber;
  final String repaymentAccountHolder;
  final String repaymentBankName;
  final String repaymentAccountNumber;
  final String repaymentTransferNote;
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
      appraisalFee: readDouble(map['appraisalFee']),
      serviceFee: readDouble(map['serviceFee']),
      netDisbursement: () {
        final value = readDouble(map['netDisbursement']);
        if (value > 0) return value;
        return readDouble(map['principal']) -
            readDouble(map['appraisalFee']) -
            readDouble(map['serviceFee']);
      }(),
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
      borrowerPayoutAccountHolder:
          readString(map['borrowerPayoutAccountHolder']),
      borrowerPayoutBankName: readString(map['borrowerPayoutBankName']),
      borrowerPayoutAccountNumber:
          readString(map['borrowerPayoutAccountNumber']),
      repaymentAccountHolder: readString(map['repaymentAccountHolder']),
      repaymentBankName: readString(map['repaymentBankName']),
      repaymentAccountNumber: readString(map['repaymentAccountNumber']),
      repaymentTransferNote: readString(map['repaymentTransferNote']),
      status: readString(map['status']),
      nextDueDate: readDateTime(map['nextDueDate']),
      createdAt: readDateTime(map['createdAt']),
      approvedAt: readDateTime(map['approvedAt']),
    );
  }
}
