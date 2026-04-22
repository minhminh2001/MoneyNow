import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter/services.dart';

import '../../models/phone_contact.dart';

class ContactSyncResult {
  const ContactSyncResult({
    required this.contacts,
    required this.granted,
    this.errorMessage,
  });

  final List<PhoneContact> contacts;
  final bool granted;
  final String? errorMessage;
}

class ContactSyncService {
  static const int maxContactsToSync = 100;

  Future<ContactSyncResult> requestAndReadContacts({
    void Function(int processed, int total, String message)? onProgress,
  }) async {
    if (!_isSupportedPlatform) {
      return const ContactSyncResult(
        contacts: <PhoneContact>[],
        granted: false,
        errorMessage:
            'Tính năng danh bạ hiện chỉ hỗ trợ trên Android và iPhone.',
      );
    }

    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        return const ContactSyncResult(
          contacts: <PhoneContact>[],
          granted: false,
          errorMessage:
              'Bạn cần cho phép truy cập danh bạ để app đọc và đồng bộ liên hệ.',
        );
      }

      onProgress?.call(0, maxContactsToSync, 'Đang đọc danh sách danh bạ...');
      final lightweightContacts = await FlutterContacts.getContacts(
        sorted: false,
      );
      final selectedContacts = lightweightContacts.take(maxContactsToSync).toList();
      final mappedContacts = <PhoneContact>[];

      for (var index = 0; index < selectedContacts.length; index += 1) {
        final lightweightContact = selectedContacts[index];
        onProgress?.call(
          index,
          selectedContacts.length,
          'Đang xử lý liên hệ ${index + 1}/${selectedContacts.length}...',
        );

        final detailedContact = await FlutterContacts.getContact(
          lightweightContact.id,
          withProperties: true,
          withThumbnail: false,
          withPhoto: false,
        );

        if (detailedContact == null) {
          continue;
        }

        final mappedContact = _mapContact(detailedContact);
        if (mappedContact != null) {
          mappedContacts.add(mappedContact);
        }
      }

      onProgress?.call(
        selectedContacts.length,
        selectedContacts.length,
        'Đã chuẩn bị ${mappedContacts.length} liên hệ để đồng bộ.',
      );

      return ContactSyncResult(
        contacts: mappedContacts,
        granted: true,
      );
    } on MissingPluginException {
      return const ContactSyncResult(
        contacts: <PhoneContact>[],
        granted: false,
        errorMessage:
            'Tính năng danh bạ chưa sẵn sàng trên bản app hiện tại. Hãy tắt hẳn app và chạy lại để nạp plugin danh bạ.',
      );
    } on PlatformException {
      return const ContactSyncResult(
        contacts: <PhoneContact>[],
        granted: false,
        errorMessage:
            'Không thể truy cập danh bạ trên thiết bị này lúc này. Vui lòng kiểm tra quyền truy cập và thử lại.',
      );
    }
  }

  bool get _isSupportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  PhoneContact? _mapContact(Contact contact) {
    final normalizedPhones = contact.phones
        .map((phone) => _normalizePhone(phone.number))
        .where((phone) => phone.isNotEmpty)
        .toSet()
        .toList();

    if (normalizedPhones.isEmpty) {
      return null;
    }

    return PhoneContact(
      id: contact.id,
      displayName: contact.displayName.trim().isEmpty
          ? 'Không có tên'
          : contact.displayName.trim(),
      primaryPhoneMasked: _maskPhone(normalizedPhones.first),
      phoneHashes: normalizedPhones.map(_hashPhone).toList(),
      syncedAt: DateTime.now(),
    );
  }

  String _normalizePhone(String value) {
    return value.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  String _maskPhone(String phone) {
    if (phone.length <= 4) return phone;
    return '***${phone.substring(phone.length - 4)}';
  }

  String _hashPhone(String phone) {
    return sha256.convert(utf8.encode(phone)).toString();
  }
}
