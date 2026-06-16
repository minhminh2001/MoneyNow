import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_notice_dialog.dart';
import '../../providers/app_providers.dart';
import 'admin_analytics_panel.dart';
import 'admin_payment_settings_screen.dart';
import 'loan_review_admin_screen.dart';

enum _AdminSection {
  applications,
  analytics,
  paymentSettings,
}

class AdminWebShell extends ConsumerStatefulWidget {
  const AdminWebShell({super.key});

  @override
  ConsumerState<AdminWebShell> createState() => _AdminWebShellState();
}

class _AdminWebShellState extends ConsumerState<AdminWebShell> {
  _AdminSection _section = _AdminSection.applications;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1120;

            return Row(
              children: [
                if (wide)
                  SizedBox(
                    width: 280,
                    child: _AdminSidebar(
                      selectedSection: _section,
                      onSelect: (section) async {
                        if (section == null) {
                          await showAppNoticeDialog(
                            context,
                            title: 'Chưa mở module này',
                            message:
                                'Mục Khách hàng chưa được triển khai trong bản web admin hiện tại.',
                            isError: true,
                          );
                          return;
                        }
                        setState(() => _section = section);
                      },
                    ),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      _AdminTopBar(
                        userLabel: profile?.fullName.isNotEmpty == true
                            ? profile!.fullName
                            : (user?.phoneNumber ?? user?.email ?? 'Admin'),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            wide ? 8 : 16,
                            16,
                            wide ? 24 : 16,
                            16,
                          ),
                          child: ListView(
                            children: [
                              if (!wide)
                                _AdminMobileNav(
                                  selectedSection: _section,
                                  onSelect: (section) async {
                                    if (section == null) {
                                      await showAppNoticeDialog(
                                        context,
                                        title: 'Chưa mở module này',
                                        message:
                                            'Mục Khách hàng chưa được triển khai trong bản web admin hiện tại.',
                                        isError: true,
                                      );
                                      return;
                                    }
                                    setState(() => _section = section);
                                  },
                                ),
                              _AdminHeroCard(section: _section),
                              const SizedBox(height: 16),
                              _AdminSectionTitle(
                                title: switch (_section) {
                                  _AdminSection.applications =>
                                    'Hồ sơ cần xử lý',
                                  _AdminSection.analytics =>
                                    'Biểu đồ và thống kê',
                                  _AdminSection.paymentSettings =>
                                    'Cấu hình thanh toán',
                                },
                                subtitle: switch (_section) {
                                  _AdminSection.applications =>
                                    'Theo dõi, duyệt hoặc từ chối hồ sơ vay ngay trên giao diện web.',
                                  _AdminSection.analytics =>
                                    'Theo dõi nhanh tình hình hồ sơ và khoản vay trên giao diện quản trị.',
                                  _AdminSection.paymentSettings =>
                                    'Quản lý tập trung tài khoản nhận tiền trả nợ để không phải sửa qua màn hồ sơ.',
                                },
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: _section == _AdminSection.applications
                                    ? 640
                                    : _section == _AdminSection.analytics
                                        ? 720
                                        : 760,
                                child: Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: switch (_section) {
                                      _AdminSection.applications =>
                                        const LoanReviewAdminScreen(
                                          embedded: true,
                                          skipAdminGate: true,
                                        ),
                                      _AdminSection.analytics =>
                                        const AdminAnalyticsPanel(),
                                      _AdminSection.paymentSettings =>
                                        const AdminPaymentSettingsScreen(),
                                    },
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
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AdminSidebar extends ConsumerWidget {
  const _AdminSidebar({
    required this.selectedSection,
    required this.onSelect,
  });

  final _AdminSection selectedSection;
  final Future<void> Function(_AdminSection? section) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).value;
    final user = ref.watch(currentUserProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: const BoxDecoration(
        color: Color(0xFF12343B),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_outlined,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Money Now Admin',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile?.fullName.isNotEmpty == true
                      ? profile!.fullName
                      : (user?.phoneNumber ?? user?.email ?? 'Admin'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Quản trị viên',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.74),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _SidebarNavItem(
            icon: Icons.fact_check_outlined,
            title: 'Duyệt hồ sơ vay',
            active: selectedSection == _AdminSection.applications,
            onTap: () => onSelect(_AdminSection.applications),
          ),
          const SizedBox(height: 10),
          _SidebarNavItem(
            icon: Icons.insights_outlined,
            title: 'Biểu đồ và thống kê',
            active: selectedSection == _AdminSection.analytics,
            onTap: () => onSelect(_AdminSection.analytics),
          ),
          const SizedBox(height: 10),
          _SidebarNavItem(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Cấu hình thanh toán',
            active: selectedSection == _AdminSection.paymentSettings,
            onTap: () => onSelect(_AdminSection.paymentSettings),
          ),
          const SizedBox(height: 10),
          _SidebarNavItem(
            icon: Icons.people_alt_outlined,
            title: 'Khách hàng',
            active: false,
            enabled: false,
            onTap: () => onSelect(null),
          ),
          const Spacer(),
          Text(
            'Bản web quản trị đang tách riêng khỏi luồng mobile app.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.66),
                ),
          ),
        ],
      ),
    );
  }
}

class _AdminMobileNav extends StatelessWidget {
  const _AdminMobileNav({
    required this.selectedSection,
    required this.onSelect,
  });

  final _AdminSection selectedSection;
  final Future<void> Function(_AdminSection? section) onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _MobileNavChip(
            label: 'Duyệt hồ sơ vay',
            selected: selectedSection == _AdminSection.applications,
            onTap: () => onSelect(_AdminSection.applications),
          ),
          _MobileNavChip(
            label: 'Biểu đồ và thống kê',
            selected: selectedSection == _AdminSection.analytics,
            onTap: () => onSelect(_AdminSection.analytics),
          ),
          _MobileNavChip(
            label: 'Cấu hình thanh toán',
            selected: selectedSection == _AdminSection.paymentSettings,
            onTap: () => onSelect(_AdminSection.paymentSettings),
          ),
          _MobileNavChip(
            label: 'Khách hàng',
            selected: false,
            enabled: false,
            onTap: () => onSelect(null),
          ),
        ],
      ),
    );
  }
}

