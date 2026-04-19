import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/notification_read_service.dart';
import '../models/app_notification.dart';
import '../models/app_user.dart';
import '../models/loan.dart';
import '../models/loan_application.dart';
import '../models/loan_draft.dart';
import '../models/repayment.dart';
import '../models/uploaded_document.dart';
import '../repositories/auth_repository.dart';
import '../repositories/loan_repository.dart';
import '../repositories/profile_repository.dart';
import '../repositories/storage_repository.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final storageProvider = Provider<FirebaseStorage>((ref) {
  return FirebaseStorage.instance;
});

final functionsProvider = Provider<FirebaseFunctions>((ref) {
  return FirebaseFunctions.instanceFor(region: 'asia-southeast1');
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(firebaseAuthProvider));
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(firestoreProvider));
});

final storageRepositoryProvider = Provider<StorageRepository>((ref) {
  return StorageRepository(
    ref.watch(storageProvider),
    ref.watch(firebaseAuthProvider),
  );
});

final loanRepositoryProvider = Provider<LoanRepository>((ref) {
  return LoanRepository(
    firestore: ref.watch(firestoreProvider),
    functions: ref.watch(functionsProvider),
  );
});

final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateChangesProvider).value;
});

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(currentUserProvider)?.uid;
});

final userProfileProvider = StreamProvider.autoDispose<AppUser?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return Stream<AppUser?>.value(null);
  }
  return ref
      .watch(profileRepositoryProvider)
      .streamProfile(uid: user.uid, email: user.email ?? '')
      .map((profile) => profile);
});

final userDocumentsProvider =
    StreamProvider.autoDispose<List<UploadedDocument>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream<List<UploadedDocument>>.value(const []);
  }
  return ref.watch(profileRepositoryProvider).streamDocuments(uid);
});

final loanDraftProvider = StreamProvider.autoDispose<LoanDraft>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream<LoanDraft>.value(LoanDraft.empty());
  }
  return ref.watch(profileRepositoryProvider).streamLoanDraft(uid);
});

final loanApplicationsProvider =
    StreamProvider.autoDispose<List<LoanApplication>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream<List<LoanApplication>>.value(const []);
  }
  return ref.watch(loanRepositoryProvider).streamApplications(uid);
});

final loansProvider = StreamProvider.autoDispose<List<Loan>>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) {
    return Stream<List<Loan>>.value(const []);
  }
  return ref.watch(loanRepositoryProvider).streamLoans(uid);
});

final repaymentScheduleProvider =
    StreamProvider.autoDispose.family<List<Repayment>, String>((ref, loanId) {
  return ref.watch(loanRepositoryProvider).streamRepaymentSchedule(loanId);
});

// ─── Notification Providers ───────────────────────────────────────────────────

/// SharedPreferences instance — khởi tạo một lần và cache.
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

/// Service quản lý trạng thái đã đọc (persist bằng SharedPreferences).
final notificationReadServiceProvider =
    Provider<NotificationReadService?>((ref) {
  return ref.watch(sharedPreferencesProvider).whenOrNull(
        data: (prefs) => NotificationReadService(prefs),
      );
});

/// Tập hợp các notification ID đã đọc — dùng Notifier để rebuild UI khi
/// người dùng mark-as-read mà không cần reload từ disk.
class ReadNotificationIdsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    final service = ref.watch(notificationReadServiceProvider);
    return service?.readIds ?? {};
  }

  void markRead(String id) {
    state = {...state, id};
  }

  void markAllRead(Iterable<String> ids) {
    state = {...state, ...ids};
  }
}

final readNotificationIdsProvider =
    NotifierProvider<ReadNotificationIdsNotifier, Set<String>>(
  ReadNotificationIdsNotifier.new,
);

