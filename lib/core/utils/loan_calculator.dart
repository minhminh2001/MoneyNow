import '../constants/loan_policy.dart';

class LoanEstimate {
  const LoanEstimate({
    required this.appraisalFee,
    required this.serviceFee,
    required this.netDisbursement,
    required this.weeklyInstallment,
    required this.weeklyInterest,
    required this.totalInterest,
    required this.totalPayable,
  });

  final double appraisalFee;
  final double serviceFee;
  final double netDisbursement;
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
        appraisalFee: 0,
        serviceFee: 0,
        netDisbursement: 0,
        weeklyInstallment: 0,
        weeklyInterest: 0,
        totalInterest: 0,
        totalPayable: 0,
      );
    }

    final dailyInterestRate = LoanPolicy.fixedInterestRate / 30;
    final weeklyInterestRate = dailyInterestRate * 7;
    
    final appraisalFee =
        (principal * LoanPolicy.appraisalFeeRate).roundToDouble();
    final serviceFee =
        (principal * LoanPolicy.serviceFeeRate).roundToDouble();
    final netDisbursement =
        (principal - appraisalFee - serviceFee).roundToDouble();
    final weeklyInterest = (principal * weeklyInterestRate).roundToDouble();
    final totalInterest = (weeklyInterest * termWeeks).roundToDouble();
    
    final totalPayable = principal + totalInterest;
    final weeklyInstallment = (principal / termWeeks).roundToDouble() + weeklyInterest;

    return LoanEstimate(
      appraisalFee: appraisalFee,
      serviceFee: serviceFee,
      netDisbursement: netDisbursement,
      weeklyInstallment: weeklyInstallment,
      weeklyInterest: weeklyInterest,
      totalInterest: totalInterest.roundToDouble(),
      totalPayable: totalPayable.roundToDouble(),
    );
  }
}
