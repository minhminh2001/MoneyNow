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

const Set<String> _requiredKycDocumentTypes = {
  'id_front',
  'id_back',
  'selfie',
};

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
    final kycDocumentCount = documents
        .where(
          (document) =>
              _requiredKycDocumentTypes.contains(document.type.toLowerCase()),
        )
        .length;
    final applications = applicationsAsync.value ?? const [];
    final loans = loansAsync.value ?? const [];
    final draft = draftAsync.value ?? LoanDraft.empty();
    final hasPendingApplication = applications.any(_isPendingApplication);
    final pendingApplication = hasPendingApplication
        ? _latestPendingApplication(applications)
        : null;
    final user = ref.watch(currentUserProvider);
    final flowProgress = _deriveBorrowerFlowProgress(
      draft: draft,
      profile: profile,
      documentCount: kycDocumentCount,
    );
    final hasDraft = flowProgress.hasStarted;
    final flowCardTitle = hasPendingApplication
        ? 'Hồ sơ vay đang chờ duyệt'
        : (hasDraft ? 'Tiếp tục hồ sơ vay' : 'Bắt đầu hồ sơ vay mới');
    final flowPrimaryActionLabel =
        hasPendingApplication ? 'Xem hồ sơ vay' : (hasDraft ? 'Tiếp tục ngay' : 'Bắt đầu ngay');
    final flowSteps = _buildFlowSteps(
      draft: draft,
      profile: profile,
      documentCount: kycDocumentCount,
      hasPendingApplication: hasPendingApplication,
    );
    final completedStepCount = hasPendingApplication
        ? 4
        : flowProgress.completedStepCount;
    final currentFlowStep = hasPendingApplication ? 4 : flowProgress.currentStep;
    final nextStep = _nextStepLabel(
      draft: draft,
      lightVerificationComplete: profile?.isLightVerificationComplete == true,
      documentCount: kycDocumentCount,
      hasPendingApplication: hasPendingApplication,
    );
    final recommendedAction = _recommendedActionLabel(
      draft: draft,
      lightVerificationComplete: profile?.isLightVerificationComplete == true,
      documentCount: kycDocumentCount,
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
            if (!isAdmin)
              _HeroGreetingCard(
                displayName: displayName,
                email: user?.email ?? '--',
                profile: profile,
                hasPendingApplication: hasPendingApplication,
              ),
            if (isAdmin) ...[
              _AdminDashboardCard(
                roleLabel: profile?.role ?? 'admin',
                applicationCount: applications.length,
                loanCount: loans.length,
                onPrimaryTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LoanReviewAdminScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
            ] else ...[
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
                            documentCount: kycDocumentCount,
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
            ],
            const SizedBox(height: 12),
            if (!isAdmin && profile != null && !profile.isProfileComplete)
              const _WarningBanner(
                text:
                    'Bạn mới ở bước xác minh nhẹ. Hoàn tất hồ sơ cá nhân để tăng khả năng được duyệt.',
              ),
            if (!isAdmin && kycDocumentCount < 3)
              const _WarningBanner(
                text:
                    'Bạn chưa hoàn tất xác minh chính. Tải CCCD và ảnh selfie để mở khóa nộp hồ sơ vay.',
              ),
            const SizedBox(height: 12),
            if (!isAdmin) ...[
              _SummaryGrid(
                items: [
                  _SummaryItem(
                      label: 'Tài liệu', value: '$kycDocumentCount/3'),
                  _SummaryItem(
                      label: 'Hồ sơ vay', value: '${applications.length}'),
                  _SummaryItem(label: 'Khoản vay', value: '${loans.length}'),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (!isAdmin) ...[
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
                subtitle: 'CCCD mặt trước / mặt sau / ảnh selfie / ảnh chụp hồ sơ bảo hiểm',
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
            ] else ...[
              Text(
                'Công cụ quản trị',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              _AdminActionGrid(
                items: [
                  _AdminActionItem(
                    title: 'Duyệt hồ sơ vay',
                    subtitle: 'Kiểm tra, duyệt hoặc từ chối hồ sơ mới',
                    icon: Icons.admin_panel_settings_outlined,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LoanReviewAdminScreen(),
                        ),
                      );
                    },
                  ),
                  _AdminActionItem(
                    title: 'Danh sách hồ sơ',
                    subtitle: 'Theo dõi toàn bộ hồ sơ và phản hồi đã gửi',
                    icon: Icons.assignment_outlined,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const ApplicationListScreen()),
                      );
                    },
                  ),
                  _AdminActionItem(
                    title: 'Khoản vay',
                    subtitle: 'Kiểm tra lịch thanh toán và trạng thái khoản vay',
                    icon: Icons.account_balance_wallet_outlined,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const LoanListScreen()),
                      );
                    },
                  ),
                  _AdminActionItem(
                    title: 'Biểu đồ tài chính',
                    subtitle: 'Xem nhanh xu hướng giải ngân và thu hồi',
                    icon: Icons.area_chart_rounded,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const LoanChartsScreen()),
                      );
                    },
                  ),
                ],
              ),
            ],
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

  final progress = _deriveBorrowerFlowProgress(
    draft: draft,
    profile: null,
    documentCount: documentCount,
    lightVerificationCompleteOverride: lightVerificationComplete,
  );

  if (!progress.quickInfoDone) {
    return 'Bước 1/4: Khai báo nhanh để xem hạn mức tạm tính';
  }
  if (!progress.preApprovalDone) {
    return 'Bước 2/4: Xem kết quả sơ bộ và tiếp tục xác minh';
  }
  if (!progress.lightVerificationDone) {
    return 'Bước 3/4: Hoàn tất hồ sơ cá nhân và đồng bộ danh bạ bắt buộc';
  }
  if (!progress.mainVerificationDone) {
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

  final progress = _deriveBorrowerFlowProgress(
    draft: draft,
    profile: null,
    documentCount: documentCount,
    lightVerificationCompleteOverride: lightVerificationComplete,
  );

  if (!progress.quickInfoDone) {
    return 'Điền SĐT, số tiền vay và mục đích vay để mở khóa bước hạn mức.';
  }
  if (!progress.preApprovalDone) {
    return 'Xem kết quả sơ bộ để biết hạn mức tạm tính của bạn.';
  }
  if (!progress.lightVerificationDone) {
    return 'Hoàn tất hồ sơ cá nhân và đồng bộ danh bạ để mở khóa bước nộp hồ sơ.';
  }
  if (!progress.mainVerificationDone) {
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
  final progress = _deriveBorrowerFlowProgress(
    draft: draft,
    profile: profile,
    documentCount: documentCount,
  );

  if (step == 1) return null;
  if (step == 2 && !progress.quickInfoDone) {
    return 'Bạn cần hoàn tất bước 1: khai báo nhanh trước khi xem hạn mức tạm tính.';
  }
  if (step == 3 && !progress.preApprovalDone) {
    return 'Bạn cần hoàn tất bước 1 và xem kết quả sơ bộ ở bước 2 trước khi sang xác minh nhẹ.';
  }
  if (step == 4 && !progress.lightVerificationDone) {
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

  final progress = _deriveBorrowerFlowProgress(
    draft: draft,
    profile: profile,
    documentCount: documentCount,
  );

  _FlowStepStatus statusFor({
    required int step,
    required bool done,
  }) {
    if (done) return _FlowStepStatus.done;
    if (step == progress.currentStep) return _FlowStepStatus.current;
    return _FlowStepStatus.upcoming;
  }

  return [
    _FlowStepData(
      step: 1,
      text: '1. Khai báo nhanh',
      status: statusFor(step: 1, done: progress.quickInfoDone),
    ),
    _FlowStepData(
      step: 2,
      text: '2. Xem hạn mức',
      status: statusFor(step: 2, done: progress.preApprovalDone),
    ),
    _FlowStepData(
      step: 3,
      text: '3. Xác minh nhẹ',
      status: statusFor(step: 3, done: progress.lightVerificationDone),
    ),
    _FlowStepData(
      step: 4,
      text: '4. Nộp hồ sơ',
      status: statusFor(step: 4, done: progress.mainVerificationDone),
    ),
  ];
}

_BorrowerFlowProgress _deriveBorrowerFlowProgress({
  required LoanDraft draft,
  required AppUser? profile,
  required int documentCount,
  bool? lightVerificationCompleteOverride,
}) {
  final quickInfoReady =
      draft.requestedAmount > 0 &&
      draft.phone.isNotEmpty &&
      draft.monthlyIncome > 0 &&
      draft.employer.isNotEmpty &&
      draft.purpose.isNotEmpty;
  final quickInfoDone = draft.currentStep >= 2 || quickInfoReady;

  final preApprovalDone = quickInfoDone && draft.currentStep >= 3;
  final lightVerificationReady =
      lightVerificationCompleteOverride ?? (profile?.isLightVerificationComplete == true);
  final lightVerificationDone = preApprovalDone && lightVerificationReady;
  final mainVerificationReady = documentCount >= 3;
  final mainVerificationDone = lightVerificationDone && mainVerificationReady;

  int currentStep;
  if (!quickInfoDone) {
    currentStep = 1;
  } else if (!preApprovalDone) {
    currentStep = 2;
  } else if (!lightVerificationDone) {
    currentStep = 3;
  } else {
    currentStep = 4;
  }

  final completedStepCount = [
    quickInfoDone,
    preApprovalDone,
    lightVerificationDone,
    mainVerificationDone,
  ].where((done) => done).length;

  final hasStarted = quickInfoDone || preApprovalDone || lightVerificationDone || mainVerificationDone;

  return _BorrowerFlowProgress(
    quickInfoDone: quickInfoDone,
    preApprovalDone: preApprovalDone,
    lightVerificationDone: lightVerificationDone,
    mainVerificationDone: mainVerificationDone,
    currentStep: currentStep,
    completedStepCount: completedStepCount,
    hasStarted: hasStarted,
  );
}

class _BorrowerFlowProgress {
  const _BorrowerFlowProgress({
    required this.quickInfoDone,
    required this.preApprovalDone,
    required this.lightVerificationDone,
    required this.mainVerificationDone,
    required this.currentStep,
    required this.completedStepCount,
    required this.hasStarted,
  });

  final bool quickInfoDone;
  final bool preApprovalDone;
  final bool lightVerificationDone;
  final bool mainVerificationDone;
  final int currentStep;
  final int completedStepCount;
  final bool hasStarted;
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

class _AdminDashboardCard extends StatelessWidget {
  const _AdminDashboardCard({
    required this.roleLabel,
    required this.applicationCount,
    required this.loanCount,
    required this.onPrimaryTap,
  });

  final String roleLabel;
  final int applicationCount;
  final int loanCount;
  final VoidCallback onPrimaryTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFB04E15),
            Color(0xFFE46A11),
            Color(0xFFFFA14B),
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
      child: Card(
        color: Colors.transparent,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bảng điều khiển quản trị',
                        style:
                            Theme.of(context).textTheme.titleLarge?.copyWith(
                                  color: Colors.white,
                                ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Phiên đăng nhập hiện tại: $roleLabel',
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.82),
                                ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Đi nhanh tới khu vực duyệt hồ sơ, theo dõi khoản vay đang hoạt động và mở các công cụ quản trị quan trọng.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _AdminStatPill(
                    label: 'Hồ sơ hiện có',
                    value: '$applicationCount',
                  ),
                  _AdminStatPill(
                    label: 'Khoản vay',
                    value: '$loanCount',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              FilledButton.tonalIcon(
                onPressed: onPrimaryTap,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF9D470D),
                ),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Mở khu vực duyệt hồ sơ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminStatPill extends StatelessWidget {
  const _AdminStatPill({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.82),
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                ),
          ),
        ],
      ),
    );
  }
}

class _AdminActionGrid extends StatelessWidget {
  const _AdminActionGrid({required this.items});

  final List<_AdminActionItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth >= 360
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items
              .map(
                (item) => SizedBox(
                  width: cardWidth,
                  child: _AdminActionCard(item: item),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _AdminActionItem {
  const _AdminActionItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _AdminActionCard extends StatelessWidget {
  const _AdminActionCard({required this.item});

  final _AdminActionItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                child: Icon(item.icon, color: const Color(0xFFE46A11)),
              ),
              const SizedBox(height: 18),
              Text(
                item.title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                item.subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF66778B),
                    ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Text(
                    'Mở nhanh',
                    style: TextStyle(
                      color: Color(0xFFE46A11),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: Color(0xFFE46A11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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
