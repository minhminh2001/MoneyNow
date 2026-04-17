import '../core/utils/firestore_value.dart';

class LoanDraft {
  const LoanDraft({
    required this.phone,
    required this.requestedAmount,
    required this.termMonths,
    required this.monthlyIncome,
    required this.employer,
    required this.purpose,
    required this.currentStep,
    required this.updatedAt,
  });

  final String phone;
  final double requestedAmount;
  final int termMonths;
  final double monthlyIncome;
  final String employer;
  final String purpose;
  final int currentStep;
  final DateTime? updatedAt;

  factory LoanDraft.empty() {
    return LoanDraft(
      phone: '',
      requestedAmount: 0,
      termMonths: 6,
      monthlyIncome: 0,
      employer: '',
      purpose: '',
      currentStep: 1,
      updatedAt: DateTime.now(),
    );
  }

  factory LoanDraft.fromMap(Map<String, dynamic> map) {
    return LoanDraft(
      phone: readString(map['phone']),
      requestedAmount: readDouble(map['requestedAmount']),
      termMonths:
          readInt(map['termMonths']) == 0 ? 6 : readInt(map['termMonths']),
      monthlyIncome: readDouble(map['monthlyIncome']),
      employer: readString(map['employer']),
      purpose: readString(map['purpose']),
      currentStep:
          readInt(map['currentStep']) == 0 ? 1 : readInt(map['currentStep']),
      updatedAt: readDateTime(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'phone': phone,
      'requestedAmount': requestedAmount,
      'termMonths': termMonths,
      'monthlyIncome': monthlyIncome,
      'employer': employer,
      'purpose': purpose,
      'currentStep': currentStep,
      'updatedAt': updatedAt ?? DateTime.now(),
    };
  }
}
