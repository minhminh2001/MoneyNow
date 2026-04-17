import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/status_chip.dart';
import '../../models/app_user.dart';
import '../../providers/app_providers.dart';
import '../../models/loan_draft.dart';
import '../application/application_list_screen.dart';
import '../documents/document_upload_screen.dart';
import '../loan/loan_list_screen.dart';
import '../profile/profile_screen.dart';
import '../application/create_application_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);
    final documentsAsync = ref.watch(userDocumentsProvider);
    final applicationsAsync = ref.watch(loanApplicationsProvider);
    final loansAsync = ref.watch(loansProvider);
    final draftAsync = ref.watch(loanDraftProvider);

    final profile = profileAsync.value;
    final documents = documentsAsync.value ?? const [];
    final applications = applicationsAsync.value ?? const [];
    final loans = loansAsync.value ?? const [];
    final draft = draftAsync.value ?? LoanDraft.empty();
    final user = ref.watch(currentUserProvider);
    final hasDraft = draft.requestedAmount > 0 || draft.purpose.isNotEmpty;
    final flowSteps = _buildFlowSteps(
      draft: draft,
      profile: profile,
      documentCount: documents.length,
    );
    final nextStep = _nextStepLabel(
      draft: draft,
      lightVerificationComplete: profile?.isLightVerificationComplete == true,
      documentCount: documents.length,
    );

    final displayName = profile?.fullName.isNotEmpty == true
        ? profile!.fullName
        : (user?.email ?? 'Người dùng');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Money Now'),
        actions: [
          IconButton(
            tooltip: 'Đăng xuất',
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(userProfileProvider);
          ref.invalidate(userDocumentsProvider);
          ref.invalidate(loanApplicationsProvider);
          ref.invalidate(loansProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeroGreetingCard(
              displayName: displayName,
              email: user?.email ?? '--',
              profile: profile,
            ),
            const SizedBox(height: 12),
            _FlowOverviewCard(
              nextStep: nextStep,
              hasDraft: hasDraft,
              flowSteps: flowSteps,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const CreateApplicationScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            if (profile != null && !profile.isProfileComplete)
              const _WarningBanner(
                text:
                    'Bạn mới ở bước xác minh nhẹ. Hoàn tất hồ sơ cá nhân để tăng khả năng được duyệt.',
              ),
            if (documents.length < 3)
              const _WarningBanner(
                text:
                    'Bạn chưa hoàn tất xác minh chính. Tải CCCD và ảnh selfie để mở khóa nộp hồ sơ vay.',
              ),
            const SizedBox(height: 12),
            _SummaryGrid(
              items: [
                _SummaryItem(label: 'Tài liệu', value: '${documents.length}/3'),
                _SummaryItem(
                    label: 'Hồ sơ vay', value: '${applications.length}'),
                _SummaryItem(label: 'Khoản vay', value: '${loans.length}'),
              ],
            ),
            const SizedBox(height: 12),
            _ActionTile(
              title: 'Bước 1: Hồ sơ cá nhân',
              subtitle: 'SĐT, địa chỉ, nghề nghiệp, thu nhập',
              icon: Icons.badge_outlined,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ProfileScreen()),
                );
              },
            ),
            _ActionTile(
              title: 'Bước 2: Xác minh tài liệu',
              subtitle: 'CCCD mặt trước / mặt sau / ảnh selfie',
              icon: Icons.upload_file_outlined,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const DocumentUploadScreen()),
                );
              },
            ),
            _ActionTile(
              title: 'Kiểm tra hạn mức tạm tính',
              subtitle: 'Tính khoản vay tự động cho bạn',
              icon: Icons.request_quote_outlined,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const CreateApplicationScreen()),
                );
              },
            ),
            _ActionTile(
              title: 'Danh sách hồ sơ vay',
              subtitle: 'Theo dõi trạng thái phê duyệt và phản hồi',
              icon: Icons.assignment_outlined,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const ApplicationListScreen()),
                );
              },
            ),
            _ActionTile(
              title: 'Danh sách khoản vay',
              subtitle: 'Xem lịch thanh toán và cập nhật đã trả',
              icon: Icons.account_balance_wallet_outlined,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoanListScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

String _nextStepLabel({
  required LoanDraft draft,
  required bool lightVerificationComplete,
  required int documentCount,
}) {
  if (draft.requestedAmount <= 0 || draft.purpose.isEmpty) {
    return 'Bước 1/4: Khai báo nhanh để xem hạn mức tạm tính';
  }
  if (draft.currentStep < 3) {
    return 'Bước 2/4: Xem kết quả sơ bộ và tiếp tục xác minh';
  }
  if (!lightVerificationComplete) {
    return 'Bước 3/4: Hoàn tất hồ sơ cá nhân và đồng bộ danh bạ bắt buộc';
  }
  if (documentCount < 3) {
    return 'Bước 4/4: Tải CCCD và ảnh selfie để nộp hồ sơ';
  }
  return 'Bạn đã sẵn sàng nộp hồ sơ vay';
}

List<_FlowStepData> _buildFlowSteps({
  required LoanDraft draft,
  required AppUser? profile,
  required int documentCount,
}) {
  final quickInfoDone = draft.requestedAmount > 0 && draft.purpose.isNotEmpty;
  final preApprovalDone =
      draft.currentStep >= 3 || profile != null || documentCount > 0;
  final lightVerificationDone = profile?.isLightVerificationComplete == true;
  final mainVerificationDone = documentCount >= 3;

  int currentStep = 1;
  if (quickInfoDone && !preApprovalDone) {
    currentStep = 2;
  } else if (preApprovalDone && !lightVerificationDone) {
    currentStep = 3;
  } else if (lightVerificationDone && !mainVerificationDone) {
    currentStep = 4;
  } else if (mainVerificationDone) {
    currentStep = 4;
  }

  _FlowStepStatus statusFor({
    required int step,
    required bool done,
  }) {
    if (done) return _FlowStepStatus.done;
    if (step == currentStep) return _FlowStepStatus.current;
    return _FlowStepStatus.upcoming;
  }

  return [
    _FlowStepData(
      text: '1. Khai báo nhanh',
      status: statusFor(step: 1, done: quickInfoDone),
    ),
    _FlowStepData(
      text: '2. Xem hạn mức',
      status: statusFor(step: 2, done: preApprovalDone),
    ),
    _FlowStepData(
      text: '3. Xác minh nhẹ',
      status: statusFor(step: 3, done: lightVerificationDone),
    ),
    _FlowStepData(
      text: '4. Nộp hồ sơ',
      status: statusFor(step: 4, done: mainVerificationDone),
    ),
  ];
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFF7E9),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFFFE2A8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.info_outline),
        ),
        title: Text(text),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.items});

  final List<_SummaryItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: items
          .map(
            (item) => SizedBox(
              width: 160,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE9F7F7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.bubble_chart_rounded,
                          color: Color(0xFF0E7C86),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        item.label,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.value,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _SummaryItem {
  const _SummaryItem({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

class _HeroGreetingCard extends StatelessWidget {
  const _HeroGreetingCard({
    required this.displayName,
    required this.email,
    required this.profile,
  });

  final String displayName;
  final String email;
  final AppUser? profile;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.98, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(scale: value, child: child);
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F7E88),
              Color(0xFF1F9EA4),
              Color(0xFF58C6B6),
            ],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F7E88).withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: -20,
              right: -10,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                runSpacing: 16,
                spacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Xin chào, $displayName',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        email,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.82),
                            ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Tiếp tục hồ sơ để tăng cơ hội được duyệt nhanh hơn.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                      ),
                    ],
                  ),
                  if (profile != null)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: StatusChip(status: profile!.kycStatus),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FlowOverviewCard extends StatelessWidget {
  const _FlowOverviewCard({
    required this.nextStep,
    required this.hasDraft,
    required this.flowSteps,
    required this.onTap,
  });

  final String nextStep;
  final bool hasDraft;
  final List<_FlowStepData> flowSteps;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE9F8F7),
            Color(0xFFF7FCFF),
            Color(0xFFFFF5EE),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Card(
        color: Colors.transparent,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFF12343B),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.auto_graph_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hasDraft ? 'Tiếp tục hồ sơ vay' : 'Bắt đầu hồ sơ vay mới',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                nextStep,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: flowSteps
                    .map(
                      (step) => _StepChip(
                        text: step.text,
                        status: step.status,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onTap,
                child: Text(hasDraft ? 'Tiếp tục ngay' : 'Bắt đầu ngay'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE9F7F7), Color(0xFFFFF0E9)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: const Color(0xFF0E7C86)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF66778B),
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.text,
    required this.status,
  });

  final String text;
  final _FlowStepStatus status;

  @override
  Widget build(BuildContext context) {
    final isDone = status == _FlowStepStatus.done;
    final isCurrent = status == _FlowStepStatus.current;

    final backgroundColor = isDone
        ? const Color(0xFFDCF6E9)
        : isCurrent
            ? const Color(0xFF12343B)
            : Colors.white.withValues(alpha: 0.92);
    final borderColor = isDone
        ? const Color(0xFFA8DEC2)
        : isCurrent
            ? const Color(0xFF12343B)
            : const Color(0xFFDCEAF1);
    final textColor = isDone
        ? const Color(0xFF197A4B)
        : isCurrent
            ? Colors.white
            : const Color(0xFF284257);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isDone) ...[
            const Icon(
              Icons.check_circle_rounded,
              size: 16,
              color: Color(0xFF197A4B),
            ),
            const SizedBox(width: 6),
          ] else if (isCurrent) ...[
            const Icon(
              Icons.radio_button_checked_rounded,
              size: 16,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              color: textColor,
              fontWeight: isCurrent || isDone ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowStepData {
  const _FlowStepData({
    required this.text,
    required this.status,
  });

  final String text;
  final _FlowStepStatus status;
}

enum _FlowStepStatus {
  done,
  current,
  upcoming,
}
