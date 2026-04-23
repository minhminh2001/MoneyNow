import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/formatters.dart';

import '../../core/widgets/app_notice_dialog.dart';
import '../../core/widgets/status_chip.dart';
import '../../models/app_user.dart';
import '../../models/loan_application.dart';
import '../../providers/app_providers.dart';
import '../../models/loan_draft.dart';
import '../admin/loan_review_admin_screen.dart';
import '../application/application_list_screen.dart';
import '../charts/loan_charts_screen.dart';
import '../documents/document_upload_screen.dart';
import '../loan/loan_list_screen.dart';
import '../notifications/notifications_screen.dart';
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
    final isAdmin = ref.watch(currentUserIsAdminProvider);
    final documents = documentsAsync.value ?? const [];
    final applications = applicationsAsync.value ?? const [];
    final loans = loansAsync.value ?? const [];
    final draft = draftAsync.value ?? LoanDraft.empty();
    final hasPendingApplication = applications.any(_isPendingApplication);
    final pendingApplication = hasPendingApplication
        ? _latestPendingApplication(applications)
        : null;
    final user = ref.watch(currentUserProvider);
    final hasDraft = draft.requestedAmount > 0 || draft.purpose.isNotEmpty;
    final flowCardTitle = hasPendingApplication
        ? 'Hồ sơ vay đang chờ duyệt'
        : (hasDraft ? 'Tiếp tục hồ sơ vay' : 'Bắt đầu hồ sơ vay mới');
    final flowPrimaryActionLabel =
        hasPendingApplication ? 'Xem hồ sơ vay' : (hasDraft ? 'Tiếp tục ngay' : 'Bắt đầu ngay');
    final flowSteps = _buildFlowSteps(
      draft: draft,
      profile: profile,
      documentCount: documents.length,
      hasPendingApplication: hasPendingApplication,
    );
    final completedStepCount = flowSteps
        .where((step) => step.status == _FlowStepStatus.done)
        .length;
    final currentFlowStep = flowSteps
        .firstWhere(
          (step) => step.status == _FlowStepStatus.current,
          orElse: () => flowSteps.last,
        )
        .step;
    final nextStep = _nextStepLabel(
      draft: draft,
      lightVerificationComplete: profile?.isLightVerificationComplete == true,
      documentCount: documents.length,
      hasPendingApplication: hasPendingApplication,
    );
    final recommendedAction = _recommendedActionLabel(
      draft: draft,
      lightVerificationComplete: profile?.isLightVerificationComplete == true,
      documentCount: documents.length,
      hasPendingApplication: hasPendingApplication,
    );

    final displayName = profile?.fullName.isNotEmpty == true
        ? profile!.fullName
        : (user?.email ?? 'Người dùng');

    final unreadCount = ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Money Now'),
        actions: [
          if (isAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE4CF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Admin mode',
                    style: TextStyle(
                      color: Color(0xFF9D470D),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Thông báo',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const NotificationsScreen()),
              );
            },
            icon: Badge(
              label: Text('$unreadCount'),
              isLabelVisible: unreadCount > 0,
              backgroundColor: const Color(0xFFE46A11),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
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
              hasPendingApplication: hasPendingApplication,
            ),
            if (isAdmin) ...[
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('Quản trị hồ sơ vay'),
                  subtitle: Text(
                    'Bạn đang đăng nhập bằng tài khoản admin: ${profile?.role ?? '--'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LoanReviewAdminScreen(),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            _FlowOverviewCard(
              title: flowCardTitle,
              nextStep: nextStep,
              hasDraft: hasDraft,
              hasPendingApplication: hasPendingApplication,
              pendingApplication: pendingApplication,
              primaryActionLabel: flowPrimaryActionLabel,
              flowSteps: flowSteps
                  .map(
                    (step) => step.copyWith(
                      onTap: () async {
                        if (hasPendingApplication) {
                          if (!context.mounted) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ApplicationListScreen(),
                            ),
                          );
                          return;
                        }

                        final blockedMessage = _blockedStepMessage(
                          step: step.step,
                          draft: draft,
                          profile: profile,
                          documentCount: documents.length,
                        );
                        if (blockedMessage != null) {
                          await HapticFeedback.lightImpact();
                          if (!context.mounted) return;
                          await showAppNoticeDialog(
                            context,
                            title: 'Chưa thể vào bước này',
                            message: blockedMessage,
                            isError: true,
                          );
                          return;
                        }

                        if (hasPendingApplication) {
                          if (!context.mounted) return;
                          await showAppNoticeDialog(
                            context,
                            title: 'Mình nhắc bạn một chút',
                            message:
                                'Bạn đang có hồ sơ vay chờ duyệt. Mình sẽ đưa bạn tới danh sách hồ sơ để theo dõi kết quả nhé.',
                            isError: true,
                          );
                          return;
                        }

                        if (!context.mounted) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => CreateApplicationScreen(
                              initialStep: step.step,
                            ),
                          ),
                        );
                      },
                    ),
                  )
                  .toList(),
              completedStepCount: completedStepCount,
              recommendedAction: recommendedAction,
              onTap: () async {
                if (hasPendingApplication) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ApplicationListScreen(),
                    ),
                  );
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CreateApplicationScreen(
                      initialStep: currentFlowStep,
                    ),
                  ),
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
              onTap: () async {
                if (hasPendingApplication) {
                  await showAppNoticeDialog(
                    context,
                    title: 'Mình nhắc bạn một chút',
                    message:
                        'Bạn đang có hồ sơ vay chờ duyệt. Khi hồ sơ hiện tại có kết quả, mình sẽ mở lại bước tạo hồ sơ mới cho bạn.',
                    isError: true,
                  );
                  return;
                }
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
            if (isAdmin)
              _ActionTile(
                title: 'Duyệt hồ sơ vay',
                subtitle: 'Khu vực quản trị để duyệt hoặc từ chối hồ sơ',
                icon: Icons.admin_panel_settings_outlined,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LoanReviewAdminScreen(),
                    ),
                  );
                },
              ),
            _ActionTile(
              title: 'Biểu đồ tài chính',
              subtitle: 'Tiến độ trả nợ và lịch sử khoản vay',
              icon: Icons.area_chart_rounded,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const LoanChartsScreen()),
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

