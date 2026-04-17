import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/status_chip.dart';
import '../../models/loan_application.dart';

class ApplicationDetailScreen extends StatelessWidget {
  const ApplicationDetailScreen({
    super.key,
    required this.application,
  });

  final LoanApplication application;

  String _riskLabel(String value) {
    switch (value.toLowerCase()) {
      case 'low':
        return 'Thấp';
      case 'medium':
        return 'Trung bình';
      case 'high':
        return 'Cao';
      default:
        return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chi tiết hồ sơ vay')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                runSpacing: 12,
                spacing: 16,
                children: [
                  StatusChip(status: application.status),
                  if (application.riskLevel.isNotEmpty)
                    Chip(
                        label: Text(
                            'Mức rủi ro: ${_riskLabel(application.riskLevel)}')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _InfoRow(
              label: 'Số tiền vay',
              value: AppFormatters.currency(application.amount)),
          _InfoRow(label: 'Kỳ hạn', value: '${application.termMonths} tháng'),
          _InfoRow(
            label: 'Trả hằng tháng',
            value: AppFormatters.currency(application.monthlyInstallment),
          ),
          _InfoRow(
            label: 'Thu nhập khai báo',
            value: AppFormatters.currency(application.monthlyIncome),
          ),
          _InfoRow(label: 'Mục đích', value: application.purpose),
          _InfoRow(
              label: 'Tạo lúc',
              value: AppFormatters.dateTime(application.createdAt)),
          _InfoRow(
              label: 'Cập nhật lúc',
              value: AppFormatters.dateTime(application.updatedAt)),
          if (application.decisionReason.isNotEmpty)
            _InfoRow(label: 'Ghi chú', value: application.decisionReason),
          if (application.approvedLoanId != null)
            _InfoRow(
                label: 'Mã khoản vay đã duyệt',
                value: application.approvedLoanId!),
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
