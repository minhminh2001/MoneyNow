import 'package:shared_preferences/shared_preferences.dart';

/// Service quản lý trạng thái đã đọc của thông báo.
/// Dữ liệu được persist bằng SharedPreferences.
class NotificationReadService {
  static const _key = 'read_notification_ids';

  final SharedPreferences _prefs;

  NotificationReadService(this._prefs);

  /// Tập hợp các notification ID đã được đọc.
  Set<String> get readIds {
    final list = _prefs.getStringList(_key) ?? [];
    return list.toSet();
  }

  /// Đánh dấu một notification đã đọc.
  Future<void> markRead(String notificationId) async {
    final current = readIds;
    current.add(notificationId);
    await _prefs.setStringList(_key, current.toList());
  }

  /// Đánh dấu nhiều notifications đã đọc cùng lúc.
  Future<void> markAllRead(Iterable<String> notificationIds) async {
    final current = readIds;
    current.addAll(notificationIds);
    await _prefs.setStringList(_key, current.toList());
  }

  /// Xoá tất cả trạng thái đã đọc (dùng khi sign out).
  Future<void> clearAll() async {
    await _prefs.remove(_key);
  }
}
