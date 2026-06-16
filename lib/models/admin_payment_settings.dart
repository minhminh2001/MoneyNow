class AdminPaymentSettings {
  const AdminPaymentSettings({
    required this.repaymentAccountHolder,
    required this.repaymentBankName,
    required this.repaymentAccountNumber,
    required this.updatedBy,
    required this.updatedAt,
  });

  final String repaymentAccountHolder;
  final String repaymentBankName;
  final String repaymentAccountNumber;
  final String updatedBy;
  final DateTime? updatedAt;

  bool get isConfigured =>
      repaymentAccountHolder.isNotEmpty ||
      repaymentBankName.isNotEmpty ||
      repaymentAccountNumber.isNotEmpty;

  factory AdminPaymentSettings.empty() {
    return const AdminPaymentSettings(
      repaymentAccountHolder: '',
      repaymentBankName: '',
      repaymentAccountNumber: '',
      updatedBy: '',
      updatedAt: null,
    );
  }

  factory AdminPaymentSettings.fromMap(Map<String, dynamic> map) {
    DateTime? readDate(dynamic value) {
      if (value is DateTime) return value;
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      return null;
    }

    String readString(dynamic value) => value?.toString().trim() ?? '';

    return AdminPaymentSettings(
      repaymentAccountHolder: readString(map['repaymentAccountHolder']),
      repaymentBankName: readString(map['repaymentBankName']),
      repaymentAccountNumber: readString(map['repaymentAccountNumber']),
      updatedBy: readString(map['updatedBy']),
      updatedAt: readDate(map['updatedAt']),
    );
  }
}
