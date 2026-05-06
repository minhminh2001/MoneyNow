import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants/loan_policy.dart';
import '../../core/services/contact_sync_service.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/utils/loan_calculator.dart';
import '../../core/widgets/app_notice_dialog.dart';
import '../../models/app_user.dart';
import '../../models/loan_draft.dart';
import '../../models/phone_contact.dart';
import '../../providers/app_providers.dart';
import '../../repositories/loan_repository.dart';
import '../documents/document_upload_screen.dart';
import '../profile/profile_screen.dart';

class CreateApplicationScreen extends ConsumerStatefulWidget {
  const CreateApplicationScreen({
    super.key,
    this.initialStep,
  });

  final int? initialStep;

  @override
  ConsumerState<CreateApplicationScreen> createState() =>
      _CreateApplicationScreenState();
}

class _CreateApplicationScreenState
    extends ConsumerState<CreateApplicationScreen> {
  static final _incomeNumberFormat = NumberFormat('#,###', 'vi_VN');
  final _contactSyncService = ContactSyncService();
  final _amountController = TextEditingController();
  final _termController = TextEditingController(text: '6');
  final _purposeController = TextEditingController();
  final _phoneController = TextEditingController();
  final _incomeController = TextEditingController();
  final _employerController = TextEditingController();

  bool _loading = false;
  bool _preparingContacts = false;
  bool _backgroundSyncingContacts = false;
  bool _attemptedAutoContactSync = false;
  bool _hydrated = false;
  int _step = 1;
  String? _contactsSyncStatusText;
  int _contactsSyncProcessed = 0;
  int _contactsSyncTotal = 0;
  DateTime? _contactsSyncStartedAt;

  @override
  void dispose() {
    _amountController.dispose();
    _termController.dispose();
    _purposeController.dispose();
    _phoneController.dispose();
    _incomeController.dispose();
    _employerController.dispose();
    super.dispose();
  }

  void _hydrate({
    required AppUser? profile,
    required LoanDraft draft,
  }) {
    if (_hydrated) return;
    _phoneController.text = _formatPhoneForDisplay(
        draft.phone.isNotEmpty ? draft.phone : profile?.phone ?? '');
    _incomeController.text = draft.monthlyIncome > 0
        ? _incomeNumberFormat.format(draft.monthlyIncome.round())
        : (profile?.monthlyIncome ?? 0) > 0
            ? _incomeNumberFormat.format(profile!.monthlyIncome.round())
            : '';
    _employerController.text =
        draft.employer.isNotEmpty ? draft.employer : profile?.employer ?? '';
    _amountController.text = draft.requestedAmount > 0
        ? _incomeNumberFormat.format(draft.requestedAmount.round())
        : '';
    _termController.text = draft.termWeeks > 0 ? draft.termWeeks.toString() : '6';
    _purposeController.text = draft.purpose;
    _step = (widget.initialStep ?? draft.currentStep).clamp(1, 4);
    _hydrated = true;
  }

  double get _requestedAmount =>
      double.tryParse(_amountController.text.trim().replaceAll('.', '')) ?? 0;

  int get _termWeeks {
    final weeks = int.tryParse(_termController.text.trim()) ?? 6;
    return weeks.clamp(1, 6);
  }

  double get _monthlyIncome =>
      double.tryParse(_incomeController.text.trim().replaceAll('.', '')) ?? 0;

  String get _purpose => _purposeController.text.trim();

  String get _phone => _phoneController.text.replaceAll(' ', '').trim();

  String get _employer => _employerController.text.trim();

  Future<void> _persistDraft({int? stepOverride}) async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;

    final draft = LoanDraft(
      phone: _phone,
      requestedAmount: _requestedAmount,
      termWeeks: _termWeeks,
      monthlyIncome: _monthlyIncome,
      employer: _employer,
      purpose: _purpose,
      currentStep: stepOverride ?? _step,
      updatedAt: DateTime.now(),
    );

    await ref.read(profileRepositoryProvider).saveLoanDraft(
          uid: uid,
          draft: draft,
        );
  }

  String _formatPhoneForDisplay(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length && i < 10; i++) {
      buffer.write(digits[i]);
      if ((i == 2 || i == 5) && i != digits.length - 1) {
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  Future<void> _saveQuickProfile(AppUser? currentProfile) async {
    final firebaseUser = ref.read(currentUserProvider);
    if (firebaseUser == null) return;

    final updatedUser = AppUser(
      uid: firebaseUser.uid,
      email: firebaseUser.email ?? currentProfile?.email ?? '',
      role: currentProfile?.role ?? 'user',
      fullName: currentProfile?.fullName ?? '',
      phone: _phone,
      address: currentProfile?.address ?? '',
      nationalId: currentProfile?.nationalId ?? '',
      employer: _employer,
      monthlyIncome: _monthlyIncome,
      kycStatus: currentProfile?.kycStatus ?? 'pending',
      contactsSyncCount: currentProfile?.contactsSyncCount ?? 0,
      contactsSyncedAt: currentProfile?.contactsSyncedAt,
      createdAt: currentProfile?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await ref.read(profileRepositoryProvider).upsertProfile(updatedUser);
  }

  Future<void> _goToStep2(AppUser? profile) async {
    if (_phone.isEmpty ||
        _requestedAmount <= 0 ||
        _monthlyIncome <= 0 ||
        _employer.isEmpty ||
        _purpose.isEmpty) {
      await showAppNoticeDialog(
        context,
        title: 'Thiếu thông tin',
        message:
            'Hãy điền SĐT, số tiền vay, nghề nghiệp, thu nhập và mục đích vay.',
        isError: true,
      );
      return;
    }

    setState(() {
      _loading = false;
      _step = 2;
    });

    unawaited(_syncStepDataInBackground(
      profile: profile,
      stepOverride: 2,
    ));
  }

  Future<void> _jumpToStep(int step) async {
    setState(() => _step = step);
    unawaited(_syncStepDataInBackground(stepOverride: step));
  }

  Future<void> _syncStepDataInBackground({
    AppUser? profile,
    required int stepOverride,
  }) async {
    try {
      final operations = <Future<void>>[
        _persistDraft(stepOverride: stepOverride).timeout(
          const Duration(seconds: 4),
        ),
      ];

      if (profile != null || stepOverride == 2) {
        operations.add(
          _saveQuickProfile(profile).timeout(const Duration(seconds: 4)),
        );
      }

      await Future.wait(operations);
    } catch (_) {
      // Keep the funnel moving even if background sync is slow or temporarily unavailable.
    }
  }

  Future<void> _submit() async {
    final profile = ref.read(userProfileProvider).value;
    final documentCount = ref.read(userDocumentsProvider).value?.length ?? 0;
    final applications = ref.read(loanApplicationsProvider).value ?? const [];
    final hasPendingApplication = applications.any(
      (application) => const {'reviewing', 'pending', 'submitted'}
          .contains(application.status.toLowerCase()),
    );

    if (hasPendingApplication) {
      await showAppNoticeDialog(
        context,
        title: 'Mình nhắc bạn một chút',
        message:
            'Bạn đang có một hồ sơ vay chờ duyệt. Mình sẽ giữ hồ sơ mới lại để tránh bị trùng. Khi có kết quả, bạn có thể tạo hồ sơ tiếp nhé.',
        isError: true,
      );
      return;
    }

    if (profile == null || !profile.isProfileComplete) {
      await showAppNoticeDialog(
        context,
        title: 'Thiếu xác minh nhẹ',
        message: 'Bạn cần hoàn tất hồ sơ cá nhân trước khi nộp hồ sơ vay.',
        isError: true,
      );
      return;
    }

    if (!profile.hasSyncedContacts) {
      await showAppNoticeDialog(
        context,
        title: 'Mình cần thêm danh bạ của bạn',
        message:
            'Bạn hãy cho phép truy cập và đồng bộ danh bạ trước khi nộp hồ sơ nhé. Khi hoàn tất bước này, hệ thống sẽ có thêm thông tin để tiếp tục xem xét hồ sơ của bạn.',
        isError: true,
      );
      return;
    }

    if (documentCount < 3) {
      await showAppNoticeDialog(
        context,
        title: 'Thiếu xác minh chính',
        message:
            'Bạn cần tải đủ CCCD mặt trước, mặt sau và ảnh selfie trước khi nộp.',
        isError: true,
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final result =
          await ref.read(loanRepositoryProvider).submitLoanApplication(
                amount: _requestedAmount,
                termWeeks: _termWeeks,
                purpose: _purpose,
              );

      final uid = ref.read(currentUserIdProvider);
      if (uid != null) {
        await ref.read(profileRepositoryProvider).clearLoanDraft(uid);
      }

      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Đã gửi hồ sơ vay',
        message:
            'Trạng thái hiện tại: ${_translateStatus(result['status']?.toString())}\n\n${result['message']}',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Nộp hồ sơ thất bại',
        message: translateFunctionsError(error),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _startContactsSyncFromFlow({bool auto = false}) {
    final firebaseUser = ref.read(currentUserProvider);
    if (firebaseUser == null || _preparingContacts || _backgroundSyncingContacts) {
      return;
    }

    setState(() {
      _contactsSyncStartedAt = DateTime.now();
      _preparingContacts = true;
      _backgroundSyncingContacts = false;
      _contactsSyncProcessed = 0;
      _contactsSyncTotal = ContactSyncService.maxContactsToSync;
      _contactsSyncStatusText = auto
          ? 'Đang tự đồng bộ tối đa 100 liên hệ ở nền...'
          : 'Bắt đầu đồng bộ tối đa 100 liên hệ...';
    });
    unawaited(_syncContactsFromFlow(firebaseUser.uid, auto: auto));
  }

  Future<void> _syncContactsFromFlow(String uid, {required bool auto}) async {
    try {
      final result = await _contactSyncService.requestAndReadContacts(
        onProgress: (processed, total, message) {
          if (!mounted) return;
          setState(() {
            _contactsSyncProcessed = processed;
            _contactsSyncTotal = total;
            _contactsSyncStatusText = message;
          });
        },
      );
      if (!result.granted) {
        if (!mounted) return;
        setState(() {
          _contactsSyncStatusText = result.errorMessage ??
              'Bạn hãy cho phép danh bạ để hoàn tất bước xác minh này nhé. Khi xong, hồ sơ của bạn sẽ được tiếp tục xem xét.';
        });
        return;
      }

      if (result.contacts.isEmpty) {
        if (!mounted) return;
        setState(() {
          _contactsSyncStatusText =
              'Mình chưa tìm thấy liên hệ nào có số điện thoại trong 100 liên hệ đầu tiên.';
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _preparingContacts = false;
        _backgroundSyncingContacts = true;
        _contactsSyncProcessed = 0;
        _contactsSyncTotal = result.contacts.length;
        _contactsSyncStatusText =
            'Đã chuẩn bị ${result.contacts.length} liên hệ. Mình đang đồng bộ ở nền...';
      });
      unawaited(_saveContactsInBackground(uid, result.contacts));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _contactsSyncStatusText = 'Đồng bộ danh bạ thất bại: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _preparingContacts = false);
      }
    }
  }

  Future<void> _saveContactsInBackground(
    String uid,
    List<PhoneContact> contacts,
  ) async {
    try {
      await ref.read(profileRepositoryProvider).savePhoneContacts(
        uid: uid,
        contacts: contacts,
        onProgress: (processed, total, message) {
          if (!mounted) return;
          setState(() {
            _contactsSyncProcessed = processed;
            _contactsSyncTotal = total;
            _contactsSyncStatusText = message;
          });
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _contactsSyncStatusText = 'Đồng bộ nền thất bại: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _backgroundSyncingContacts = false);
      }
    }
  }

  void _maybeFinalizeContactsSync(AppUser? profile) {
    if (!_backgroundSyncingContacts || profile == null) return;
    final syncedAt = profile.contactsSyncedAt;
    final startedAt = _contactsSyncStartedAt;
    if (syncedAt == null || startedAt == null || !profile.hasSyncedContacts) {
      return;
    }
    if (syncedAt.isBefore(startedAt.subtract(const Duration(seconds: 1)))) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_backgroundSyncingContacts) return;
      setState(() {
        _backgroundSyncingContacts = false;
        _contactsSyncProcessed = profile.contactsSyncCount;
        _contactsSyncTotal = profile.contactsSyncCount;
        _contactsSyncStatusText =
            'Đã đồng bộ ${profile.contactsSyncCount} liên hệ thành công.';
      });
    });
  }


  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final documentCount = ref.watch(userDocumentsProvider).value?.length ?? 0;
    final draft = ref.watch(loanDraftProvider).value ?? LoanDraft.empty();

    _hydrate(profile: profile, draft: draft);
    _maybeFinalizeContactsSync(profile);

    final provisionalLimit = _requestedAmount > 0 ? _requestedAmount : 0.0;

    if (_step == 3 &&
        !_attemptedAutoContactSync &&
        !(profile?.hasSyncedContacts ?? false) &&
        !_preparingContacts &&
        !_backgroundSyncingContacts) {
      _attemptedAutoContactSync = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _startContactsSyncFromFlow(auto: true);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Hồ sơ vay 4 bước')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ProgressHeader(
            step: _step,
            title: _titleForStep(_step),
            subtitle: _subtitleForStep(_step),
          ),
          const SizedBox(height: 16),
          if (_step == 1) ...[
            _QuickStepCard(
              phoneController: _phoneController,
              amountController: _amountController,
              incomeController: _incomeController,
              employerController: _employerController,
              termController: _termController,
              purposeController: _purposeController,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : () => _goToStep2(profile),
              child: Text(_loading ? 'Đang lưu...' : 'Xem chi tiết khoản vay'),
            ),
          ],
          if (_step == 2) ...[
            _PreApprovalCard(
              amount: provisionalLimit,
              requestedAmount: _requestedAmount,
              termWeeks: _termWeeks,
            ),
            const SizedBox(height: 12),
            const _InfoStrip(
              text:
                  'Hoàn tất các bước tiếp theo để tăng hạn mức, duyệt hồ sơ nhanh hơn và sẵn sàng giải ngân.',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _jumpToStep(1),
                    child: const Text('Chỉnh sửa'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _jumpToStep(3),
                    child: const Text('Tiếp tục xác minh'),
                  ),
                ),
              ],
            ),
          ],
          if (_step == 3) ...[
            _VerificationLightCard(
              profile: profile,
              phone: _phone,
              employer: _employer,
              income: _monthlyIncome,
              contactsSyncCount: profile?.contactsSyncCount ?? 0,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: (_preparingContacts || _backgroundSyncingContacts)
                  ? null
                  : () => _startContactsSyncFromFlow(auto: false),
              child: Text(
                _preparingContacts
                    ? 'Đang chuẩn bị danh bạ...'
                    : _backgroundSyncingContacts
                        ? 'Đang đồng bộ nền...'
                    : (profile?.hasSyncedContacts ?? false)
                        ? 'Đồng bộ lại danh bạ'
                        : 'Cho phép truy cập danh bạ',
              ),
            ),
            if (_contactsSyncStatusText != null) ...[
              const SizedBox(height: 10),
              Text(
                _contactsSyncStatusText!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (_preparingContacts || _backgroundSyncingContacts) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: _backgroundSyncingContacts
                    ? null
                    : _contactsSyncTotal > 0
                    ? (_contactsSyncProcessed / _contactsSyncTotal).clamp(0, 1)
                    : null,
                borderRadius: BorderRadius.circular(999),
                minHeight: 8,
              ),
              const SizedBox(height: 8),
              Text(
                _backgroundSyncingContacts
                    ? 'Đang ghi dữ liệu nền lên hệ thống...'
                    : 'Tiến độ: $_contactsSyncProcessed/${_contactsSyncTotal == 0 ? ContactSyncService.maxContactsToSync : _contactsSyncTotal} liên hệ',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () async {
                unawaited(_persistDraft(stepOverride: 3));
                if (!context.mounted) return;
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
              child: const Text('Bổ sung hồ sơ cá nhân'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => _jumpToStep(4),
              child: const Text('Tôi đã hiểu, sang bước tiếp theo'),
            ),
          ],
          if (_step == 4) ...[
            _VerificationMainCard(
              documentCount: documentCount,
              profileComplete: profile?.isProfileComplete == true,
              provisionalLimit: provisionalLimit,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () async {
                unawaited(_persistDraft(stepOverride: 4));
                if (!context.mounted) return;
                await Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const DocumentUploadScreen()),
                );
              },
              child: const Text('Tải CCCD và ảnh selfie'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _loading ? null : _submit,
              child: Text(_loading ? 'Đang gửi...' : 'Nộp hồ sơ vay ngay'),
            ),
          ],
        ],
      ),
    );
  }

  String _translateStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'approved':
        return 'Đã duyệt';
      case 'reviewing':
        return 'Đang thẩm định';
      case 'rejected':
        return 'Từ chối';
      case 'submitted':
        return 'Đã nộp';
      case 'pending':
        return 'Chờ xử lý';
      default:
        return status ?? '--';
    }
  }

  String _titleForStep(int step) {
    switch (step) {
      case 1:
        return 'Bước 1/4: Thông tin cơ bản';
      case 2:
        return 'Bước 2/4: Chi tiết khoản vay';
      case 3:
        return 'Bước 3/4: Bổ sung thông tin';
      case 4:
        return 'Bước 4/4: Xác thực danh tính';
      default:
        return 'Hồ sơ vay';
    }
  }

  String _subtitleForStep(int step) {
    switch (step) {
      case 1:
        return 'Cung cấp thông tin để hệ thống đánh giá sơ bộ.';
      case 2:
        return 'Chi tiết lịch trả nợ cho khoản vay của bạn.';
      case 3:
        return 'Hoàn thiện hồ sơ cá nhân để tăng tỷ lệ duyệt.';
      case 4:
        return 'Xác thực tài liệu để hoàn tất nộp hồ sơ.';
      default:
        return '';
    }
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.step,
    required this.title,
    required this.subtitle,
  });

  final int step;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: step / 4,
              borderRadius: BorderRadius.circular(999),
              minHeight: 10,
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

