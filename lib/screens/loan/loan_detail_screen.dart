import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/app_notice_dialog.dart';
import '../../core/widgets/status_chip.dart';
import '../../models/loan.dart';
import '../../models/repayment.dart';
import '../../providers/app_providers.dart';
import '../charts/loan_charts_screen.dart';

class LoanDetailScreen extends ConsumerStatefulWidget {
  const LoanDetailScreen({
    super.key,
    required this.loan,
  });

  final Loan loan;

  @override
  ConsumerState<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends ConsumerState<LoanDetailScreen> {
  final Set<String> _payingScheduleIds = <String>{};

  Future<void> _markPaid(Repayment repayment) async {
    setState(() => _payingScheduleIds.add(repayment.id));

    try {
      await ref.read(loanRepositoryProvider).markRepaymentPaidMock(
            loanId: widget.loan.id,
            scheduleId: repayment.id,
          );
      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Cập nhật thành công',
        message: 'Đã cập nhật thanh toán cho kỳ #${repayment.installmentNo}.',
      );
    } catch (error) {
      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Cập nhật thất bại',
        message: 'Không thể cập nhật thanh toán: $error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _payingScheduleIds.remove(repayment.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheduleAsync = ref.watch(repaymentScheduleProvider(widget.loan.id));

    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết khoản vay')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 16,
                runSpacing: 12,
                children: [
                  StatusChip(status: widget.loan.status),
                  Chip(label: Text('Mã hồ sơ: ${widget.loan.applicationId}')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _InfoRow(
              label: 'Gốc vay',
              value: AppFormatters.currency(widget.loan.principal)),
          _InfoRow(
            label: 'Lãi suất tháng',
            value:
                '${(widget.loan.interestRateMonthly * 100).toStringAsFixed(2)}%',
          ),
          _InfoRow(label: 'Kỳ hạn', value: '${widget.loan.termMonths} tháng'),
          _InfoRow(
            label: 'Trả hằng tháng',
            value: AppFormatters.currency(widget.loan.monthlyInstallment),
          ),
          _InfoRow(
              label: 'Ngày tạo',
              value: AppFormatters.dateTime(widget.loan.createdAt)),
          _InfoRow(
            label: 'Kỳ tiếp theo',
            value: AppFormatters.date(widget.loan.nextDueDate),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LoanChartsScreen(initialLoan: widget.loan),
              ),
            ),
            icon: const Icon(Icons.bar_chart_rounded, size: 18),
            label: const Text('Xem biểu đồ'),
          ),
          const SizedBox(height: 12),
          Text(
            'Lịch thanh toán',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          scheduleAsync.when(
            data: (schedules) {
              if (schedules.isEmpty) {
                return const Card(
                  child: ListTile(
                    title: Text('Chưa có lịch thanh toán'),
                  ),
                );
              }

              return Column(
                children: schedules.map((repayment) {
                  final loading = _payingScheduleIds.contains(repayment.id);
                  return Card(
                    child: ListTile(
                      title: Text('Kỳ #${repayment.installmentNo}'),
                      subtitle: Text(
                        'Hạn: ${AppFormatters.date(repayment.dueDate)}\nSố tiền: ${AppFormatters.currency(repayment.amount)}',
                      ),
                      isThreeLine: true,
                      trailing: repayment.status == 'paid'
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : FilledButton.tonal(
                              onPressed:
                                  loading ? null : () => _markPaid(repayment),
                              child: Text(loading
                                  ? 'Đang xử lý...'
                                  : 'Đánh dấu đã trả'),
                            ),
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text('Không tải được lịch thanh toán: $error'),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        subtitle: Text(value),
      ),
    );
  }
}
