import '../core/utils/firestore_value.dart';

class LoanDraft {
  const LoanDraft({
    required this.phone,
    required this.requestedAmount,
    required this.termWeeks,
    required this.monthlyIncome,
    required this.employer,
    required this.purpose,
    required this.currentStep,
    required this.updatedAt,
  });

  final String phone;
  final double requestedAmount;
  final int termWeeks;
  final double monthlyIncome;
  final String employer;
  final String purpose;
  final int currentStep;
  final DateTime? updatedAt;

  factory LoanDraft.empty() {
    return LoanDraft(
      phone: '',
      requestedAmount: 0,
      termWeeks: 6,
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
      termWeeks: () {
        final value = readInt(map['termWeeks']);
        if (value > 0) return value;
        final legacyValue = readInt(map['termMonths']);
        return legacyValue == 0 ? 6 : legacyValue;
      }(),
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
      'termWeeks': termWeeks,
      'monthlyIncome': monthlyIncome,
      'employer': employer,
      'purpose': purpose,
      'currentStep': currentStep,
      'updatedAt': updatedAt ?? DateTime.now(),
    };
  }
}