class _QuickStepCard extends StatelessWidget {
  const _QuickStepCard({
    required this.phoneController,
    required this.amountController,
    required this.incomeController,
    required this.employerController,
    required this.termController,
    required this.purposeController,
  });

  final TextEditingController phoneController;
  final TextEditingController amountController;
  final TextEditingController incomeController;
  final TextEditingController employerController;
  final TextEditingController termController;
  final TextEditingController purposeController;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const _IntroBlock(
              title: 'Cung cấp thông tin đăng ký',
              body:
                  'Vui lòng điền đầy đủ số điện thoại, mức thu nhập và nhu cầu vay của bạn.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
                VietnamesePhoneInputFormatter(),
              ],
              decoration: const InputDecoration(
                labelText: 'Số điện thoại',
                hintText: 'Ví dụ: 090 123 4567',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(12),
                CurrencyTextInputFormatter(),
              ],
              decoration: const InputDecoration(
                labelText: 'Số tiền cần vay (VND)',
                hintText: 'Ví dụ: 5.000.000',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: incomeController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(12),
                CurrencyTextInputFormatter(),
              ],
              decoration: const InputDecoration(
                labelText: 'Thu nhập tự khai mỗi tháng (VND)',
                hintText: 'Ví dụ: 12.000.000',
                helperText: 'Thu nhập tối thiểu: 1.000.000 VND',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: employerController,
              decoration: const InputDecoration(
                labelText: 'Nghề nghiệp / nơi làm việc',
                hintText: 'Ví dụ: Nhân viên văn phòng tại ABC',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: termController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(1),
              ],
              decoration: const InputDecoration(
                labelText: 'Kỳ hạn mong muốn (tuần)',
                hintText: '1 - 6',
                helperText:
                    'Tối đa ${LoanPolicy.maxTermWeeks} tuần (${LoanPolicy.maxTermDays} ngày)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: purposeController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Mục đích vay',
                hintText: 'Thanh toán học phí, xoay vốn, mua xe...',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreApprovalCard extends StatelessWidget {
  const _PreApprovalCard({
    required this.amount,
    required this.requestedAmount,
    required this.termWeeks,
  });

  final double amount;
  final double requestedAmount;
  final int termWeeks;

  @override
  Widget build(BuildContext context) {
    final estimate = LoanCalculator.estimate(
      principal: amount,
      termWeeks: termWeeks,
    );

    return Card(
      color: const Color(0xFF12343B),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chi tiết khoản vay',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              AppFormatters.currency(amount),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: const Color(0xFFE8FF7A),
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'Bạn đang yêu cầu vay ${AppFormatters.currency(requestedAmount)} trong $termWeeks tuần (${termWeeks * 7} ngày). Hệ thống hỗ trợ trả góp với số tiền thanh toán mỗi tuần cố định.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.86),
                  ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _MetricBadge(
                  label: 'Trả mỗi tuần',
                  value: AppFormatters.currency(estimate.weeklyInstallment),
                ),
                _MetricBadge(
                  label: 'Tổng tiền trả',
                  value: AppFormatters.currency(estimate.totalPayable),
                ),
                _MetricBadge(
                  label: 'Phí quá hạn',
                  value: AppFormatters.currency(LoanPolicy.overduePenaltyFee),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  const _MetricBadge({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _VerificationLightCard extends StatelessWidget {
  const _VerificationLightCard({
    required this.profile,
    required this.phone,
    required this.employer,
    required this.income,
    required this.contactsSyncCount,
  });

  final AppUser? profile;
  final String phone;
  final String employer;
  final double income;
  final int contactsSyncCount;

  @override
  Widget build(BuildContext context) {
    final fullNameReady = profile?.fullName.isNotEmpty == true;
    final addressReady = profile?.address.isNotEmpty == true;
    final nationalIdReady = profile?.nationalId.isNotEmpty == true;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _IntroBlock(
              title: 'Bổ sung hồ sơ cá nhân',
              body:
                  'Hoàn tất thông tin cá nhân và chia sẻ danh bạ để hệ thống tiếp tục xem xét và phê duyệt hồ sơ vay của bạn.',
            ),
            const SizedBox(height: 12),
            _CheckRow(label: 'SĐT đã khai báo', done: phone.isNotEmpty),
            _CheckRow(
                label: 'Nghề nghiệp / nơi làm việc', done: employer.isNotEmpty),
            _CheckRow(label: 'Thu nhập tự khai', done: income > 0),
            _CheckRow(
              label: contactsSyncCount > 0
                  ? 'Danh bạ đã đồng bộ ($contactsSyncCount liên hệ)'
                  : 'Danh bạ điện thoại',
              done: contactsSyncCount > 0,
            ),
            _CheckRow(label: 'Họ và tên đầy đủ', done: fullNameReady),
            _CheckRow(label: 'Địa chỉ hiện tại', done: addressReady),
            _CheckRow(label: 'Số CCCD', done: nationalIdReady),
          ],
        ),
      ),
    );
  }
}

class _VerificationMainCard extends StatelessWidget {
  const _VerificationMainCard({
    required this.documentCount,
    required this.profileComplete,
    required this.provisionalLimit,
  });

  final int documentCount;
  final bool profileComplete;
  final double provisionalLimit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _IntroBlock(
              title: 'Xác thực giấy tờ tùy thân',
              body:
                  'Tải lên ảnh CCCD hai mặt và ảnh chân dung để hoàn tất quá trình định danh.',
            ),
            const SizedBox(height: 12),
            _CheckRow(label: 'Hồ sơ cá nhân đã đủ', done: profileComplete),
            _CheckRow(label: 'Tài liệu KYC đã tải', done: documentCount >= 3),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E7),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                documentCount >= 3
                    ? 'Tốt rồi. Hồ sơ của bạn đã sẵn sàng để nộp.'
                    : 'Bạn đang ở bước cuối. Hoàn tất tài liệu để mở khóa nộp hồ sơ, trả góp theo tuần và tăng cơ hội duyệt nhanh hơn.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(text),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.done,
  });

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _IntroBlock extends StatelessWidget {
  const _IntroBlock({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(body, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}
