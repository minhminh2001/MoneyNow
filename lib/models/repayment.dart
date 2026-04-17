import '../core/utils/firestore_value.dart';

class Repayment {
  const Repayment({
    required this.id,
    required this.loanId,
    required this.installmentNo,
    required this.dueDate,
    required this.amount,
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
      paidAmount: readDouble(map['paidAmount']),
      status: readString(map['status']),
      paidAt: readDateTime(map['paidAt']),
      createdAt: readDateTime(map['createdAt']),
      updatedAt: readDateTime(map['updatedAt']),
    );
  }
}
