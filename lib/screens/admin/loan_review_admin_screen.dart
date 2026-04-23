import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/app_notice_dialog.dart';
import '../../core/widgets/status_chip.dart';
import '../../models/loan_application.dart';
import '../../providers/app_providers.dart';
import '../../repositories/loan_repository.dart';

class LoanReviewAdminScreen extends ConsumerStatefulWidget {
  const LoanReviewAdminScreen({super.key});

  @override
  ConsumerState<LoanReviewAdminScreen> createState() =>
      _LoanReviewAdminScreenState();
}

class _LoanReviewAdminScreenState extends ConsumerState<LoanReviewAdminScreen> {
  String _statusFilter = 'reviewing';
  String? _busyApplicationId;
  String? _busyDecision;
  bool _loading = true;
  String? _loadError;
  List<LoanApplication> _applications = const [];
  Map<String, Map<String, dynamic>> _userSummaries = const {};

  @override
  void initState() {
    super.initState();
    _loadApplications();
  }

  List<LoanApplication> _applyFilter(List<LoanApplication> applications) {
    if (_statusFilter == 'all') {
      return applications;
    }
    return applications
        .where((application) => application.status.toLowerCase() == _statusFilter)
        .toList();
  }

  int _countByStatus(String status) {
    if (status == 'all') {
      return _applications.length;
    }
    return _applications
        .where((application) => application.status.toLowerCase() == status)
        .length;
  }