/// Danh sách thông báo tổng hợp, sinh client-side từ dữ liệu Firestore sẵn có.
/// Không cần collection mới — dữ liệu đến từ loans, repaymentSchedules,
/// loanApplications đã stream.
final notificationsProvider = Provider.autoDispose<List<AppNotification>>(
  (ref) {
    final now = DateTime.now();
    const dueSoonDays = 3; // ngưỡng nhắc nhở trước hạn
    final notifications = <AppNotification>[];

    // ── 1. Thông báo từ lịch thanh toán ──────────────────────────────────────
    final loansAsync = ref.watch(loansProvider);
    final loans = loansAsync.value ?? [];

    for (final loan in loans) {
      if (loan.status == 'closed') continue;
      final scheduleAsync = ref.watch(repaymentScheduleProvider(loan.id));
      final schedules = scheduleAsync.value ?? [];

      for (final repayment in schedules) {
        final dueDate = repayment.dueDate;
        if (dueDate == null) continue;
        if (repayment.status == 'paid') continue;

        final isOverdue = dueDate.isBefore(now);
        final isDueSoon = !isOverdue &&
            dueDate.difference(now).inDays <= dueSoonDays;

        if (isOverdue || repayment.status == 'overdue') {
          notifications.add(AppNotification(
            id: 'overdue_${loan.id}_${repayment.id}',
            type: AppNotificationType.repaymentOverdue,
            title: 'Kỳ #${repayment.installmentNo} đã quá hạn!',
            body:
                'Hạn thanh toán ${_fmtDate(dueDate)} đã qua. Vui lòng thanh toán sớm.',
            timestamp: dueDate,
            routeId: loan.id,
          ));
        } else if (isDueSoon) {
          final daysLeft = dueDate.difference(now).inDays;
          final dayText = daysLeft == 0 ? 'hôm nay' : 'trong $daysLeft ngày';
          notifications.add(AppNotification(
            id: 'due_${loan.id}_${repayment.id}',
            type: AppNotificationType.repaymentDue,
            title: 'Kỳ #${repayment.installmentNo} sắp đến hạn',
            body: 'Hạn thanh toán ${_fmtDate(dueDate)} ($dayText).',
            timestamp: dueDate,
            routeId: loan.id,
          ));
        }
      }
    }

    // ── 2. Thông báo từ hồ sơ vay ────────────────────────────────────────────
    final applicationsAsync = ref.watch(loanApplicationsProvider);
    final applications = applicationsAsync.value ?? [];

    for (final app in applications) {
      final ts = app.updatedAt ?? app.createdAt ?? now;
      switch (app.status) {
        case 'approved':
          notifications.add(AppNotification(
            id: 'app_approved_${app.id}',
            type: AppNotificationType.applicationApproved,
            title: 'Hồ sơ vay được duyệt!',
            body: 'Hồ sơ vay của bạn đã được phê duyệt. Kiểm tra khoản vay ngay.',
            timestamp: ts,
            routeId: app.id,
          ));
        case 'rejected':
          notifications.add(AppNotification(
            id: 'app_rejected_${app.id}',
            type: AppNotificationType.applicationRejected,
            title: 'Hồ sơ vay bị từ chối',
            body: app.decisionReason.isNotEmpty
                ? app.decisionReason
                : 'Hồ sơ vay không đáp ứng điều kiện. Vui lòng kiểm tra lại.',
            timestamp: ts,
            routeId: app.id,
          ));
        case 'reviewing':
          notifications.add(AppNotification(
            id: 'app_reviewing_${app.id}',
            type: AppNotificationType.applicationReviewing,
            title: 'Hồ sơ đang thẩm định',
            body: 'Hồ sơ vay đang được xem xét thủ công. Chúng tôi sẽ phản hồi sớm.',
            timestamp: ts,
            routeId: app.id,
          ));
      }
    }

    // Sắp xếp: mới nhất lên đầu, overdue ưu tiên
    notifications.sort((a, b) {
      // Overdue/rejected lên trên cùng
      if (a.isUrgent && !b.isUrgent) return -1;
      if (!a.isUrgent && b.isUrgent) return 1;
      return b.timestamp.compareTo(a.timestamp);
    });

    return notifications;
  },
);

/// Số thông báo chưa đọc — dùng để hiển thị badge trên AppBar.
final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final notifications = ref.watch(notificationsProvider);
  final readIds = ref.watch(readNotificationIdsProvider);
  return notifications.where((n) => !readIds.contains(n.id)).length;
});

String _fmtDate(DateTime dt) =>
    '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
