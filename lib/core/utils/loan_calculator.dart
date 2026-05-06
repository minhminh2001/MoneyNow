import '../constants/loan_policy.dart';

class LoanEstimate {
  const LoanEstimate({
    required this.weeklyInstallment,
    required this.weeklyInterest,
    required this.totalInterest,
    required this.totalPayable,
  });

  final double weeklyInstallment;
  final double weeklyInterest;
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
        weeklyInterest: 0,
        totalInterest: 0,
        totalPayable: 0,
      );
    }

    final dailyInterestRate = LoanPolicy.fixedInterestRate / 30;
    final weeklyInterestRate = dailyInterestRate * 7;
    
    final weeklyInterest = (principal * weeklyInterestRate).roundToDouble();
    final totalInterest = (weeklyInterest * termWeeks).roundToDouble();
    
    final totalPayable = principal + totalInterest;
    final weeklyInstallment = (principal / termWeeks).roundToDouble() + weeklyInterest;

    return LoanEstimate(
      weeklyInstallment: weeklyInstallment,
      weeklyInterest: weeklyInterest,
      totalInterest: totalInterest.roundToDouble(),
      totalPayable: totalPayable.roundToDouble(),
    );
  }
}
