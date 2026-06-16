import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_notice_dialog.dart';
import '../../providers/app_providers.dart';
import '../../repositories/auth_repository.dart';

class AdminWebLoginScreen extends ConsumerStatefulWidget {
  const AdminWebLoginScreen({super.key});

  @override
  ConsumerState<AdminWebLoginScreen> createState() =>
      _AdminWebLoginScreenState();
}

class _AdminWebLoginScreenState extends ConsumerState<AdminWebLoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final normalizedPhone = _normalizeVietnamPhone(_phoneController.text);
    final password = _passwordController.text.trim();

    if (normalizedPhone == null) {
      await showAppNoticeDialog(
        context,
        title: 'Số điện thoại chưa đúng',
        message:
            'Hãy nhập số điện thoại Việt Nam không gồm số 0 đầu tiên. Ví dụ: 912345678 với đầu số mặc định +84.',
        isError: true,
      );
      return;
    }

    if (password.isEmpty) {
      await showAppNoticeDialog(
        context,
        title: 'Thiếu mật khẩu',
        message: 'Vui lòng nhập mật khẩu để đăng nhập quản trị.',
        isError: true,
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final authRepository = ref.read(authRepositoryProvider);
      final credential = await authRepository.signInWithPhoneAndPassword(
        phoneNumber: normalizedPhone,
        password: password,
      );

      final user = credential.user;
      if (user != null) {
        await ref.read(profileRepositoryProvider).ensureUserProfile(
              uid: user.uid,
              email: user.email ??
                  authRepository.credentialEmailForPhone(normalizedPhone),
            );
      }
    } catch (error) {
      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Đăng nhập quản trị thất bại',
        message: translateAuthError(error),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String? _normalizeVietnamPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return null;

    if (digits.startsWith('84')) {
      final local = digits.substring(2);
      return RegExp(r'^\d{9,10}$').hasMatch(local) ? '+84$local' : null;
    }

    if (digits.startsWith('0')) {
      final local = digits.substring(1);
      return RegExp(r'^\d{9,10}$').hasMatch(local) ? '+84$local' : null;
    }

    return RegExp(r'^\d{9,10}$').hasMatch(digits) ? '+84$digits' : null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF102F35),
              Color(0xFF173E45),
              Color(0xFFF2F6FB),
            ],
            stops: [0, 0.42, 1],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  return Row(
                    children: [
                      if (wide)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 28),
                            child: _AdminLoginIntro(
                              colorScheme: colorScheme,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    Colors.black.withValues(alpha: 0.08),
                                blurRadius: 36,
                                offset: const Offset(0, 20),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!wide)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  child: Text(
                                    'Money Now Admin',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(
                                          color: const Color(0xFF12343B),
                                        ),
                                  ),
                                ),
                              Text(
                                'Đăng nhập quản trị',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                      color: const Color(0xFF12343B),
                                    ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Bản web này tách riêng khỏi luồng mobile app. Hãy đăng nhập bằng số điện thoại và mật khẩu của tài khoản quản trị.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      color: const Color(0xFF5B6B7E),
                                    ),
                              ),
                              const SizedBox(height: 24),
                              TextField(
                                controller: _phoneController,
                                enabled: !_loading,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Số điện thoại quản trị',
                                  hintText: '912345678',
                                  prefixText: '+84 ',
                                  prefixIcon: Icon(Icons.phone_rounded),
                                  helperText:
                                      'Nhập số điện thoại không gồm số 0 đầu tiên.',
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextField(
                                controller: _passwordController,
                                enabled: !_loading,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Mật khẩu',
                                  hintText: 'Nhập mật khẩu',
                                  prefixIcon: Icon(Icons.lock_outline_rounded),
                                ),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _loading ? null : _submit,
                                  icon: const Icon(Icons.login_rounded),
                                  label: Text(
                                    _loading
                                        ? 'Đang đăng nhập...'
                                        : 'Vào trang quản trị',
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Lưu ý: giao diện web đã tách riêng, nhưng thao tác duyệt hồ sơ vẫn được backend kiểm tra quyền admin.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: const Color(0xFF6B7A90),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminLoginIntro extends StatelessWidget {
  const _AdminLoginIntro({
    required this.colorScheme,
  });

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.admin_panel_settings_outlined,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Money Now Admin',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'Không còn đi qua luồng đăng nhập của khách hàng. Đây là điểm vào riêng cho web quản trị để xem hồ sơ, lọc, duyệt và theo dõi dữ liệu vận hành.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white.withValues(alpha: 0.84),
                ),
          ),
        ],
      ),
    );
  }
}