class _MobileNavChip extends StatelessWidget {
  const _MobileNavChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: () {
        onTap();
      },
      backgroundColor:
          selected ? const Color(0xFFFFE4CF) : Colors.white,
      side: BorderSide(
        color: selected
            ? const Color(0xFFE46A11)
            : const Color(0xFFE3EAF2),
      ),
      labelStyle: TextStyle(
        color: enabled ? const Color(0xFF12343B) : const Color(0xFF8A9BAE),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.active = false,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool active;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final background = active
        ? const Color(0xFFE46A11)
        : Colors.white.withValues(alpha: enabled ? 0.06 : 0.03);
    final textColor = enabled ? Colors.white : Colors.white54;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(icon, color: textColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminTopBar extends ConsumerWidget {
  const _AdminTopBar({
    required this.userLabel,
  });

  final String userLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Web quản trị',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: const Color(0xFF12343B),
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Đăng nhập dưới quyền $userLabel',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6B7A90),
                      ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              try {
                await ref.read(authRepositoryProvider).signOut();
              } catch (error) {
                if (!context.mounted) return;
                await showAppNoticeDialog(
                  context,
                  title: 'Không thể đăng xuất',
                  message: 'Đăng xuất chưa hoàn tất.\n$error',
                  isError: true,
                );
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }
}

class _AdminHeroCard extends StatelessWidget {
  const _AdminHeroCard({
    required this.section,
  });

  final _AdminSection section;

  @override
  Widget build(BuildContext context) {
    final title = section == _AdminSection.applications
        ? 'Bảng điều khiển xét duyệt'
        : section == _AdminSection.analytics
            ? 'Bảng điều khiển phân tích'
            : 'Bảng cấu hình thanh toán';
    final body = section == _AdminSection.applications
        ? 'Phiên bản web này tập trung vào thao tác quản trị: xem danh sách hồ sơ, lọc trạng thái, duyệt hoặc từ chối hồ sơ vay.'
        : section == _AdminSection.analytics
            ? 'Theo dõi nhanh số lượng hồ sơ, tình trạng khoản vay và các chỉ số vận hành từ giao diện quản trị web.'
            : 'Thiết lập tập trung tài khoản nhận trả nợ để các khoản vay mới luôn hiển thị đúng thông tin thanh toán.';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF12343B),
            Color(0xFF215861),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.84),
                ),
          ),
        ],
      ),
    );
  }
}

class _AdminSectionTitle extends StatelessWidget {
  const _AdminSectionTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFF12343B),
              ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF6B7A90),
              ),
        ),
      ],
    );
  }
}
