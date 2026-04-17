import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/services/contact_sync_service.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/widgets/app_notice_dialog.dart';
import '../../models/app_user.dart';
import '../../models/loan_draft.dart';
import '../../providers/app_providers.dart';
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
  bool _syncingContacts = false;
  bool _attemptedAutoContactSync = false;
  bool _hydrated = false;
  int _step = 1;

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
    _termController.text =
        draft.termMonths > 0 ? draft.termMonths.toString() : '6';
    _purposeController.text = draft.purpose;
    _step = (widget.initialStep ?? draft.currentStep).clamp(1, 4);
    _hydrated = true;
  }

  double get _requestedAmount =>
      double.tryParse(_amountController.text.trim().replaceAll('.', '')) ?? 0;

  int get _termMonths => int.tryParse(_termController.text.trim()) ?? 6;

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
      termMonths: _termMonths,
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
        title: 'Thiếu đồng bộ danh bạ',
        message:
            'Bạn cần cho phép và đồng bộ danh bạ điện thoại trước khi nộp hồ sơ. Đây là điều kiện bắt buộc để được xét duyệt vay.',
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
                termMonths: _termMonths,
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
        message: 'Nộp hồ sơ thất bại: $error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _syncContactsFromFlow() async {
    final firebaseUser = ref.read(currentUserProvider);
    if (firebaseUser == null || _syncingContacts) return;

    setState(() => _syncingContacts = true);
    try {
      final result = await _contactSyncService
          .requestAndReadContacts()
          .timeout(const Duration(seconds: 20));
      if (!result.granted) {
        if (!mounted) return;
        await showAppNoticeDialog(
          context,
          title: 'Không thể đồng bộ danh bạ',
          message: result.errorMessage ??
              'Hãy cho phép danh bạ để hoàn tất bước xác minh nhẹ. Đây là điều kiện bắt buộc để được xét duyệt vay.',
          isError: true,
        );
        return;
      }

      if (result.contacts.isEmpty) {
        if (!mounted) return;
        await showAppNoticeDialog(
          context,
          title: 'Danh bạ trống',
          message:
              'Không tìm thấy liên hệ nào có số điện thoại để đồng bộ. Vui lòng kiểm tra lại danh bạ trên máy.',
          isError: true,
        );
        return;
      }

      await ref
          .read(profileRepositoryProvider)
          .savePhoneContacts(
            uid: firebaseUser.uid,
            contacts: result.contacts,
          )
          .timeout(const Duration(seconds: 25));

      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Đã đồng bộ danh bạ',
        message:
            'Đã đồng bộ ${result.contacts.length} liên hệ dưới dạng bảo mật. Hồ sơ của bạn đã đạt điều kiện danh bạ bắt buộc.',
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is TimeoutException
          ? 'Đồng bộ danh bạ mất quá nhiều thời gian. Vui lòng thử lại hoặc đồng bộ khi mạng ổn định hơn.'
          : 'Đồng bộ danh bạ thất bại: $error';
      await showAppNoticeDialog(
        context,
        title: 'Không thể đồng bộ danh bạ',
        message: message,
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _syncingContacts = false);
      }
    }
  }

  double _provisionalLimit({
    required double income,
    required double requestedAmount,
    required bool profileComplete,
    required int documentCount,
  }) {
    if (income <= 0 || requestedAmount <= 0) return 0;

    var limit = math.min(requestedAmount, income * 2.2);
    if (profileComplete) {
      limit = math.min(requestedAmount, limit + income * 0.4);
    }
    if (documentCount >= 3) {
      limit = math.min(requestedAmount, limit + income * 0.6);
    }

    return limit.clamp(1000000, requestedAmount);
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final documentCount = ref.watch(userDocumentsProvider).value?.length ?? 0;
    final draft = ref.watch(loanDraftProvider).value ?? LoanDraft.empty();

    _hydrate(profile: profile, draft: draft);

    final provisionalLimit = _provisionalLimit(
      income: _monthlyIncome,
      requestedAmount: _requestedAmount,
      profileComplete: profile?.isProfileComplete == true,
      documentCount: documentCount,
    );

    if (_step == 3 &&
        !_attemptedAutoContactSync &&
        !(profile?.hasSyncedContacts ?? false) &&
        !_syncingContacts) {
      _attemptedAutoContactSync = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncContactsFromFlow();
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
              child: Text(_loading ? 'Đang lưu...' : 'Xem hạn mức tạm tính'),
            ),
          ],
          if (_step == 2) ...[
            _PreApprovalCard(
              amount: provisionalLimit,
              requestedAmount: _requestedAmount,
              termMonths: _termMonths,
            ),
            const SizedBox(height: 12),
            const _InfoStrip(
              text:
                  'Hoàn tất xác minh để tăng hạn mức, duyệt nhanh hơn và sẵn sàng nộp hồ sơ thật.',
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
              onPressed: _syncingContacts ? null : _syncContactsFromFlow,
              child: Text(
                _syncingContacts
                    ? 'Đang đồng bộ danh bạ...'
                    : (profile?.hasSyncedContacts ?? false)
                        ? 'Đồng bộ lại danh bạ'
                        : 'Cho phép và đồng bộ danh bạ',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () async {
                await _persistDraft(stepOverride: 3);
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
        return 'Bước 1/4: Khai báo nhanh';
      case 2:
        return 'Bước 2/4: Kết quả sơ bộ';
      case 3:
        return 'Bước 3/4: Xác minh nhẹ';
      case 4:
        return 'Bước 4/4: Xác minh chính';
      default:
        return 'Hồ sơ vay';
    }
  }

  String _subtitleForStep(int step) {
    switch (step) {
      case 1:
        return 'Khai báo thông tin cơ bản để tiếp tục.';
      case 2:
        return 'Cho user thấy giá trị trước khi yêu cầu xác minh sâu hơn.';
      case 3:
        return 'Bổ sung hồ sơ cá nhân và đồng bộ danh bạ. Đây là điều kiện bắt buộc để được xét duyệt vay.';
      case 4:
        return 'Hoàn tất xác minh tài liệu để sẵn sàng nộp hồ sơ.';
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
              title: 'Nhập thật nhanh để xem khả năng vay',
              body:
                  'Ở bước này bạn chỉ cần SĐT, số tiền mong muốn, nghề nghiệp, thu nhập và mục đích vay.',
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
              decoration: const InputDecoration(
                labelText: 'Kỳ hạn mong muốn (tháng)',
                hintText: '3 - 24',
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
    required this.termMonths,
  });

  final double amount;
  final double requestedAmount;
  final int termMonths;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF12343B),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hạn mức tạm tính của bạn',
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
              'Bạn đang yêu cầu ${AppFormatters.currency(requestedAmount)} trong $termMonths tháng.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.86),
                  ),
            ),
          ],
        ),
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
              title: 'Xác minh nhẹ bắt buộc để xét duyệt',
              body:
                  'Bạn cần hoàn tất hồ sơ cá nhân và đồng bộ danh bạ ở bước này. Đây là điều kiện bắt buộc trước khi hồ sơ được xét duyệt vay.',
            ),
            const SizedBox(height: 12),
            _CheckRow(label: 'SĐT đã khai báo', done: phone.isNotEmpty),
            _CheckRow(
                label: 'Nghề nghiệp / nơi làm việc', done: employer.isNotEmpty),
            _CheckRow(label: 'Thu nhập tự khai', done: income > 0),
            _CheckRow(
              label: contactsSyncCount > 0
                  ? 'Danh bạ đã đồng bộ ($contactsSyncCount liên hệ)'
                  : 'Danh bạ điện thoại (bắt buộc)',
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
              title: 'Hoàn tất xác minh chính',
              body:
                  'Tải CCCD mặt trước, mặt sau và ảnh selfie. Sau bước này bạn có thể nộp hồ sơ vay thật.',
            ),
            const SizedBox(height: 12),
            _CheckRow(label: 'Hồ sơ cá nhân đã đủ', done: profileComplete),
            _CheckRow(label: 'Tài liệu KYC đã tải', done: documentCount >= 3),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF2FBF7),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                documentCount >= 3
                    ? 'Tốt rồi. Hạn mức hiện tại của bạn đang ở mức ${AppFormatters.currency(provisionalLimit)} và đã sẵn sàng để nộp hồ sơ.'
                    : 'Bạn đang ở bước cuối. Hoàn tất tài liệu để mở khóa nộp hồ sơ và tăng cơ hội duyệt nhanh hơn.',
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