bool _isPendingApplication(LoanApplication application) {
  return const {'reviewing', 'pending', 'submitted'}
      .contains(application.status.toLowerCase());
}

LoanApplication? _latestPendingApplication(List<LoanApplication> applications) {
  final pendingApplications = applications.where(_isPendingApplication).toList()
    ..sort((a, b) {
      final aTimestamp = a.createdAt?.millisecondsSinceEpoch ?? 0;
      final bTimestamp = b.createdAt?.millisecondsSinceEpoch ?? 0;
      return bTimestamp.compareTo(aTimestamp);
    });

  if (pendingApplications.isEmpty) return null;
  return pendingApplications.first;
}

String _nextStepLabel({
  required LoanDraft draft,
  required bool lightVerificationComplete,
  required int documentCount,
  required bool hasPendingApplication,
}) {
  if (hasPendingApplication) {
    return 'Bạn đang có hồ sơ vay chờ duyệt.';
  }

  final quickInfoDone =
      draft.currentStep >= 2 ||
      (draft.requestedAmount > 0 &&
          draft.phone.isNotEmpty &&
          draft.monthlyIncome > 0 &&
          draft.employer.isNotEmpty &&
          draft.purpose.isNotEmpty);
  final preApprovalDone = draft.currentStep >= 3;

  if (!quickInfoDone) {
    return 'Bước 1/4: Khai báo nhanh để xem hạn mức tạm tính';
  }
  if (!preApprovalDone) {
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

String _recommendedActionLabel({
  required LoanDraft draft,
  required bool lightVerificationComplete,
  required int documentCount,
  required bool hasPendingApplication,
}) {
  if (hasPendingApplication) {
    return 'Bạn có thể theo dõi kết quả ngay trong danh sách hồ sơ vay. Khi hồ sơ hiện tại có kết quả, mình sẽ mở lại luồng tạo mới cho bạn.';
  }

  final quickInfoDone =
      draft.currentStep >= 2 ||
      (draft.requestedAmount > 0 &&
          draft.phone.isNotEmpty &&
          draft.monthlyIncome > 0 &&
          draft.employer.isNotEmpty &&
          draft.purpose.isNotEmpty);
  final preApprovalDone = draft.currentStep >= 3;

  if (!quickInfoDone) {
    return 'Điền SĐT, số tiền vay và mục đích vay để mở khóa bước hạn mức.';
  }
  if (!preApprovalDone) {
    return 'Xem kết quả sơ bộ để biết hạn mức tạm tính của bạn.';
  }
  if (!lightVerificationComplete) {
    return 'Hoàn tất hồ sơ cá nhân và đồng bộ danh bạ để mở khóa bước nộp hồ sơ.';
  }
  if (documentCount < 3) {
    return 'Tải đủ CCCD mặt trước, mặt sau và ảnh selfie để hoàn tất KYC.';
  }
  return 'Bạn đã đủ điều kiện để vào bước 4 và nộp hồ sơ vay.';
}

String? _blockedStepMessage({
  required int step,
  required LoanDraft draft,
  required AppUser? profile,
  required int documentCount,
}) {
  final quickInfoDone = draft.requestedAmount > 0 && draft.purpose.isNotEmpty;
  final preApprovalReady = quickInfoDone;
  final lightVerificationDone = profile?.isLightVerificationComplete == true;

  if (step == 1) return null;
  if (step == 2 && !quickInfoDone) {
    return 'Bạn cần hoàn tất bước 1: khai báo nhanh trước khi xem hạn mức tạm tính.';
  }
  if (step == 3 && !preApprovalReady) {
    return 'Bạn cần hoàn tất bước 1 và xem kết quả sơ bộ ở bước 2 trước khi sang xác minh nhẹ.';
  }
  if (step == 4 && !lightVerificationDone) {
    return 'Bạn cần hoàn tất bước 3: hồ sơ cá nhân và đồng bộ danh bạ bắt buộc trước khi sang bước nộp hồ sơ.';
  }
  if (step == 4 && documentCount >= 3) {
    return null;
  }
  return null;
}

List<_FlowStepData> _buildFlowSteps({
  required LoanDraft draft,
  required AppUser? profile,
  required int documentCount,
  required bool hasPendingApplication,
}) {
  if (hasPendingApplication) {
    return const [
      _FlowStepData(
        step: 1,
        text: '1. Khai báo nhanh',
        status: _FlowStepStatus.upcoming,
      ),
      _FlowStepData(
        step: 2,
        text: '2. Xem hạn mức',
        status: _FlowStepStatus.upcoming,
      ),
      _FlowStepData(
        step: 3,
        text: '3. Xác minh nhẹ',
        status: _FlowStepStatus.upcoming,
      ),
      _FlowStepData(
        step: 4,
        text: '4. Nộp hồ sơ',
        status: _FlowStepStatus.upcoming,
      ),
    ];
  }

  final quickInfoDone =
      draft.currentStep >= 2 ||
      (draft.requestedAmount > 0 &&
          draft.phone.isNotEmpty &&
          draft.monthlyIncome > 0 &&
          draft.employer.isNotEmpty &&
          draft.purpose.isNotEmpty);
  final preApprovalDone = draft.currentStep >= 3;
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
      step: 1,
      text: '1. Khai báo nhanh',
      status: statusFor(step: 1, done: quickInfoDone),
    ),
    _FlowStepData(
      step: 2,
      text: '2. Xem hạn mức',
      status: statusFor(step: 2, done: preApprovalDone),
    ),
    _FlowStepData(
      step: 3,
      text: '3. Xác minh nhẹ',
      status: statusFor(step: 3, done: lightVerificationDone),
    ),
    _FlowStepData(
      step: 4,
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
            color: const Color(0xFFFFD39A),
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
                          color: const Color(0xFFFFF0E4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.bubble_chart_rounded,
                          color: Color(0xFFE46A11),
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
    required this.hasPendingApplication,
  });

  final String displayName;
  final String email;
  final AppUser? profile;
  final bool hasPendingApplication;

  @override
  Widget build(BuildContext context) {
    final supportText = hasPendingApplication
        ? 'Hồ sơ của bạn đang được kiểm tra. Mình sẽ đồng hành cùng bạn trong lúc chờ kết quả.'
        : 'Tiếp tục hồ sơ để tăng cơ hội được duyệt nhanh hơn.';

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
              Color(0xFFE46A11),
              Color(0xFFFF8E2B),
              Color(0xFFFFB15A),
            ],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE46A11).withValues(alpha: 0.18),
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
                        supportText,
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
    required this.title,
    required this.nextStep,
    required this.hasDraft,
    required this.hasPendingApplication,
    required this.pendingApplication,
    required this.primaryActionLabel,
    required this.flowSteps,
    required this.completedStepCount,
    required this.recommendedAction,
    required this.onTap,
  });

  final String title;
  final String nextStep;
  final bool hasDraft;
  final bool hasPendingApplication;
  final LoanApplication? pendingApplication;
  final String primaryActionLabel;
  final List<_FlowStepData> flowSteps;
  final int completedStepCount;
  final String recommendedAction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progressDescription = hasPendingApplication
        ? 'Hồ sơ hiện tại đang trong hàng chờ phê duyệt, vì vậy luồng tạo mới sẽ tạm khóa.'
        : completedStepCount == 4
            ? 'Bạn đã hoàn tất toàn bộ luồng vay.'
            : 'Hoàn tất $completedStepCount trên 4 bước để sẵn sàng nộp hồ sơ.';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF0E4),
            Color(0xFFFFF8F2),
            Color(0xFFFFECDD),
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
                      color: const Color(0xFFB04E15),
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
                      title,
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
              if (hasPendingApplication && pendingApplication != null) ...[
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusChip(status: pendingApplication!.status),
                    Chip(
                      label: Text(
                        'Nộp lúc ${AppFormatters.dateTime(pendingApplication!.createdAt)}',
                      ),
                      backgroundColor: Colors.white.withValues(alpha: 0.82),
                      side: const BorderSide(color: Color(0xFFF2D9C4)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFF2D9C4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0E4),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.hourglass_top_rounded,
                          color: Color(0xFFE46A11),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hồ sơ đang được kiểm tra',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              pendingApplication!.decisionReason.isNotEmpty
                                  ? pendingApplication!.decisionReason
                                  : recommendedAction,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: const Color(0xFF486368)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (!hasPendingApplication) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: completedStepCount / 4,
                          minHeight: 10,
                          backgroundColor: const Color(0xFFDDEDF1),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFFE46A11),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$completedStepCount/4',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: const Color(0xFFB04E15),
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  progressDescription,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF617487),
                      ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFF2D9C4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.flag_circle_rounded,
                          color: Color(0xFFE46A11),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          recommendedAction,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: const Color(0xFF284257),
                                  ),
                        ),
                      ),
                    ],
                  ),
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
                          onTap: step.onTap,
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onTap,
                child: Text(primaryActionLabel),
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
                    colors: [Color(0xFFFFF0E4), Color(0xFFFFE7D2)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: const Color(0xFFE46A11)),
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
    this.onTap,
  });

  final String text;
  final _FlowStepStatus status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDone = status == _FlowStepStatus.done;
    final isCurrent = status == _FlowStepStatus.current;

    final backgroundColor = isDone
        ? const Color(0xFFFFE4CF)
        : isCurrent
            ? const Color(0xFFB04E15)
            : Colors.white.withValues(alpha: 0.92);
    final borderColor = isDone
        ? const Color(0xFFFFCBA3)
        : isCurrent
            ? const Color(0xFFB04E15)
            : const Color(0xFFF2D9C4);
    final textColor = isDone
        ? const Color(0xFF9D470D)
        : isCurrent
            ? Colors.white
            : const Color(0xFF284257);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
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
                  color: Color(0xFF9D470D),
                ),
                const SizedBox(width: 6),
              ] else if (isCurrent) ...[
                const Icon(
                  Icons.radio_button_checked_rounded,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(width: 6),
              ] else if (status == _FlowStepStatus.upcoming) ...[
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 16,
                  color: Color(0xFF6B7D8E),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                text,
                style: TextStyle(
                  color: textColor,
                  fontWeight:
                      isCurrent || isDone ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlowStepData {
  const _FlowStepData({
    required this.step,
    required this.text,
    required this.status,
    this.onTap,
  });

  final int step;
  final String text;
  final _FlowStepStatus status;
  final VoidCallback? onTap;

  _FlowStepData copyWith({
    int? step,
    String? text,
    _FlowStepStatus? status,
    VoidCallback? onTap,
  }) {
    return _FlowStepData(
      step: step ?? this.step,
      text: text ?? this.text,
      status: status ?? this.status,
      onTap: onTap ?? this.onTap,
    );
  }
}

enum _FlowStepStatus {
  done,
  current,
  upcoming,
}


