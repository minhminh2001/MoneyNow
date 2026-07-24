import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/widgets/app_notice_dialog.dart';
import '../../providers/app_providers.dart';
import '../../repositories/admin_repository.dart';

class AccountDeletionRequestsScreen extends ConsumerStatefulWidget {
  const AccountDeletionRequestsScreen({super.key});

  @override
  ConsumerState<AccountDeletionRequestsScreen> createState() =>
      _AccountDeletionRequestsScreenState();
}

class _AccountDeletionRequestsScreenState
    extends ConsumerState<AccountDeletionRequestsScreen> {
  final _dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'vi_VN');
  bool _loading = true;
  bool _acting = false;
  String? _error;
  List<AccountDeletionRequest> _requests = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final requests =
          await ref.read(adminRepositoryProvider).fetchAccountDeletionRequests();
      if (!mounted) return;
      setState(() => _requests = requests);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _reject(AccountDeletionRequest request) async {
    setState(() => _acting = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .rejectAccountDeletionRequest(uid: request.uid);
      await _load();
      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Đã từ chối yêu cầu',
        message: 'Yêu cầu xóa tài khoản đã được chuyển sang trạng thái từ chối.',
      );
    } catch (error) {
      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Không thể từ chối',
        message: '$error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _acting = false);
      }
    }
  }

  Future<void> _approve(AccountDeletionRequest request) async {
    final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('Xác nhận xóa tài khoản'),
              content: Text(
                'Tài khoản ${request.displayName} sẽ bị xóa khỏi Auth, hồ sơ, tài liệu, hồ sơ vay và khoản vay liên quan.\n\n'
                'Khoản vay đang hoạt động: ${request.activeLoanCount}\n'
                'Chỉ xác nhận khi đã đối chiếu nghiệp vụ xong.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Hủy'),
                ),
                FilledButton.tonal(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Xác nhận xóa'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirmed) return;

    setState(() => _acting = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .approveAccountDeletionRequest(uid: request.uid);
      await _load();
      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Đã xóa tài khoản',
        message: 'Tài khoản và dữ liệu liên quan đã được xóa khỏi hệ thống.',
      );
    } catch (error) {
      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Không thể xóa tài khoản',
        message: '$error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _acting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return _AdminMessage(
        title: 'Không tải được yêu cầu xóa tài khoản',
        message: _error!,
        actionLabel: 'Thử lại',
        onAction: _load,
      );
    }

    if (_requests.isEmpty) {
      return _AdminMessage(
        title: 'Chưa có yêu cầu xóa tài khoản',
        message:
            'Khi người dùng gửi yêu cầu xóa tài khoản từ app, danh sách sẽ xuất hiện ở đây để admin kiểm tra và xác nhận.',
        actionLabel: 'Làm mới',
        onAction: _load,
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _requests.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final request = _requests[index];
          final pending = request.status == 'pending';
          final requestedAt = request.requestedAt == null
              ? '-'
              : _dateFormat.format(request.requestedAt!);
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        request.displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Chip(label: Text(request.statusLabel)),
                      if (request.activeLoanCount > 0)
                        const Chip(
                          label: Text('Có khoản vay đang hoạt động'),
                          backgroundColor: Color(0xFFFFE4CF),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('UID: ${request.uid}'),
                  Text('SĐT: ${request.phone.isEmpty ? '-' : request.phone}'),
                  Text('Email: ${request.email.isEmpty ? '-' : request.email}'),
                  Text('Thời gian gửi: $requestedAt'),
                  const SizedBox(height: 8),
                  Text(
                    'Hồ sơ vay: ${request.applicationCount} | Khoản vay: ${request.loanCount} | Đang hoạt động/quá hạn: ${request.activeLoanCount}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: request.activeLoanCount > 0
                              ? const Color(0xFF9B2F1F)
                              : null,
                          fontWeight: request.activeLoanCount > 0
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                  ),
                  if (pending) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _acting ? null : () => _reject(request),
                          icon: const Icon(Icons.close),
                          label: const Text('Từ chối'),
                        ),
                        FilledButton.icon(
                          onPressed: _acting ? null : () => _approve(request),
                          icon: const Icon(Icons.delete_outline),
                          label: Text(
                            _acting ? 'Đang xử lý...' : 'Xác nhận xóa',
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

extension on AccountDeletionRequest {
  String get displayName {
    if (fullName.trim().isNotEmpty) return fullName.trim();
    if (phone.trim().isNotEmpty) return phone.trim();
    if (email.trim().isNotEmpty) return email.trim();
    return uid;
  }

  String get statusLabel {
    switch (status.trim().toLowerCase()) {
      case 'pending':
        return 'Chờ admin xử lý';
      case 'processing':
        return 'Đang xử lý';
      case 'rejected':
        return 'Đã từ chối';
      default:
        return status.isEmpty ? 'Không rõ' : status;
    }
  }
}

class _AdminMessage extends StatelessWidget {
  const _AdminMessage({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
