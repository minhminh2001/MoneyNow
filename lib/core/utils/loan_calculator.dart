import '../constants/loan_policy.dart';

class LoanEstimate {
  const LoanEstimate({
    required this.weeklyInstallment,
    required this.totalInterest,
    required this.totalPayable,
  });

  final double weeklyInstallment;
  final double totalInterest;
  final double totalPayable;
}

class LoanCalculator {
  static LoanEstimate estimate({
    required double principal,
    required int termWeeks,
  }) {
    if (principal <= 0 || termWeeks <= 0) {
      return const LoanEstimate(
        weeklyInstallment: 0,
        totalInterest: 0,
        totalPayable: 0,
      );
    }

    final totalInterest =
        (principal * LoanPolicy.fixedInterestRate).roundToDouble();
    final totalPayable = principal + totalInterest;
    final weeklyInstallment = (totalPayable / termWeeks).roundToDouble();

    return LoanEstimate(
      weeklyInstallment: weeklyInstallment,
      totalInterest: totalInterest.roundToDouble(),
      totalPayable: totalPayable.roundToDouble(),
    );
  }
}
