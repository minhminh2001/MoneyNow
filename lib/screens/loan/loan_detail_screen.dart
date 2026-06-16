import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/app_notice_dialog.dart';
import '../../core/widgets/status_chip.dart';
import '../../models/loan.dart';
import '../../models/repayment.dart';
import '../../providers/app_providers.dart';
import '../../repositories/loan_repository.dart';
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
  final Set<String> _optimisticPaidScheduleIds = <String>{};

  Future<void> _markPaid(Repayment repayment) async {
    setState(() => _payingScheduleIds.add(repayment.id));

    try {
      await ref.read(loanRepositoryProvider).markRepaymentPaidMock(
            loanId: widget.loan.id,
            scheduleId: repayment.id,
          );
      if (mounted) {
        setState(() => _optimisticPaidScheduleIds.add(repayment.id));
      }
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
        message: translateFunctionsError(error),
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
            label: 'Kỳ hạn',
            value: '${widget.loan.termWeeks} tuần (${widget.loan.termDays} ngày)',
          ),
          _InfoRow(
            label: 'Trả hằng tuần',
            value: AppFormatters.currency(widget.loan.weeklyInstallment),
          ),
          _InfoRow(
            label: 'Phí thẩm định hồ sơ (4%)',
            value: AppFormatters.currency(widget.loan.appraisalFee),
          ),
          _InfoRow(
            label: 'Phí dịch vụ (4%)',
            value: AppFormatters.currency(widget.loan.serviceFee),
          ),
          _InfoRow(
            label: 'Số tiền thực nhận',
            value: AppFormatters.currency(widget.loan.netDisbursement),
          ),
          _InfoRow(
            label: 'Phí phạt quá hạn',
            value: AppFormatters.currency(widget.loan.overduePenaltyFee),
          ),
          _InfoRow(
              label: 'Ngày tạo',
              value: AppFormatters.dateTime(widget.loan.createdAt)),
          _InfoRow(
            label: 'Kỳ tiếp theo',
            value: AppFormatters.date(widget.loan.nextDueDate),
          ),
          if (widget.loan.borrowerPayoutAccountHolder.isNotEmpty ||
              widget.loan.borrowerPayoutBankName.isNotEmpty ||
              widget.loan.borrowerPayoutAccountNumber.isNotEmpty) ...[
            const SizedBox(height: 12),
            _PaymentInfoCard(
              title: 'Tài khoản nhận giải ngân của bạn',
              rows: [
                if (widget.loan.borrowerPayoutAccountHolder.isNotEmpty)
                  _PaymentRowData(
                    'Chủ tài khoản',
                    widget.loan.borrowerPayoutAccountHolder,
                  ),
                if (widget.loan.borrowerPayoutBankName.isNotEmpty)
                  _PaymentRowData(
                    'Ngân hàng',
                    widget.loan.borrowerPayoutBankName,
                  ),
                if (widget.loan.borrowerPayoutAccountNumber.isNotEmpty)
                  _PaymentRowData(
                    'Số tài khoản',
                    widget.loan.borrowerPayoutAccountNumber,
                  ),
              ],
            ),
          ],
          if (widget.loan.repaymentAccountHolder.isNotEmpty ||
              widget.loan.repaymentBankName.isNotEmpty ||
              widget.loan.repaymentAccountNumber.isNotEmpty ||
              widget.loan.repaymentTransferNote.isNotEmpty) ...[
            const SizedBox(height: 12),
            _PaymentInfoCard(
              title: 'Thông tin chuyển khoản trả nợ',
              subtitle:
                  'Dùng thông tin dưới đây khi bạn chuyển khoản thanh toán kỳ vay.',
              rows: [
                if (widget.loan.repaymentAccountHolder.isNotEmpty)
                  _PaymentRowData(
                    'Chủ tài khoản',
                    widget.loan.repaymentAccountHolder,
                  ),
                if (widget.loan.repaymentBankName.isNotEmpty)
                  _PaymentRowData(
                    'Ngân hàng',
                    widget.loan.repaymentBankName,
                  ),
                if (widget.loan.repaymentAccountNumber.isNotEmpty)
                  _PaymentRowData(
                    'Số tài khoản',
                    widget.loan.repaymentAccountNumber,
                  ),
                if (widget.loan.repaymentTransferNote.isNotEmpty)
                  _PaymentRowData(
                    'Nội dung chuyển khoản',
                    widget.loan.repaymentTransferNote,
                  ),
              ],
            ),
          ],
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
              final scheduleIds =
                  schedules.map((repayment) => repayment.id).toSet();
              final syncedPaidIds = schedules
                  .where((repayment) => repayment.status == 'paid')
                  .map((repayment) => repayment.id)
                  .toSet();
              final syncedOptimisticIds =
                  _optimisticPaidScheduleIds.intersection(syncedPaidIds);
              final missingOptimisticIds =
                  _optimisticPaidScheduleIds.difference(scheduleIds);
              final resolvedOptimisticIds = <String>{
                ...syncedOptimisticIds,
                ...missingOptimisticIds,
              };
              if (resolvedOptimisticIds.isNotEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  setState(() {
                    _optimisticPaidScheduleIds
                        .removeAll(resolvedOptimisticIds);
                  });
                });
              }

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
                  final isPaid = repayment.status == 'paid' ||
                      _optimisticPaidScheduleIds.contains(repayment.id);
                  return Card(
                    child: ListTile(
                      title: Text('Kỳ #${repayment.installmentNo}'),
                      subtitle: Text(
                        'Hạn: ${AppFormatters.date(repayment.dueDate)}\nKỳ trả: ${AppFormatters.currency(repayment.amount)}\nPhí phạt quá hạn: ${AppFormatters.currency(repayment.overduePenaltyFee)}\nTổng cần trả: ${AppFormatters.currency(repayment.totalDue)}',
                      ),
                      isThreeLine: true,
                      trailing: isPaid
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

class _PaymentInfoCard extends StatelessWidget {
  const _PaymentInfoCard({
    required this.title,
    required this.rows,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<_PaymentRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF5B6B7E),
                    ),
              ),
            ],
            const SizedBox(height: 12),
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 150,
                      child: Text(
                        row.label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF6B7A90),
                            ),
                      ),
                    ),
                    Expanded(
                      child: SelectableText(
                        row.value,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: const Color(0xFF12343B),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentRowData {
  const _PaymentRowData(this.label, this.value);

  final String label;
  final String value;
}
