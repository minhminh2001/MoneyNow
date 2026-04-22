import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/services/contact_sync_service.dart';
import '../../core/utils/input_formatters.dart';
import '../../core/widgets/app_notice_dialog.dart';
import '../../models/app_user.dart';
import '../../models/phone_contact.dart';
import '../../providers/app_providers.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static final _incomeNumberFormat = NumberFormat('#,###', 'vi_VN');
  final _contactSyncService = ContactSyncService();
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _employerController = TextEditingController();
  final _monthlyIncomeController = TextEditingController();

  bool _loading = false;
  bool _preparingContacts = false;
  bool _backgroundSyncingContacts = false;
  bool _hydrated = false;
  String? _saveStatusText;
  String? _contactsSyncStatusText;
  int _contactsSyncProcessed = 0;
  int _contactsSyncTotal = 0;
  DateTime? _contactsSyncStartedAt;
  bool _submitted = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _nationalIdController.dispose();
    _employerController.dispose();
    _monthlyIncomeController.dispose();
    super.dispose();
  }

  void _hydrate(AppUser? user) {
    if (_hydrated || user == null) return;
    _fullNameController.text = user.fullName;
    _phoneController.text = user.phone;
    _addressController.text = user.address;
    _nationalIdController.text = user.nationalId;
    _employerController.text = user.employer;
    _monthlyIncomeController.text = user.monthlyIncome == 0
        ? ''
        : _incomeNumberFormat.format(user.monthlyIncome.round());
    _hydrated = true;
  }

  Future<void> _save(AppUser? currentProfile) async {
    FocusScope.of(context).unfocus();
    setState(() => _submitted = true);

    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      await showAppNoticeDialog(
        context,
        title: 'Thông tin chưa hợp lệ',
        message: 'Vui lòng kiểm tra lại các trường đang báo lỗi.',
        isError: true,
      );
      return;
    }

    final firebaseUser = ref.read(currentUserProvider);
    if (firebaseUser == null) {
      await showAppNoticeDialog(
        context,
        title: 'Chưa đăng nhập',
        message: 'Không tìm thấy người dùng hiện tại để lưu hồ sơ.',
        isError: true,
      );
      return;
    }

    final monthlyIncome = double.tryParse(
          _monthlyIncomeController.text.trim().replaceAll('.', ''),
        ) ??
        0;

    final updatedUser = AppUser(
      uid: firebaseUser.uid,
      email: firebaseUser.email ?? currentProfile?.email ?? '',
      fullName: _fullNameController.text.trim(),
      phone: _phoneController.text.replaceAll(' ', '').trim(),
      address: _addressController.text.trim(),
      nationalId: _nationalIdController.text.trim(),
      employer: _employerController.text.trim(),
      monthlyIncome: monthlyIncome,
      kycStatus: currentProfile?.kycStatus ?? 'pending',
      contactsSyncCount: currentProfile?.contactsSyncCount ?? 0,
      contactsSyncedAt: currentProfile?.contactsSyncedAt,
      createdAt: currentProfile?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    setState(() {
      _loading = true;
      _saveStatusText = 'Đang lưu hồ sơ...';
    });

    try {
      var saveTimedOut = false;
      final saveFuture =
          ref.read(profileRepositoryProvider).upsertProfile(updatedUser);

      unawaited(
        saveFuture.catchError((_) {
          // The foreground flow below handles visible errors. This prevents
          // an unawaited background completion from surfacing unexpectedly.
        }),
      );

      await saveFuture.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          saveTimedOut = true;
        },
      );

      if (!mounted) return;

      if (saveTimedOut) {
        setState(() {
          _loading = false;
          _saveStatusText = 'Kết nối đang chậm. Hồ sơ sẽ tiếp tục đồng bộ nền...';
        });
        await showAppNoticeDialog(
          context,
          title: 'Đang đồng bộ nền',
          message:
              'Mạng đang phản hồi chậm nên app chưa xác nhận xong với Firestore. '
              'Thay đổi của bạn vẫn đang tiếp tục đồng bộ nền.',
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }

      setState(() => _saveStatusText = 'Đã lưu hồ sơ thành công.');
      await showAppNoticeDialog(
        context,
        title: 'Lưu thành công',
        message: 'Đã lưu hồ sơ thành công.',
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saveStatusText = 'Lưu hồ sơ thất bại.');
      await showAppNoticeDialog(
        context,
        title: 'Lưu thất bại',
        message:
            'Không thể lưu hồ sơ lúc này. Vui lòng kiểm tra mạng và thử lại.\n\nChi tiết: $error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _startContactsSync() {
    final firebaseUser = ref.read(currentUserProvider);
    if (firebaseUser == null || _preparingContacts || _backgroundSyncingContacts) {
      return;
    }

    setState(() {
      _contactsSyncStartedAt = DateTime.now();
      _preparingContacts = true;
      _backgroundSyncingContacts = false;
      _contactsSyncProcessed = 0;
      _contactsSyncTotal = ContactSyncService.maxContactsToSync;
      _contactsSyncStatusText = 'Bắt đầu đồng bộ tối đa 100 liên hệ...';
    });
    unawaited(_syncContacts(firebaseUser.uid));
  }

  Future<void> _syncContacts(String uid) async {
    try {
      final result = await _contactSyncService.requestAndReadContacts(
        onProgress: (processed, total, message) {
          if (!mounted) return;
          setState(() {
            _contactsSyncProcessed = processed;
            _contactsSyncTotal = total;
            _contactsSyncStatusText = message;
          });
        },
      );
      if (!result.granted) {
        if (!mounted) return;
        setState(() {
          _contactsSyncStatusText = result.errorMessage ??
              'Bạn cần cho phép truy cập danh bạ để hoàn tất điều kiện xét duyệt hồ sơ vay.';
        });
        return;
      }

      if (result.contacts.isEmpty) {
        if (!mounted) return;
        setState(() {
          _contactsSyncStatusText =
              'Không tìm thấy liên hệ nào có số điện thoại trong 100 liên hệ đầu tiên.';
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _preparingContacts = false;
        _backgroundSyncingContacts = true;
        _contactsSyncProcessed = 0;
        _contactsSyncTotal = result.contacts.length;
        _contactsSyncStatusText =
            'Đã chuẩn bị ${result.contacts.length} liên hệ. Đang đồng bộ nền...';
      });
      unawaited(_saveContactsInBackground(uid, result.contacts));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _contactsSyncStatusText = 'Không thể đọc hoặc lưu danh bạ: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _preparingContacts = false);
      }
    }
  }

  Future<void> _saveContactsInBackground(
    String uid,
    List<PhoneContact> contacts,
  ) async {
    try {
      await ref.read(profileRepositoryProvider).savePhoneContacts(
        uid: uid,
        contacts: contacts,
        onProgress: (processed, total, message) {
          if (!mounted) return;
          setState(() {
            _contactsSyncProcessed = processed;
            _contactsSyncTotal = total;
            _contactsSyncStatusText = message;
          });
        },
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _contactsSyncStatusText = 'Đồng bộ nền thất bại: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _backgroundSyncingContacts = false);
      }
    }
  }

  void _maybeFinalizeContactsSync(AppUser? profile) {
    if (!_backgroundSyncingContacts || profile == null) return;
    final syncedAt = profile.contactsSyncedAt;
    final startedAt = _contactsSyncStartedAt;
    if (syncedAt == null || startedAt == null || !profile.hasSyncedContacts) {
      return;
    }
    if (syncedAt.isBefore(startedAt.subtract(const Duration(seconds: 1)))) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_backgroundSyncingContacts) return;
      setState(() {
        _backgroundSyncingContacts = false;
        _contactsSyncProcessed = profile.contactsSyncCount;
        _contactsSyncTotal = profile.contactsSyncCount;
        _contactsSyncStatusText =
            'Đã đồng bộ ${profile.contactsSyncCount} liên hệ thành công.';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);
    final currentProfile = profileAsync.value;

    _hydrate(currentProfile);
    _maybeFinalizeContactsSync(currentProfile);

    return Scaffold(
      appBar: AppBar(title: const Text('Cập nhật hồ sơ')),
      body: profileAsync.when(
        data: (_) {
          return Form(
            key: _formKey,
            autovalidateMode: _submitted
                ? AutovalidateMode.onUserInteraction
                : AutovalidateMode.disabled,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_saveStatusText != null) ...[
                  Card(
                    color: _loading
                        ? const Color(0xFFFFF7E8)
                        : const Color(0xFFFFF3E7),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _saveStatusText!,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          if (_loading) ...[
                            const SizedBox(height: 10),
                            const LinearProgressIndicator(minHeight: 8),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _fullNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Họ và tên *'),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Vui lòng nhập họ và tên';
                    }
                    if ((value ?? '').trim().length < 2) {
                      return 'Họ và tên quá ngắn';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                    VietnamesePhoneInputFormatter(),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại *',
                    hintText: '090 123 4567',
                  ),
                  validator: (value) {
                    final text = (value ?? '').replaceAll(' ', '').trim();
                    if (text.isEmpty) {
                      return 'Vui lòng nhập số điện thoại';
                    }
                    if (!RegExp(r'^(03|05|07|08|09)\d{8}$').hasMatch(text)) {
                      return 'SĐT phải là số di động Việt Nam hợp lệ';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  maxLines: 3,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(labelText: 'Địa chỉ *'),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Vui lòng nhập địa chỉ';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _nationalIdController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(12),
                  ],
                  decoration: const InputDecoration(labelText: 'Số CCCD *'),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) {
                      return 'Vui lòng nhập số CCCD';
                    }
                    if (!RegExp(r'^\d{12}$').hasMatch(text)) {
                      return 'CCCD phải đúng 12 số';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _employerController,
                  textInputAction: TextInputAction.next,
                  decoration:
                      const InputDecoration(labelText: 'Nơi làm việc *'),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) {
                      return 'Vui lòng nhập nơi làm việc';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _monthlyIncomeController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(12),
                    CurrencyTextInputFormatter(),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Thu nhập hằng tháng (VND) *',
                    helperText: 'Thu nhập tối thiểu: 1.000.000 VND',
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) {
                      return 'Vui lòng nhập thu nhập';
                    }
                    final income = double.tryParse(text.replaceAll('.', ''));
                    if (income == null) {
                      return 'Thu nhập không hợp lệ';
                    }
                    if (income < 1000000) {
                      return 'Thu nhập phải lớn hơn hoặc bằng 1.000.000 VND';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Card(
                  color: const Color(0xFFFFF3E7),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Danh bạ điện thoại',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Cho phép Money Now đọc danh bạ để lấy số điện thoại liên hệ và lưu lại phục vụ đánh giá hồ sơ. Đồng bộ danh bạ là yêu cầu bắt buộc để được duyệt vay.',
                        ),
                        const SizedBox(height: 10),
                        Text(
                          (_preparingContacts || _backgroundSyncingContacts)
                              ? 'Đang xử lý đồng bộ danh bạ. Bạn vẫn có thể tiếp tục thao tác trong app.'
                              : currentProfile?.hasSyncedContacts == true
                              ? 'Đã đồng bộ ${currentProfile!.contactsSyncCount} liên hệ'
                              : 'Chưa đồng bộ danh bạ. Hồ sơ sẽ chưa đủ điều kiện duyệt vay.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        if (_contactsSyncStatusText != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _contactsSyncStatusText!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                        if (_preparingContacts || _backgroundSyncingContacts) ...[
                          const SizedBox(height: 10),
                          LinearProgressIndicator(
                            value: _backgroundSyncingContacts
                                ? null
                                : _contactsSyncTotal > 0
                                ? (_contactsSyncProcessed / _contactsSyncTotal)
                                    .clamp(0, 1)
                                : null,
                            borderRadius: BorderRadius.circular(999),
                            minHeight: 8,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _backgroundSyncingContacts
                                ? 'Đang ghi dữ liệu nền lên hệ thống...'
                                : 'Tiến độ: $_contactsSyncProcessed/${_contactsSyncTotal == 0 ? ContactSyncService.maxContactsToSync : _contactsSyncTotal} liên hệ',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed:
                              (_preparingContacts || _backgroundSyncingContacts)
                                  ? null
                                  : _startContactsSync,
                          child: Text(
                            _preparingContacts
                                ? 'Đang chuẩn bị danh bạ...'
                                : _backgroundSyncingContacts
                                    ? 'Đang đồng bộ nền...'
                                : 'Cho phép và đồng bộ danh bạ',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : () => _save(currentProfile),
                  child: Text(_loading ? 'Đang lưu...' : 'Lưu hồ sơ'),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Không tải được hồ sơ: $error'),
          ),
        ),
      ),
    );
  }
}
