import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/app_notice_dialog.dart';
import '../../providers/app_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _registerMode = false;
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      await showAppNoticeDialog(
        context,
        title: 'Thiếu thông tin',
        message: 'Email và mật khẩu là bắt buộc.',
        isError: true,
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final authRepository = ref.read(authRepositoryProvider);
      final profileRepository = ref.read(profileRepositoryProvider);

      if (_registerMode) {
        final credential = await authRepository.register(
          email: email,
          password: password,
        );

        final user = credential.user;
        if (user != null) {
          await profileRepository.ensureUserProfile(
            uid: user.uid,
            email: user.email ?? email,
          );
        }
      } else {
        final credential = await authRepository.signIn(
          email: email,
          password: password,
        );

        final user = credential.user;
        if (user != null) {
          await profileRepository.ensureUserProfile(
            uid: user.uid,
            email: user.email ?? email,
          );
        }
      }
    } catch (error) {
      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Đăng nhập thất bại',
        message: 'Không thể đăng nhập: $error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _registerMode ? 'Đăng ký tài khoản' : 'Đăng nhập';
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(title)),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFE7FBF8),
              Color(0xFFF5F8FF),
              Color(0xFFFFF1E8),
            ],
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
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.96, end: 1),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutBack,
                      builder: (context, value, child) {
                        return Transform.scale(scale: value, child: child);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0E7C86)
                                  .withValues(alpha: 0.10),
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
                                Icons.account_balance_wallet_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'Money Now',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(fontSize: 34),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _registerMode
                                  ? 'Tạo tài khoản để bắt đầu kiểm tra hạn mức vay nhanh hơn.'
                                  : 'Đăng nhập để tiếp tục hồ sơ vay và theo dõi tiến độ của bạn.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(color: const Color(0xFF5B6B7E)),
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                hintText: 'example@email.com',
                                prefixIcon: Icon(Icons.alternate_email_rounded),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passwordController,
                              obscureText: true,
                              decoration: const InputDecoration(
                                labelText: 'Mật khẩu',
                                hintText: 'Ít nhất 8 ký tự',
                                prefixIcon: Icon(Icons.lock_outline_rounded),
                              ),
                            ),
                            const SizedBox(height: 18),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: SizedBox(
                                key: ValueKey(_loading),
                                width: double.infinity,
                                child: FilledButton(
                                  onPressed: _loading ? null : _submit,
                                  child: Text(
                                    _loading ? 'Đang xử lý...' : title,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.center,
                              child: TextButton(
                                onPressed: _loading
                                    ? null
                                    : () {
                                        setState(
                                          () => _registerMode = !_registerMode,
                                        );
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
  const _GlowBubble({
    required this.size,
    required this.colors,
  });

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
