import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_notice_dialog.dart';
import '../../models/admin_payment_settings.dart';
import '../../providers/app_providers.dart';
import '../../repositories/admin_repository.dart';

class AdminPaymentSettingsScreen extends ConsumerStatefulWidget {
  const AdminPaymentSettingsScreen({super.key});

  @override
  ConsumerState<AdminPaymentSettingsScreen> createState() =>
      _AdminPaymentSettingsScreenState();
}

class _AdminPaymentSettingsScreenState
    extends ConsumerState<AdminPaymentSettingsScreen> {
  final _repaymentAccountHolderController = TextEditingController();
  final _repaymentBankNameController = TextEditingController();
  final _repaymentAccountNumberController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _didHydrate = false;
  String? _error;
  AdminPaymentSettings _settings = AdminPaymentSettings.empty();
  AdminDashboardData? _dashboardData;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _repaymentAccountHolderController.dispose();
    _repaymentBankNameController.dispose();
    _repaymentAccountNumberController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final repository = ref.read(adminRepositoryProvider);
      final results = await Future.wait([
        repository.fetchPaymentSettings(),
        repository.fetchDashboard(),
      ]);
      final settings = results[0] as AdminPaymentSettings;
      final dashboard = results[1] as AdminDashboardData;
      if (!mounted) return;
      _settings = settings;
      _dashboardData = dashboard;
      _hydrate(settings);
      setState(() {
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  void _hydrate(AdminPaymentSettings settings) {
    if (_didHydrate) return;
    _repaymentAccountHolderController.text = settings.repaymentAccountHolder;
    _repaymentBankNameController.text = settings.repaymentBankName;
    _repaymentAccountNumberController.text = settings.repaymentAccountNumber;
    _didHydrate = true;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final saved = await ref.read(adminRepositoryProvider).savePaymentSettings(
            repaymentAccountHolder:
                _repaymentAccountHolderController.text.trim(),
            repaymentBankName: _repaymentBankNameController.text.trim(),
            repaymentAccountNumber:
                _repaymentAccountNumberController.text.trim(),
          );
      if (!mounted) return;
      _settings = saved;
      await showAppNoticeDialog(
        context,
        title: 'Đã lưu cấu hình',
        message:
            'Thông tin nhận trả nợ đã được cập nhật cho toàn bộ web admin.',
      );
      setState(() {
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 40, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(
                'Không tải được cấu hình thanh toán.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF6B7A90),
                    ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Tải lại'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBF7),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFF0E2D6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cấu hình nhận trả nợ',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: const Color(0xFF12343B),
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Thông tin ở đây sẽ được dùng tập trung khi tạo khoản vay mới, để khách hàng biết chuyển khoản trả nợ về đâu.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF6B7A90),
                    ),
              ),
              if (_settings.updatedAt != null || _settings.updatedBy.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Cập nhật gần nhất: ${_formatUpdatedMeta(_settings)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6B7A90),
                        ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 380,
              child: _buildField(
                controller: _repaymentAccountHolderController,
                label: 'Tên chủ tài khoản',
                hintText: 'Ví dụ: CONG TY ABC',
                icon: Icons.badge_outlined,
              ),
            ),
            SizedBox(
              width: 320,
              child: _buildField(
                controller: _repaymentBankNameController,
                label: 'Ngân hàng',
                hintText: 'Ví dụ: MB Bank',
                icon: Icons.account_balance_outlined,
              ),
            ),
            SizedBox(
              width: 320,
              child: _buildField(
                controller: _repaymentAccountNumberController,
                label: 'Số tài khoản',
                hintText: 'Nhập số tài khoản nhận trả nợ',
                icon: Icons.credit_card_outlined,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5ECF4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Xem trước trên khoản vay',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF12343B),
                    ),
              ),
              const SizedBox(height: 12),
              _PreviewRow(
                label: 'Chủ tài khoản',
                value: _repaymentAccountHolderController.text.trim(),
              ),
              _PreviewRow(
                label: 'Ngân hàng',
                value: _repaymentBankNameController.text.trim(),
              ),
              _PreviewRow(
                label: 'Số tài khoản',
                value: _repaymentAccountNumberController.text.trim(),
              ),
              const _PreviewRow(
                label: 'Nội dung chuyển khoản',
                value: 'TRA NO {loanId}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _BorrowerPayoutPanel(
          records: _buildBorrowerRecords(),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Đang lưu...' : 'Lưu cấu hình'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _saving
                  ? null
                  : () {
                      _didHydrate = false;
                      _hydrate(_settings);
                      setState(() {});
                    },
              icon: const Icon(Icons.undo_outlined),
              label: const Text('Khôi phục'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  String _formatUpdatedMeta(AdminPaymentSettings settings) {
    final date = settings.updatedAt;
    final user = settings.updatedBy;
    final dateLabel = date == null
        ? ''
        : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    if (dateLabel.isNotEmpty && user.isNotEmpty) {
      return '$dateLabel bởi $user';
    }
    return dateLabel.isNotEmpty ? dateLabel : user;
  }

  List<_BorrowerPayoutRecord> _buildBorrowerRecords() {
    final dashboard = _dashboardData;
    if (dashboard == null) return const [];

    final records = <_BorrowerPayoutRecord>[];
    final userSummaries = dashboard.userSummaries;
    final seenKeys = <String>{};

    for (final loan in dashboard.loans) {
      if (loan.borrowerPayoutAccountHolder.isEmpty &&
          loan.borrowerPayoutBankName.isEmpty &&
          loan.borrowerPayoutAccountNumber.isEmpty) {
        continue;
      }
      final key =
          'loan_${loan.uid}_${loan.borrowerPayoutAccountNumber}_${loan.borrowerPayoutBankName}';
      if (!seenKeys.add(key)) continue;
      final user = userSummaries[loan.uid] ?? const {};
      records.add(
        _BorrowerPayoutRecord(
          source: 'Khoản vay',
          sourceId: loan.id,
          userName: (user['fullName']?.toString().trim().isNotEmpty ?? false)
              ? user['fullName'].toString().trim()
              : 'Khách hàng ${loan.uid}',
          phone: user['phone']?.toString().trim() ?? '',
          accountHolder: loan.borrowerPayoutAccountHolder,
          bankName: loan.borrowerPayoutBankName,
          accountNumber: loan.borrowerPayoutAccountNumber,
          amountLabel: _formatCurrency(loan.netDisbursement),
          updatedAt: loan.createdAt ?? loan.approvedAt,
        ),
      );
    }

    for (final application in dashboard.applications) {
      if (application.borrowerPayoutAccountHolder.isEmpty &&
          application.borrowerPayoutBankName.isEmpty &&
          application.borrowerPayoutAccountNumber.isEmpty) {
        continue;
      }
      final key =
          'application_${application.uid}_${application.borrowerPayoutAccountNumber}_${application.borrowerPayoutBankName}';
      if (!seenKeys.add(key)) continue;
      final user = userSummaries[application.uid] ?? const {};
      records.add(
        _BorrowerPayoutRecord(
          source: 'Hồ sơ vay',
          sourceId: application.id,
          userName: (user['fullName']?.toString().trim().isNotEmpty ?? false)
              ? user['fullName'].toString().trim()
              : 'Khách hàng ${application.uid}',
          phone: user['phone']?.toString().trim() ?? '',
          accountHolder: application.borrowerPayoutAccountHolder,
          bankName: application.borrowerPayoutBankName,
          accountNumber: application.borrowerPayoutAccountNumber,
          amountLabel: _formatCurrency(application.netDisbursement),
          updatedAt: application.updatedAt ?? application.createdAt,
        ),
      );
    }

    records.sort((a, b) {
      final aTime = a.updatedAt?.millisecondsSinceEpoch ?? 0;
      final bTime = b.updatedAt?.millisecondsSinceEpoch ?? 0;
      return bTime.compareTo(aTime);
    });
    return records;
  }

  String _formatCurrency(double value) {
    final rounded = value.round();
    final digits = rounded.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      final reverseIndex = digits.length - i;
      buffer.write(digits[i]);
      if (reverseIndex > 1 && reverseIndex % 3 == 1) {
        buffer.write('.');
      }
    }
    final prefix = rounded < 0 ? '-' : '';
    return '$prefix${buffer.toString()} đ';
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final resolvedValue = value.trim().isEmpty ? 'Chưa cấu hình' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6B7A90),
                  ),
            ),
          ),
          Expanded(
            child: Text(
              resolvedValue,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: const Color(0xFF12343B),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BorrowerPayoutRecord {
  const _BorrowerPayoutRecord({
    required this.source,
    required this.sourceId,
    required this.userName,
    required this.phone,
    required this.accountHolder,
    required this.bankName,
    required this.accountNumber,
    required this.amountLabel,
    required this.updatedAt,
  });

  final String source;
  final String sourceId;
  final String userName;
  final String phone;
  final String accountHolder;
  final String bankName;
  final String accountNumber;
  final String amountLabel;
  final DateTime? updatedAt;
}

class _BorrowerPayoutPanel extends StatelessWidget {
  const _BorrowerPayoutPanel({
    required this.records,
  });

  final List<_BorrowerPayoutRecord> records;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5ECF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tài khoản nhận giải ngân của khách vay',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF12343B),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Danh sách này giúp admin đối chiếu nhanh thông tin chuyển khoản nhận tiền của khách hàng từ hồ sơ vay và khoản vay đã tạo.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF6B7A90),
                ),
          ),
          const SizedBox(height: 16),
          if (records.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Chưa có dữ liệu tài khoản nhận giải ngân từ khách vay.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF6B7A90),
                    ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 18,
                headingRowColor: WidgetStatePropertyAll(
                  const Color(0xFFF7FAFD),
                ),
                columns: const [
                  DataColumn(label: Text('Khách hàng')),
                  DataColumn(label: Text('Liên hệ')),
                  DataColumn(label: Text('Tài khoản')),
                  DataColumn(label: Text('Ngân hàng')),
                  DataColumn(label: Text('Số tài khoản')),
                  DataColumn(label: Text('Thực nhận')),
                  DataColumn(label: Text('Nguồn')),
                ],
                rows: records
                    .map(
                      (record) => DataRow(
                        cells: [
                          DataCell(Text(record.userName)),
                          DataCell(
                            Text(record.phone.isEmpty ? '-' : record.phone),
                          ),
                          DataCell(Text(record.accountHolder)),
                          DataCell(Text(record.bankName)),
                          DataCell(Text(record.accountNumber)),
                          DataCell(Text(record.amountLabel)),
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(record.source),
                                Text(
                                  record.sourceId,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF6B7A90),
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}
