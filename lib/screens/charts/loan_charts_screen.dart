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
    final isAdmin = ref.watch(currentUserIsAdminProvider);
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
          if (isAdmin) ...[
            _AdminKpiGrid(
              applications: applications,
              loans: loans,
            ),
            const SizedBox(height: 16),
            _ChartCard(
              title: 'Trạng thái hồ sơ vay',
              subtitle: 'Phân loại hồ sơ theo kết quả xử lý hiện tại',
              icon: Icons.assignment_turned_in_outlined,
              child: applications.isEmpty
                  ? const _EmptyChart(message: 'Chưa có hồ sơ vay nào.')
                  : _ApplicationStatusChart(applications: applications),
            ),
            const SizedBox(height: 16),
            _ChartCard(
              title: 'Danh mục khoản vay',
              subtitle: 'Tỷ trọng khoản vay đang hoạt động và đã hoàn tất',
              icon: Icons.pie_chart_outline_rounded,
              child: loans.isEmpty
                  ? const _EmptyChart(message: 'Chưa có khoản vay nào.')
                  : _LoanPortfolioChart(loans: loans),
            ),
            const SizedBox(height: 16),
          ],
          if (loan != null) ...[
            _SummaryRow(loan: loan, schedules: schedules),
            const SizedBox(height: 16),
            _ChartCard(
              title: 'Tiến độ trả nợ',
              subtitle: '${loan.termWeeks} kỳ tuần · ${AppFormatters.currency(loan.principal)}',
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
              title: isAdmin ? 'Diễn biến hồ sơ theo thời gian' : 'Lịch sử hồ sơ vay',
              subtitle: isAdmin
                  ? 'Giá trị hồ sơ theo thứ tự tạo gần nhất'
                  : '${applications.length} hồ sơ đã nộp',
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

class _AdminKpiGrid extends StatelessWidget {
  const _AdminKpiGrid({
    required this.applications,
    required this.loans,
  });

  final List<LoanApplication> applications;
  final List<Loan> loans;

  @override
  Widget build(BuildContext context) {
    final reviewingCount = applications
        .where((application) => _applicationStatusKey(application.status) == 'reviewing')
        .length;
    final approvedCount = applications
        .where((application) => _applicationStatusKey(application.status) == 'approved')
        .length;
    final activeLoanCount = loans
        .where((loan) => _loanStatusKey(loan.status) == 'active')
        .length;
    final totalOutstanding = loans
        .where((loan) => _loanStatusKey(loan.status) == 'active')
        .fold<double>(0, (sum, loan) => sum + loan.principal);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _KpiCard(
          label: 'Tổng hồ sơ',
          value: '${applications.length}',
          accent: const Color(0xFFE46A11),
        ),
        _KpiCard(
          label: 'Đang duyệt',
          value: '$reviewingCount',
          accent: const Color(0xFF1565C0),
        ),
        _KpiCard(
          label: 'Đã duyệt',
          value: '$approvedCount',
          accent: const Color(0xFF2E7D32),
        ),
        _KpiCard(
          label: 'Dư nợ active',
          value: AppFormatters.currency(totalOutstanding),
          accent: const Color(0xFF7B3FE4),
          helper: '$activeLoanCount khoản vay',
          wide: true,
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.accent,
    this.helper,
    this.wide = false,
  });

  final String label;
  final String value;
  final Color accent;
  final String? helper;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final width = wide ? 340.0 : 164.0;
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (helper != null) ...[
              const SizedBox(height: 4),
              Text(
                helper!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF7C8A9A),
                    ),
              ),
            ],
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
        maxX: loan.termWeeks.toDouble(),
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
              interval: (loan.termWeeks / 4).ceilToDouble(),
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

class _ApplicationStatusChart extends StatelessWidget {
  const _ApplicationStatusChart({required this.applications});

  final List<LoanApplication> applications;

  @override
  Widget build(BuildContext context) {
    final buckets = <_StatusBucket>[
      _StatusBucket(
        key: 'reviewing',
        label: 'Đang duyệt',
        color: const Color(0xFF1565C0),
        count: applications
            .where((application) => _applicationStatusKey(application.status) == 'reviewing')
            .length,
      ),
      _StatusBucket(
        key: 'approved',
        label: 'Đã duyệt',
        color: const Color(0xFF2E7D32),
        count: applications
            .where((application) => _applicationStatusKey(application.status) == 'approved')
            .length,
      ),
      _StatusBucket(
        key: 'rejected',
        label: 'Từ chối',
        color: const Color(0xFFD32F2F),
        count: applications
            .where((application) => _applicationStatusKey(application.status) == 'rejected')
            .length,
      ),
      _StatusBucket(
        key: 'other',
        label: 'Khác',
        color: const Color(0xFF8A9BAE),
        count: applications
            .where((application) => _applicationStatusKey(application.status) == 'other')
            .length,
      ),
    ];

    final maxCount = buckets.fold<int>(1, (max, bucket) => bucket.count > max ? bucket.count : max);

    return Row(
      children: [
        Expanded(
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: (maxCount + 1).toDouble(),
              barGroups: buckets.asMap().entries.map((entry) {
                final index = entry.key;
                final bucket = entry.value;
                return BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: bucket.count.toDouble(),
                      color: bucket.color,
                      width: 28,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(8)),
                    ),
                  ],
                );
              }).toList(),
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
                    reservedSize: 28,
                    interval: 1,
                    getTitlesWidget: (value, _) => Text(
                      value.toInt().toString(),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF8A9BAE),
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, _) {
                      final index = value.toInt();
                      if (index < 0 || index >= buckets.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          buckets[index].shortLabel,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF8A9BAE),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF12343B),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final bucket = buckets[group.x];
                    return BarTooltipItem(
                      '${bucket.label}: ${bucket.count} hồ sơ',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
            ),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 108,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: buckets
                .where((bucket) => bucket.count > 0)
                .map((bucket) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _Legend(
                        color: bucket.color,
                        label: '${bucket.label} (${bucket.count})',
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _LoanPortfolioChart extends StatelessWidget {
  const _LoanPortfolioChart({required this.loans});

  final List<Loan> loans;

  @override
  Widget build(BuildContext context) {
    final active = loans.where((loan) => _loanStatusKey(loan.status) == 'active').length;
    final closed = loans.where((loan) => _loanStatusKey(loan.status) == 'closed').length;
    final other = loans.length - active - closed;

    final sections = <PieChartSectionData>[
      if (active > 0)
        PieChartSectionData(
          value: active.toDouble(),
          color: const Color(0xFFE46A11),
          radius: 52,
          title: '$active',
          titleStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      if (closed > 0)
        PieChartSectionData(
          value: closed.toDouble(),
          color: const Color(0xFF2E7D32),
          radius: 52,
          title: '$closed',
          titleStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      if (other > 0)
        PieChartSectionData(
          value: other.toDouble(),
          color: const Color(0xFF8A9BAE),
          radius: 52,
          title: '$other',
          titleStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
    ];

    final total = loans.length;
    final activePct = total > 0 ? (active / total * 100).toStringAsFixed(0) : '0';

    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sections: sections.isEmpty
                  ? [
                      PieChartSectionData(
                        value: 1,
                        color: const Color(0xFFE8F0F5),
                        radius: 52,
                        title: '',
                      ),
                    ]
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
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$activePct%',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: const Color(0xFFE46A11),
                  ),
            ),
            const Text(
              'đang active',
              style: TextStyle(color: Color(0xFF8A9BAE), fontSize: 12),
            ),
            const SizedBox(height: 14),
            _Legend(color: const Color(0xFFE46A11), label: 'Active ($active)'),
            const SizedBox(height: 6),
            _Legend(color: const Color(0xFF2E7D32), label: 'Đã tất toán ($closed)'),
            if (other > 0) ...[
              const SizedBox(height: 6),
              _Legend(color: const Color(0xFF8A9BAE), label: 'Khác ($other)'),
            ],
          ],
        ),
      ],
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

class _StatusBucket {
  const _StatusBucket({
    required this.key,
    required this.label,
    required this.color,
    required this.count,
  });

  final String key;
  final String label;
  final Color color;
  final int count;

  String get shortLabel => label;
}

String _applicationStatusKey(String status) {
  switch (status) {
    case 'reviewing':
      return 'reviewing';
    case 'approved':
      return 'approved';
    case 'rejected':
      return 'rejected';
    default:
      return 'other';
  }
}

String _loanStatusKey(String status) {
  switch (status) {
    case 'active':
      return 'active';
    case 'closed':
      return 'closed';
    case 'defaulted':
      return 'defaulted';
    default:
      return 'other';
  }
}
