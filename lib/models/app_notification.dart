import 'package:flutter/foundation.dart';

enum AppNotificationType {
  repaymentDue,
  repaymentOverdue,
  applicationApproved,
  applicationRejected,
  applicationReviewing,
}

@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    this.routeId,
  });

  /// ID duy nhất — dùng để track trạng thái đã đọc và làm widget key.
  /// Format: "type_entityId" để đảm bảo idempotent khi data cập nhật.
  final String id;
  final AppNotificationType type;
  final String title;
  final String body;

  /// Dùng để sort (mới nhất lên đầu).
  final DateTime timestamp;

  /// loanId hoặc applicationId để navigate khi tap.
  final String? routeId;

  bool get isRepayment =>
      type == AppNotificationType.repaymentDue ||
      type == AppNotificationType.repaymentOverdue;

  bool get isUrgent =>
      type == AppNotificationType.repaymentOverdue ||
      type == AppNotificationType.applicationRejected;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppNotification &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
