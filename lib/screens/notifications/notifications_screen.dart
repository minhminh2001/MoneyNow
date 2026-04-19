import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../models/app_notification.dart';
import '../../models/loan.dart';
import '../../models/loan_application.dart';
import '../../providers/app_providers.dart';
import '../application/application_detail_screen.dart';
import '../loan/loan_detail_screen.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final readIds = ref.watch(readNotificationIdsProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);

    // Phân nhóm: hôm nay vs trước đó
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayItems = notifications
        .where((n) => !n.timestamp.isBefore(today))
        .toList();
    final earlierItems = notifications
        .where((n) => n.timestamp.isBefore(today))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Thông báo'),
            if (unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFE46A11),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: () => _markAllRead(ref, notifications),
              child: const Text('Đọc tất cả'),
            ),
        ],
      ),
      body: notifications.isEmpty
          ? _EmptyState()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (todayItems.isNotEmpty) ...[
                  _SectionHeader(label: 'Hôm nay'),
                  const SizedBox(height: 8),
                  ...todayItems.map(
                    (n) => _NotificationTile(
                      notification: n,
                      isRead: readIds.contains(n.id),
                      onTap: () => _onTap(context, ref, n),
                    ),
                  ),
                ],
                if (earlierItems.isNotEmpty) ...[
                  if (todayItems.isNotEmpty) const SizedBox(height: 12),
                  _SectionHeader(label: 'Trước đó'),
                  const SizedBox(height: 8),
                  ...earlierItems.map(
                    (n) => _NotificationTile(
                      notification: n,
                      isRead: readIds.contains(n.id),
                      onTap: () => _onTap(context, ref, n),
                    ),
                  ),
                ],
                // Nếu tất cả đều hôm nay nhưng không có "trước đó" cũng OK
                if (todayItems.isEmpty && earlierItems.isEmpty)
                  _EmptyState(),
              ],
            ),
    );
  }

  Future<void> _markAllRead(
      WidgetRef ref, List<AppNotification> notifications) async {
    final service = ref.read(notificationReadServiceProvider);
    final ids = notifications.map((n) => n.id).toSet();
    await service?.markAllRead(ids);
    ref.read(readNotificationIdsProvider.notifier).markAllRead(ids);
  }

  Future<void> _onTap(
    BuildContext context,
    WidgetRef ref,
    AppNotification notification,
  ) async {
    HapticFeedback.selectionClick();

    // Đánh dấu đã đọc
    final service = ref.read(notificationReadServiceProvider);
    await service?.markRead(notification.id);
    ref.read(readNotificationIdsProvider.notifier).markRead(notification.id);

    if (!context.mounted) return;

    // Navigate đến màn hình liên quan
    if (notification.routeId == null) return;

    if (notification.isRepayment) {
      // Tìm loan trong danh sách đã watch
      final loans = ref.read(loansProvider).value ?? [];
      final loan = loans.cast<Loan?>().firstWhere(
            (l) => l?.id == notification.routeId,
            orElse: () => null,
          );
      if (loan != null && context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => LoanDetailScreen(loan: loan)),
        );
      }
    } else {
      // Hồ sơ vay
      final applications = ref.read(loanApplicationsProvider).value ?? [];
      final app = applications.cast<LoanApplication?>().firstWhere(
            (a) => a?.id == notification.routeId,
            orElse: () => null,
          );
      if (app != null && context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => ApplicationDetailScreen(application: app)),
        );
      }
    }
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF8A9BAE),
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.isRead,
    required this.onTap,
  });

  final AppNotification notification;
  final bool isRead;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final config = _NotificationConfig.from(notification.type);

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: isRead ? 0.55 : 1.0,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          elevation: 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isRead
                      ? const Color(0xFFECF0F5)
                      : config.borderColor,
                  width: isRead ? 1 : 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon container
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: config.iconBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        config.icon,
                        color: config.iconColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Nội dung
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  notification.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        color: isRead
                                            ? const Color(0xFF8A9BAE)
                                            : const Color(0xFF12343B),
                                        fontSize: 14,
                                      ),
                                ),
                              ),
                              // Unread dot
                              if (!isRead)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(left: 8, top: 4),
                                  decoration: BoxDecoration(
                                    color: config.iconColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            notification.body,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: const Color(0xFF617487),
                                  height: 1.4,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              // Badge type
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: config.iconBg,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  config.badge,
                                  style: TextStyle(
                                    color: config.iconColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              // Timestamp
                              Text(
                                AppFormatters.date(notification.timestamp),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: const Color(0xFFAABBC8),
                                      fontSize: 11,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.85, end: 1),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutBack,
              builder: (_, value, child) =>
                  Transform.scale(scale: value, child: child),
              child: Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF0E4), Color(0xFFFFE7D2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(
                  Icons.notifications_none_rounded,
                  size: 44,
                  color: Color(0xFFE46A11),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Không có thông báo',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: const Color(0xFF12343B),
                  ),
            ),
            const SizedBox(height: 10),
            Text(
              'Các nhắc nhở trả nợ và cập nhật hồ sơ vay sẽ xuất hiện ở đây.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF8A9BAE),
                    height: 1.5,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Config helper ────────────────────────────────────────────────────────────

class _NotificationConfig {
  const _NotificationConfig({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.borderColor,
    required this.badge,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color borderColor;
  final String badge;

  factory _NotificationConfig.from(AppNotificationType type) {
    switch (type) {
      case AppNotificationType.repaymentOverdue:
        return const _NotificationConfig(
          icon: Icons.error_outline_rounded,
          iconColor: Color(0xFFD32F2F),
          iconBg: Color(0xFFFFEBEB),
          borderColor: Color(0xFFFFCDD2),
          badge: 'Quá hạn',
        );
      case AppNotificationType.repaymentDue:
        return const _NotificationConfig(
          icon: Icons.schedule_rounded,
          iconColor: Color(0xFFE46A11),
          iconBg: Color(0xFFFFF0E4),
          borderColor: Color(0xFFFFD9B8),
          badge: 'Sắp đến hạn',
        );
      case AppNotificationType.applicationApproved:
        return const _NotificationConfig(
          icon: Icons.check_circle_outline_rounded,
          iconColor: Color(0xFF2E7D32),
          iconBg: Color(0xFFE8F5E9),
          borderColor: Color(0xFFC8E6C9),
          badge: 'Được duyệt',
        );
      case AppNotificationType.applicationRejected:
        return const _NotificationConfig(
          icon: Icons.cancel_outlined,
          iconColor: Color(0xFFB71C1C),
          iconBg: Color(0xFFFFEBEB),
          borderColor: Color(0xFFFFCDD2),
          badge: 'Từ chối',
        );
      case AppNotificationType.applicationReviewing:
        return const _NotificationConfig(
          icon: Icons.hourglass_empty_rounded,
          iconColor: Color(0xFF1565C0),
          iconBg: Color(0xFFE3F2FD),
          borderColor: Color(0xFFBBDEFB),
          badge: 'Đang thẩm định',
        );
    }
  }
}
