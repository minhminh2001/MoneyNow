import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_notice_dialog.dart';
import '../../providers/app_providers.dart';
import '../../repositories/auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    this.registrationPending = false,
    this.initialPhoneNumber,
  });

  final bool registrationPending;
  final String? initialPhoneNumber;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _otpController = TextEditingController();

  bool _registerMode = false;
  bool _loading = false;
  bool _otpRequested = false;
  bool _passwordSetupReady = false;
  String? _verificationId;
  int? _resendToken;
  String _normalizedPhone = '';

  @override
  void initState() {
    super.initState();
    if (widget.registrationPending) {
      _registerMode = true;
      _passwordSetupReady = true;
      _normalizedPhone = widget.initialPhoneNumber ?? '';
      _phoneController.text = _localPhoneInputFor(widget.initialPhoneNumber);
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (_registerMode) {
      if (_passwordSetupReady) {
        await _completeRegistration();
      } else if (_otpRequested) {
        await _verifyRegisterOtp();
      } else {
        await _requestRegisterOtp();
      }
      return;
    }

    await _signInWithPassword();
  }

  Future<void> _requestRegisterOtp({bool resend = false}) async {
    final normalizedPhone = _normalizeVietnamPhone(_phoneController.text);
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

    setState(() => _loading = true);

    try {
      final authRepository = ref.read(authRepositoryProvider);
      final result = await authRepository.requestPhoneOtp(
        phoneNumber: normalizedPhone,
        forceResendingToken: resend ? _resendToken : null,
      );

      if (result.isAutoVerified) {
        await _moveToPasswordSetup(
          result.autoVerifiedCredential!,
          normalizedPhone: normalizedPhone,
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _normalizedPhone = normalizedPhone;
        _verificationId = result.verificationId;
        _resendToken = result.resendToken;
        _otpRequested = true;
      });

      await showAppNoticeDialog(
        context,
        title: 'Mã OTP đã được gửi',
        message:
            'Nhập mã OTP đã gửi tới ${_prettyPhone(normalizedPhone)} để tiếp tục tạo mật khẩu.',
      );
    } catch (error) {
      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Không thể gửi OTP đăng ký',
        message: translateAuthError(error),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _verifyRegisterOtp() async {
    final verificationId = _verificationId;
    final smsCode = _otpController.text.trim();

    if (verificationId == null || verificationId.isEmpty) {
      await showAppNoticeDialog(
        context,
        title: 'Phiên OTP không còn hợp lệ',
        message: 'Vui lòng yêu cầu gửi lại mã rồi thử lại.',
        isError: true,
      );
      return;
    }

    if (!RegExp(r'^\d{6}$').hasMatch(smsCode)) {
      await showAppNoticeDialog(
        context,
        title: 'Mã OTP chưa đúng',
        message: 'Mã xác thực phải gồm đúng 6 chữ số.',
        isError: true,
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final credential = await ref
          .read(authRepositoryProvider)
          .verifyPhoneOtp(verificationId: verificationId, smsCode: smsCode);
      await _moveToPasswordSetup(credential, normalizedPhone: _normalizedPhone);
    } catch (error) {
      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Xác thực OTP thất bại',
        message: translateAuthError(error),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _moveToPasswordSetup(
    UserCredential credential, {
    required String normalizedPhone,
  }) async {
    if (credential.user == null || !mounted) return;

    setState(() {
      _normalizedPhone = normalizedPhone;
      _otpRequested = false;
      _passwordSetupReady = true;
      _verificationId = null;
      _resendToken = null;
      _otpController.clear();
    });
  }

  Future<void> _completeRegistration() async {
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (password.length < 6) {
      await showAppNoticeDialog(
        context,
        title: 'Mật khẩu chưa đạt',
        message: 'Mật khẩu cần có ít nhất 6 ký tự.',
        isError: true,
      );
      return;
    }

    if (password != confirmPassword) {
      await showAppNoticeDialog(
        context,
        title: 'Mật khẩu chưa khớp',
        message: 'Mật khẩu nhập lại chưa trùng khớp.',
        isError: true,
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final authRepository = ref.read(authRepositoryProvider);
      await authRepository.linkPasswordToCurrentPhoneUser(
        phoneNumber: _normalizedPhone,
        password: password,
      );

      final user = authRepository.currentUser;
      if (user != null) {
        await ref
            .read(profileRepositoryProvider)
            .ensureUserProfile(
              uid: user.uid,
              email:
                  user.email ??
                  authRepository.credentialEmailForPhone(_normalizedPhone),
            );
      }

      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Tạo tài khoản thành công',
        message:
            'Tài khoản của bạn đã được xác thực số điện thoại và tạo mật khẩu. Từ lần sau bạn có thể đăng nhập bằng số điện thoại + mật khẩu.',
      );
      if (!mounted) return;
      setState(() {
        _passwordSetupReady = false;
        _passwordController.clear();
        _confirmPasswordController.clear();
      });
    } catch (error) {
      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Không thể tạo mật khẩu',
        message: translateAuthError(error),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _signInWithPassword() async {
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
        message: 'Vui lòng nhập mật khẩu để đăng nhập.',
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
        await ref
            .read(profileRepositoryProvider)
            .ensureUserProfile(
              uid: user.uid,
              email:
                  user.email ??
                  authRepository.credentialEmailForPhone(normalizedPhone),
            );
      }
    } catch (error) {
      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Đăng nhập thất bại',
        message: translateAuthError(error),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _resetRegisterFlow({bool signOut = false}) async {
    if (signOut) {
      await ref.read(authRepositoryProvider).signOut();
    }

    if (!mounted) return;
    setState(() {
      _otpRequested = false;
      _passwordSetupReady = false;
      _verificationId = null;
      _resendToken = null;
      _normalizedPhone = '';
      _otpController.clear();
      _passwordController.clear();
      _confirmPasswordController.clear();
    });
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

  String _prettyPhone(String phone) {
    final digits = phone.replaceAll('+84', '0');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      if ((i == 3 || i == 6) && i != digits.length - 1) {
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  String _localPhoneInputFor(String? phone) {
    if (phone == null || phone.isEmpty) return '';
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.startsWith('84')) {
      return digits.substring(2);
    }
    if (digits.startsWith('0')) {
      return digits.substring(1);
    }
    return digits;
  }

  @override
  Widget build(BuildContext context) {
    final title = _registerMode ? 'Đăng ký tài khoản' : 'Đăng nhập';
    final primaryLabel = _registerMode
        ? _passwordSetupReady
              ? (_loading ? 'Đang tạo mật khẩu...' : 'Hoàn tất đăng ký')
              : _otpRequested
              ? (_loading ? 'Đang xác thực OTP...' : 'Xác thực OTP')
              : (_loading ? 'Đang gửi OTP...' : 'Gửi OTP đăng ký')
        : (_loading ? 'Đang đăng nhập...' : 'Đăng nhập');
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(title)),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE7FBF8), Color(0xFFF5F8FF), Color(0xFFFFF1E8)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -80,
              right: -40,
              child: _GlowBubble(
                size: 220,
                colors: [Color(0x3329B6B9), Color(0x11FFFFFF)],
              ),
            ),
            const Positioned(
              left: -60,
              bottom: 60,
              child: _GlowBubble(
                size: 180,
                colors: [Color(0x33FF8A5B), Color(0x11FFFFFF)],
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 96, 16, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFE46A11,
                            ).withValues(alpha: 0.10),
                            blurRadius: 36,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  colorScheme.primary,
                                  colorScheme.secondary,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Icon(
                              Icons.phone_android_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            'Money Now',
                            style: Theme.of(
                              context,
                            ).textTheme.headlineMedium?.copyWith(fontSize: 34),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _registerMode
                                ? _passwordSetupReady
                                      ? 'Số điện thoại đã xác thực. Tạo mật khẩu để hoàn tất tài khoản mới.'
                                      : (_otpRequested
                                            ? 'Nhập mã OTP để xác thực số điện thoại trước khi tạo mật khẩu.'
                                            : 'Tài khoản mới cần xác thực OTP trước, sau đó bạn sẽ tạo mật khẩu để đăng nhập về sau.')
                                : 'Đăng nhập bằng số điện thoại và mật khẩu.',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: const Color(0xFF5B6B7E)),
                          ),
                          if (widget.registrationPending) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3E7),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                'Số điện thoại của bạn đã xác thực thành công. Hãy tạo mật khẩu để hoàn tất tài khoản.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: const Color(0xFF8A4B14),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                          if (kDebugMode && _registerMode) ...[
                            const SizedBox(height: 14),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3E7),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                'Bản debug đang bật chế độ test OTP của Firebase. Hãy dùng số điện thoại test và mã test đã khai báo trong Authentication.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: const Color(0xFF8A4B14),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          TextField(
                            controller: _phoneController,
                            enabled:
                                !_loading &&
                                !_otpRequested &&
                                !_passwordSetupReady,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Số điện thoại',
                              hintText: '912345678',
                              prefixIcon: Icon(Icons.phone_rounded),
                              prefixText: '+84 ',
                              helperText:
                                  'Nhập số điện thoại không gồm số 0 đầu tiên.',
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (!_registerMode || _passwordSetupReady) ...[
                            TextField(
                              controller: _passwordController,
                              enabled: !_loading,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: _registerMode
                                    ? 'Tạo mật khẩu'
                                    : 'Mật khẩu',
                                hintText: 'Ít nhất 6 ký tự',
                                prefixIcon: const Icon(
                                  Icons.lock_outline_rounded,
                                ),
                              ),
                            ),
                          ],
                          if (_registerMode && _passwordSetupReady) ...[
                            const SizedBox(height: 12),
                            TextField(
                              controller: _confirmPasswordController,
                              enabled: !_loading,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Nhập lại mật khẩu',
                                hintText: 'Nhập lại để xác nhận',
                                prefixIcon: Icon(Icons.lock_reset_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _loading
                                    ? null
                                    : () => _resetRegisterFlow(signOut: true),
                                child: const Text('Đổi số điện thoại'),
                              ),
                            ),
                          ],
                          if (_registerMode && _otpRequested) ...[
                            TextField(
                              controller: _otpController,
                              enabled: !_loading,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ],
                              decoration: InputDecoration(
                                labelText: 'Mã OTP',
                                hintText: '6 chữ số',
                                prefixIcon: const Icon(Icons.password_rounded),
                                helperText:
                                    'OTP đã gửi tới ${_prettyPhone(_normalizedPhone)}',
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _loading
                                        ? null
                                        : () =>
                                              _resetRegisterFlow(signOut: true),
                                    child: const Text('Đổi số'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _loading
                                        ? null
                                        : () =>
                                              _requestRegisterOtp(resend: true),
                                    child: const Text('Gửi lại OTP'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 18),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: SizedBox(
                              key: ValueKey('auth-$primaryLabel'),
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _loading ? null : _submit,
                                child: Text(primaryLabel),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.center,
                            child: TextButton(
                              onPressed: _loading
                                  ? null
                                  : () async {
                                      await _resetRegisterFlow(
                                        signOut: _registerMode,
                                      );
                                      if (!mounted) return;
                                      setState(() {
                                        _registerMode = !_registerMode;
                                      });
                                    },
                              child: Text(
                                _registerMode
                                    ? 'Đã có tài khoản? Chuyển sang đăng nhập'
                                    : 'Chưa có tài khoản? Tạo mới',
                              ),
                            ),
                          ),
                          ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowBubble extends StatelessWidget {
  const _GlowBubble({required this.size, required this.colors});

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      ),
    );
  }
}
