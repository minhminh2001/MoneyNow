import '../core/utils/firestore_value.dart';

class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.role,
    required this.insuranceNumber,
    required this.fullName,
    required this.phone,
    required this.address,
    required this.nationalId,
    required this.employer,
    required this.monthlyIncome,
    required this.payoutAccountHolder,
    required this.payoutBankName,
    required this.payoutAccountNumber,
    required this.repaymentAccountHolder,
    required this.repaymentBankName,
    required this.repaymentAccountNumber,
    required this.kycStatus,
    required this.contactsSyncCount,
    required this.contactsSyncedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String uid;
  final String email;
  final String role;
  final String insuranceNumber;
  final String fullName;
  final String phone;
  final String address;
  final String nationalId;
  final String employer;
  final double monthlyIncome;
  final String payoutAccountHolder;
  final String payoutBankName;
  final String payoutAccountNumber;
  final String repaymentAccountHolder;
  final String repaymentBankName;
  final String repaymentAccountNumber;
  final String kycStatus;
  final int contactsSyncCount;
  final DateTime? contactsSyncedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory AppUser.empty({
    required String uid,
    required String email,
  }) {
    return AppUser(
      uid: uid,
      email: email,
      role: 'user',
      insuranceNumber: '',
      fullName: '',
      phone: '',
      address: '',
      nationalId: '',
      employer: '',
      monthlyIncome: 0,
      payoutAccountHolder: '',
      payoutBankName: '',
      payoutAccountNumber: '',
      repaymentAccountHolder: '',
      repaymentBankName: '',
      repaymentAccountNumber: '',
      kycStatus: 'pending',
      contactsSyncCount: 0,
      contactsSyncedAt: null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    final rawContactsSync = map['contactsSync'];
    final contactsSync = rawContactsSync is Map<String, dynamic>
        ? rawContactsSync
        : rawContactsSync is Map
            ? Map<String, dynamic>.from(rawContactsSync)
            : const <String, dynamic>{};

    return AppUser(
      uid: uid,
      email: readString(map['email']),
      role: readString(map['role']).trim().isEmpty
          ? 'user'
          : readString(map['role']).trim(),
      insuranceNumber: readString(map['insuranceNumber']),
      fullName: readString(map['fullName']),
      phone: readString(map['phone']),
      address: readString(map['address']),
      nationalId: readString(map['nationalId']),
      employer: readString(map['employer']),
      monthlyIncome: readDouble(map['monthlyIncome']),
      payoutAccountHolder: readString(map['payoutAccountHolder']),
      payoutBankName: readString(map['payoutBankName']),
      payoutAccountNumber: readString(map['payoutAccountNumber']),
      repaymentAccountHolder: readString(map['repaymentAccountHolder']),
      repaymentBankName: readString(map['repaymentBankName']),
      repaymentAccountNumber: readString(map['repaymentAccountNumber']),
      kycStatus: readString(map['kycStatus']).isEmpty
          ? 'pending'
          : readString(map['kycStatus']),
      contactsSyncCount: readInt(contactsSync['count']),
      contactsSyncedAt: readDateTime(contactsSync['updatedAt']),
      createdAt: readDateTime(map['createdAt']),
      updatedAt: readDateTime(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'role': role,
      'insuranceNumber': insuranceNumber,
      'fullName': fullName,
      'phone': phone,
      'address': address,
      'nationalId': nationalId,
      'employer': employer,
      'monthlyIncome': monthlyIncome,
      'payoutAccountHolder': payoutAccountHolder,
      'payoutBankName': payoutBankName,
      'payoutAccountNumber': payoutAccountNumber,
      'repaymentAccountHolder': repaymentAccountHolder,
      'repaymentBankName': repaymentBankName,
      'repaymentAccountNumber': repaymentAccountNumber,
      'kycStatus': kycStatus,
      'contactsSync': {
        'count': contactsSyncCount,
        'updatedAt': contactsSyncedAt,
      },
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  bool get isProfileComplete =>
      fullName.isNotEmpty &&
      phone.isNotEmpty &&
      address.isNotEmpty &&
      nationalId.isNotEmpty;

  bool get hasSyncedContacts => contactsSyncCount > 0;

  bool get isAdmin => role.trim().toLowerCase() == 'admin';

  bool get isLightVerificationComplete =>
      isProfileComplete && hasSyncedContacts;
}
