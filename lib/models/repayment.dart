import '../core/utils/firestore_value.dart';

class Repayment {
  const Repayment({
    required this.id,
    required this.loanId,
    required this.installmentNo,
    required this.dueDate,
    required this.amount,
    required this.principalAmount,
    required this.interestAmount,
    required this.openingBalance,
    required this.closingBalance,
    required this.paidAmount,
    required this.status,
    required this.paidAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String loanId;
  final int installmentNo;
  final DateTime? dueDate;
  final double amount;

  /// Phần gốc trong kỳ thanh toán này.
  final double principalAmount;

  /// Phần lãi trong kỳ thanh toán này.
  final double interestAmount;

  /// Dư nợ đầu kỳ (trước khi thanh toán).
  final double openingBalance;

  /// Dư nợ cuối kỳ (sau khi thanh toán) — dùng để vẽ line chart.
  final double closingBalance;

  final double paidAmount;
  final String status;
  final DateTime? paidAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Repayment.fromMap(String id, Map<String, dynamic> map) {
    return Repayment(
      id: id,
      loanId: readString(map['loanId']),
      installmentNo: readInt(map['installmentNo']),
      dueDate: readDateTime(map['dueDate']),
      amount: readDouble(map['amount']),
      principalAmount: readDouble(map['principalAmount']),
      interestAmount: readDouble(map['interestAmount']),
      openingBalance: readDouble(map['openingBalance']),
      closingBalance: readDouble(map['closingBalance']),
      paidAmount: readDouble(map['paidAmount']),
      status: readString(map['status']),
      paidAt: readDateTime(map['paidAt']),
      createdAt: readDateTime(map['createdAt']),
      updatedAt: readDateTime(map['updatedAt']),
    );
  }
}

