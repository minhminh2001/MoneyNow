import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/loan.dart';
import '../../models/loan_application.dart';
import '../../models/repayment.dart';
import '../../providers/app_providers.dart';

class LoanChartsScreen extends ConsumerWidget {
  const LoanChartsScreen({super.key, this.initialLoan});

  final Loan? initialLoan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(loansProvider).value ?? [];
    final applications = ref.watch(loanApplicationsProvider).value ?? [];

    final loan = initialLoan ??
        loans.cast<Loan?>().firstWhere(
              (l) => l?.status == 'active',
              orElse: () => loans.isNotEmpty ? loans.first : null,
            );

    final schedules = loan != null
        ? (ref.watch(repaymentScheduleProvider(loan.id)).value ?? <Repayment>[])
        : <Repayment>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Biểu đồ tài chính')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (loan != null) ...[
            _SummaryRow(loan: loan, schedules: schedules),
            const SizedBox(height: 16),
            _ChartCard(
              title: 'Tiến độ trả nợ',
              subtitle: '${loan.termMonths} kỳ · ${AppFormatters.currency(loan.principal)}',
              icon: Icons.donut_large_rounded,
              child: schedules.isEmpty
                  ? const _EmptyChart()
                  : _DonutChart(schedules: schedules),
            ),
            const SizedBox(height: 16),
            _ChartCard(
              title: 'Dư nợ giảm dần',
              subtitle: 'Số dư còn lại sau mỗi kỳ thanh toán',
              icon: Icons.trending_down_rounded,
              child: schedules.isEmpty
                  ? const _EmptyChart()
                  : _BalanceLineChart(loan: loan, schedules: schedules),
            ),
            const SizedBox(height: 16),
          ],
          if (loan == null)
            _NoLoanCard(),
          _ChartCard(
            title: 'Lịch sử hồ sơ vay',
            subtitle: '${applications.length} hồ sơ đã nộp',
            icon: Icons.bar_chart_rounded,
            child: applications.isEmpty
                ? const _EmptyChart(message: 'Chưa có hồ sơ vay nào.')
                : _ApplicationBarChart(applications: applications),
          ),
        ],
      ),
    );
  }
}

// ─── Summary Row ──────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.loan, required this.schedules});

  final Loan loan;
  final List<Repayment> schedules;

  @override
  Widget build(BuildContext context) {
    final paid = schedules.where((s) => s.status == 'paid').length;
    final total = schedules.length;
    final paidAmount = schedules
        .where((s) => s.status == 'paid')
        .fold(0.0, (sum, s) => sum + s.paidAmount);
    final remaining = loan.principal - paidAmount;

    return Row(
      children: [
        _StatChip(label: 'Đã trả', value: '$paid/$total kỳ', color: const Color(0xFFE46A11)),
        const SizedBox(width: 8),
        _StatChip(
          label: 'Còn lại',
          value: AppFormatters.currency(remaining.clamp(0, double.infinity)),
          color: const Color(0xFF1565C0),
        ),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: color, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

// ─── Chart Card Container ─────────────────────────────────────────────────────

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE46A11).withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0E4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: const Color(0xFFE46A11), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF8A9BAE), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(height: 220, child: child),
          ],
        ),
      ),
    );
  }
}

// ─── Donut Chart ──────────────────────────────────────────────────────────────

class _DonutChart extends StatelessWidget {
  const _DonutChart({required this.schedules});

  final List<Repayment> schedules;

  @override
  Widget build(BuildContext context) {
    final paid = schedules.where((s) => s.status == 'paid').length;
    final overdue = schedules.where((s) => s.status == 'overdue').length;
    final unpaid = schedules.length - paid - overdue;

    final sections = <PieChartSectionData>[
      if (paid > 0)
        PieChartSectionData(
          value: paid.toDouble(),
          color: const Color(0xFFE46A11),
          radius: 52,
          title: '$paid',
          titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
        ),
      if (overdue > 0)
        PieChartSectionData(
          value: overdue.toDouble(),
          color: const Color(0xFFD32F2F),
          radius: 52,
          title: '$overdue',
          titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
        ),
      if (unpaid > 0)
        PieChartSectionData(
          value: unpaid.toDouble(),
          color: const Color(0xFFE8F0F5),
          radius: 52,
          title: '$unpaid',
          titleStyle: const TextStyle(color: Color(0xFF8A9BAE), fontWeight: FontWeight.w700, fontSize: 14),
        ),
    ];

    final total = schedules.length;
    final paidPct = total > 0 ? (paid / total * 100).toStringAsFixed(0) : '0';

    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sections: sections.isEmpty
                  ? [PieChartSectionData(value: 1, color: const Color(0xFFE8F0F5), radius: 52, title: '')]
                  : sections,
              centerSpaceRadius: 52,
              sectionsSpace: 3,
              startDegreeOffset: -90,
            ),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
          ),
        ),
        const SizedBox(width: 16),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$paidPct%',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(color: const Color(0xFFE46A11))),
            const Text('đã thanh toán',
                style: TextStyle(color: Color(0xFF8A9BAE), fontSize: 12)),
            const SizedBox(height: 14),
            _Legend(color: const Color(0xFFE46A11), label: 'Đã trả ($paid)'),
            const SizedBox(height: 6),
            _Legend(color: const Color(0xFFD32F2F), label: 'Quá hạn ($overdue)'),
            const SizedBox(height: 6),
            _Legend(color: const Color(0xFFE8F0F5), label: 'Còn lại ($unpaid)', textColor: const Color(0xFF8A9BAE)),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.textColor});

  final Color color;
  final String label;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: textColor ?? const Color(0xFF12343B),
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

