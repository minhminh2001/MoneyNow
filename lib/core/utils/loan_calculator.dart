import 'dart:math' as math;

class LoanEstimate {
  const LoanEstimate({
    required this.monthlyInstallment,
    required this.totalInterest,
    required this.totalPayable,
  });

  final double monthlyInstallment;
  final double totalInterest;
  final double totalPayable;
}

class LoanCalculator {
  static const double monthlyInterestRate = 0.018;

  static LoanEstimate estimate({
    required double principal,
    required int termMonths,
  }) {
    if (principal <= 0 || termMonths <= 0) {
      return const LoanEstimate(
        monthlyInstallment: 0,
        totalInterest: 0,
        totalPayable: 0,
      );
    }

    final rate = monthlyInterestRate;
    final rawMonthlyInstallment = rate == 0
        ? principal / termMonths
        : principal * rate / (1 - math.pow(1 + rate, -termMonths));
    final monthlyInstallment = rawMonthlyInstallment.roundToDouble();

    var remainingBalance = principal;
    var totalInterest = 0.0;

    for (var installmentNo = 1; installmentNo <= termMonths; installmentNo += 1) {
      final interestAmount = (remainingBalance * rate).roundToDouble();
      final principalAmount = installmentNo == termMonths
          ? remainingBalance.roundToDouble()
          : math.max(0, monthlyInstallment - interestAmount).roundToDouble();
      remainingBalance =
          math.max(0, remainingBalance - principalAmount).roundToDouble();
      totalInterest += interestAmount;
    }

    final totalPayable = principal + totalInterest;

    return LoanEstimate(
      monthlyInstallment: monthlyInstallment,
      totalInterest: totalInterest.roundToDouble(),
      totalPayable: totalPayable.roundToDouble(),
    );
  }
}