  Future<void> _loadApplications() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }

    try {
      final repository = ref.read(loanRepositoryProvider);
      final applications = await repository.fetchAllApplications();
      final userSummaries = await repository.fetchUserSummariesByIds(
        applications.map((application) => application.uid),
      );

      if (!mounted) return;
      setState(() {
        _applications = applications;
        _userSummaries = userSummaries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _reviewApplication(
    LoanApplication application, {
    required String decision,
  }) async {
    final reasonController = TextEditingController(
      text: _defaultDecisionReason(decision),
    );

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              scrollable: true,
              title: Text(_decisionDialogTitle(decision)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hồ sơ ${AppFormatters.currency(application.amount)} • ${application.termWeeks} tuần',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Lý do hiển thị cho khách hàng',
                      hintText: 'Ví dụ: Hồ sơ đã được duyệt thủ công.',
                    ),
                  ),
                ],
              ),
              actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              actions: [
                SizedBox(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: Text(_decisionActionLabel(decision)),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('Để sau'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed) {
      reasonController.dispose();
      return;
    }

    setState(() {
      _busyApplicationId = application.id;
      _busyDecision = decision;
    });
    try {
      final result =
          await ref.read(loanRepositoryProvider).reviewLoanApplicationManual(
                applicationId: application.id,
                decision: decision,
                decisionReason: reasonController.text.trim(),
              );
      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Đã cập nhật hồ sơ',
        message:
            'Trạng thái mới: ${_translateDecision(result['status']?.toString())}\n\n${result['message'] ?? ''}',
      );
      await _loadApplications();
    } catch (error) {
      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Chưa thể cập nhật hồ sơ',
        message: translateFunctionsError(error),
        isError: true,
      );
    } finally {
      reasonController.dispose();
      if (mounted) {
        setState(() {
          _busyApplicationId = null;
          _busyDecision = null;
        });
      }
    }
  }

  String _defaultDecisionReason(String decision) {
    switch (decision) {
      case 'approved':
        return 'Hồ sơ đã được duyệt thủ công.';
      case 'rejected':
        return 'Hồ sơ chưa được chấp thuận sau khi thẩm định thủ công.';
      case 'reviewing':
        return 'Hồ sơ đang được thẩm định thủ công.';
      default:
        return '';
    }
  }

  String _decisionDialogTitle(String decision) {
    switch (decision) {
      case 'approved':
        return 'Duyệt hồ sơ vay';
      case 'rejected':
        return 'Từ chối hồ sơ vay';
      case 'reviewing':
        return 'Đưa về chờ thẩm định';
      default:
        return 'Cập nhật hồ sơ';
    }
  }

  String _decisionActionLabel(String decision) {
    switch (decision) {
      case 'approved':
        return 'Duyệt hồ sơ';
      case 'rejected':
        return 'Xác nhận từ chối';
      case 'reviewing':
        return 'Đưa về chờ duyệt';
      default:
        return 'Cập nhật';
    }
  }

  String _translateDecision(String? status) {
    switch (status?.toLowerCase()) {
      case 'approved':
        return 'Đã duyệt';
      case 'rejected':
        return 'Từ chối';
      case 'reviewing':
        return 'Đang thẩm định';
      default:
        return status ?? '--';
    }
  }

  String _borrowerNameFor(String uid) {
    final user = _userSummaries[uid];
    final fullName = (user?['fullName']?.toString() ?? '').trim();
    final email = (user?['email']?.toString() ?? '').trim();
    if (fullName.isNotEmpty) return fullName;
    if (email.isNotEmpty) return email;
    return uid;
  }

  String? _borrowerSubtitleFor(String uid) {
    final user = _userSummaries[uid];
    final fullName = (user?['fullName']?.toString() ?? '').trim();
    final email = (user?['email']?.toString() ?? '').trim();
    if (fullName.isNotEmpty && email.isNotEmpty) {
      return email;
    }
    return null;
  }

  String? _borrowerPhoneFor(String uid) {
    final user = _userSummaries[uid];
    final phone = (user?['phone']?.toString() ?? '').trim();
    return phone.isEmpty ? null : phone;
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(currentUserIsAdminProvider);

    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Duyệt hồ sơ vay')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Khu vực này chỉ dành cho tài khoản admin.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final filteredApplications = _applyFilter(_applications);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Duyệt hồ sơ vay'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadApplications,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Khu vực quản trị',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Màn này tải danh sách một lần để giữ trạng thái ổn định hơn. Bạn có thể kéo xuống để làm mới khi cần.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterChip(
                  label: 'Chờ duyệt (${_countByStatus('reviewing')})',
                  selected: _statusFilter == 'reviewing',
                  onSelected: () => setState(() => _statusFilter = 'reviewing'),
                ),
                _FilterChip(
                  label: 'Đã duyệt (${_countByStatus('approved')})',
                  selected: _statusFilter == 'approved',
                  onSelected: () => setState(() => _statusFilter = 'approved'),
                ),
                _FilterChip(
                  label: 'Từ chối (${_countByStatus('rejected')})',
                  selected: _statusFilter == 'rejected',
                  onSelected: () => setState(() => _statusFilter = 'rejected'),
                ),
                _FilterChip(
                  label: 'Tất cả (${_countByStatus('all')})',
                  selected: _statusFilter == 'all',
                  onSelected: () => setState(() => _statusFilter = 'all'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_loadError != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Không thể tải danh sách hồ sơ: $_loadError'),
                ),
              )
            else if (filteredApplications.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Chưa có hồ sơ nào khớp với bộ lọc hiện tại.'),
                ),
              )
            else
              ...filteredApplications.map(
                (application) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AdminApplicationCard(
                    application: application,
                    borrowerName: _borrowerNameFor(application.uid),
                    borrowerSubtitle: _borrowerSubtitleFor(application.uid),
                    borrowerPhone: _borrowerPhoneFor(application.uid),
                    busy: _busyApplicationId == application.id,
                    busyDecision: _busyDecision,
                    onApprove: () => _reviewApplication(
                      application,
                      decision: 'approved',
                    ),
                    onReject: () => _reviewApplication(
                      application,
                      decision: 'rejected',
                    ),
                    onSendToReview: () => _reviewApplication(
                      application,
                      decision: 'reviewing',
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdminApplicationCard extends StatelessWidget {
  const _AdminApplicationCard({
    required this.application,
    required this.borrowerName,
    required this.borrowerSubtitle,
    required this.borrowerPhone,
    required this.busy,
    required this.busyDecision,
    required this.onApprove,
    required this.onReject,
    required this.onSendToReview,
  });

  final LoanApplication application;
  final String borrowerName;
  final String? borrowerSubtitle;
  final String? borrowerPhone;
  final bool busy;
  final String? busyDecision;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onSendToReview;

  @override
  Widget build(BuildContext context) {
    final canApprove = application.approvedLoanId == null;
    final canMoveToReview = application.approvedLoanId == null;
    final canReject = application.approvedLoanId == null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppFormatters.currency(application.amount),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${application.termWeeks} tuần • ${AppFormatters.dateTime(application.createdAt)}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF66778B),
                            ),
                      ),
                    ],
                  ),
                ),
                StatusChip(status: application.status),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('Người vay: $borrowerName')),
                if (borrowerSubtitle != null) Chip(label: Text(borrowerSubtitle!)),
                if (borrowerPhone != null) Chip(label: Text('SĐT: $borrowerPhone')),
                if (application.riskLevel.isNotEmpty)
                  Chip(label: Text('Rủi ro: ${_riskLabel(application.riskLevel)}')),
                if (application.approvedLoanId != null)
                  Chip(label: Text('Loan: ${application.approvedLoanId}')),
              ],
            ),
            if (application.purpose.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Mục đích vay: ${application.purpose}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (application.decisionReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                application.decisionReason,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF486368),
                    ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: busy || !canApprove ? null : onApprove,
                  icon: busy && busyDecision == 'approved'
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: const Text('Duyệt'),
                ),
                OutlinedButton.icon(
                  onPressed: busy || !canReject ? null : onReject,
                  icon: busy && busyDecision == 'rejected'
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.close_rounded),
                  label: const Text('Từ chối'),
                ),
                OutlinedButton.icon(
                  onPressed: busy || !canMoveToReview ? null : onSendToReview,
                  icon: busy && busyDecision == 'reviewing'
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.hourglass_top_rounded),
                  label: const Text('Chờ duyệt'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

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
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}