// ─── Balance Line Chart ───────────────────────────────────────────────────────

class _BalanceLineChart extends StatelessWidget {
  const _BalanceLineChart({required this.loan, required this.schedules});

  final Loan loan;
  final List<Repayment> schedules;

  @override
  Widget build(BuildContext context) {
    final sorted = [...schedules]
      ..sort((a, b) => a.installmentNo.compareTo(b.installmentNo));

    // Điểm 0 = dư nợ ban đầu (gốc vay), sau đó closingBalance mỗi kỳ
    final spots = <FlSpot>[
      FlSpot(0, loan.principal),
      ...sorted.map((s) => FlSpot(s.installmentNo.toDouble(), s.closingBalance)),
    ];

    final maxY = loan.principal * 1.05;
    final intervalY = (loan.principal / 4).ceilToDouble();

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: loan.termMonths.toDouble(),
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: intervalY,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Color(0xFFF0F4F8), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              interval: intervalY,
              getTitlesWidget: (v, _) => Text(
                _fmtM(v),
                style: const TextStyle(fontSize: 10, color: Color(0xFF8A9BAE)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: (loan.termMonths / 4).ceilToDouble(),
              getTitlesWidget: (v, _) => Text(
                v == 0 ? 'Đầu' : 'Kỳ ${v.toInt()}',
                style: const TextStyle(fontSize: 10, color: Color(0xFF8A9BAE)),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.35,
            gradient: const LinearGradient(
              colors: [Color(0xFFE46A11), Color(0xFFFFA145)],
            ),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                radius: 3,
                color: Colors.white,
                strokeWidth: 2,
                strokeColor: const Color(0xFFE46A11),
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFE46A11).withValues(alpha: 0.15),
                  const Color(0xFFE46A11).withValues(alpha: 0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF12343B),
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      AppFormatters.currency(s.y),
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                    ))
                .toList(),
          ),
        ),
      ),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  }
}

// ─── Application Bar Chart ────────────────────────────────────────────────────

class _ApplicationBarChart extends StatelessWidget {
  const _ApplicationBarChart({required this.applications});

  final List<LoanApplication> applications;

  Color _barColor(String status) {
    switch (status) {
      case 'approved':
        return const Color(0xFFE46A11);
      case 'rejected':
        return const Color(0xFFD32F2F);
      case 'reviewing':
        return const Color(0xFF1565C0);
      default:
        return const Color(0xFF8A9BAE);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...applications]
      ..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));

    final maxY = sorted.isEmpty
        ? 10.0
        : (sorted.map((a) => a.amount).reduce((a, b) => a > b ? a : b) / 1e6 * 1.2);

    final barGroups = sorted.asMap().entries.map((e) {
      final amountM = e.value.amount / 1e6;
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: amountM,
            color: _barColor(e.value.status),
            width: 28,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
        ],
      );
    }).toList();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barGroups: barGroups,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Color(0xFFF0F4F8), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, _) => Text(
                '${v.toStringAsFixed(0)}M',
                style: const TextStyle(fontSize: 10, color: Color(0xFF8A9BAE)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= sorted.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '#${i + 1}',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF8A9BAE)),
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF12343B),
            getTooltipItem: (group, gi, rod, ri) {
              final app = sorted[group.x];
              return BarTooltipItem(
                AppFormatters.currency(app.amount),
                const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
              );
            },
          ),
        ),
      ),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  }
}

// ─── Helper Widgets ───────────────────────────────────────────────────────────

class _EmptyChart extends StatelessWidget {
  const _EmptyChart({this.message = 'Chưa có dữ liệu lịch thanh toán.'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.insert_chart_outlined_rounded,
              size: 48, color: Color(0xFFD7E3EE)),
          const SizedBox(height: 12),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF8A9BAE), fontSize: 13)),
        ],
      ),
    );
  }
}

class _NoLoanCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFD9B8)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: Color(0xFFE46A11)),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Bạn chưa có khoản vay nào. Biểu đồ dư nợ và tiến độ sẽ hiển thị sau khi hồ sơ được duyệt.',
              style: TextStyle(color: Color(0xFF9D470D), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _fmtM(double v) {
  if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(0)}M';
  if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(0)}K';
  return v.toStringAsFixed(0);
}
