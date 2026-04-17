import '../core/utils/firestore_value.dart';

class PhoneContact {
  const PhoneContact({
    required this.id,
    required this.displayName,
    required this.primaryPhoneMasked,
    required this.phoneHashes,
    required this.syncedAt,
  });

  final String id;
  final String displayName;
  final String primaryPhoneMasked;
  final List<String> phoneHashes;
  final DateTime? syncedAt;

  factory PhoneContact.fromMap(String id, Map<String, dynamic> map) {
    final rawPhoneHashes = map['phoneHashes'];
    final phoneHashes = rawPhoneHashes is Iterable
        ? rawPhoneHashes
            .map((item) => readString(item))
            .where((item) => item.isNotEmpty)
            .toList()
        : <String>[];

    return PhoneContact(
      id: id,
      displayName: readString(map['displayName']),
      primaryPhoneMasked: readString(map['primaryPhoneMasked']),
      phoneHashes: phoneHashes,
      syncedAt: readDateTime(map['syncedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'primaryPhoneMasked': primaryPhoneMasked,
      'phoneHashes': phoneHashes,
      'syncedAt': syncedAt ?? DateTime.now(),
    };
  }
}
