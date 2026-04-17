import 'package:flutter/material.dart';

Future<void> showAppNoticeDialog(
  BuildContext context, {
  required String title,
  required String message,
  bool isError = false,
}) {
  return showGeneralDialog<void>(
    context: context,
    transitionDuration: const Duration(milliseconds: 280),
    barrierColor: Colors.black.withValues(alpha: 0.28),
    barrierDismissible: true,
    barrierLabel: 'Đóng thông báo',
    pageBuilder: (context, animation, secondaryAnimation) {
      final colorScheme = Theme.of(context).colorScheme;
      final accentColor = isError ? colorScheme.error : colorScheme.primary;
      final softColor = accentColor.withValues(alpha: 0.12);
      final surfaceTint =
          isError ? const Color(0xFFFFF1F0) : const Color(0xFFFFF4EA);

      return Center(
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 32,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  decoration: BoxDecoration(
                    color: surfaceTint,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(32),
                    ),
                  ),
                  child: Column(
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.92, end: 1),
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutBack,
                        builder: (context, value, child) {
                          return Transform.scale(scale: value, child: child);
                        },
                        child: Container(
                          width: 68,
                          height: 68,
                          decoration: BoxDecoration(
                            color: softColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: accentColor.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Icon(
                            isError
                                ? Icons.warning_amber_rounded
                                : Icons.task_alt,
                            color: accentColor,
                            size: 34,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: const Color(0xFF12343B),
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                  child: Column(
                    children: [
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: const Color(0xFF486368),
                            ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: FilledButton.styleFrom(
                            backgroundColor: accentColor,
                          ),
                          child: const Text('Đã hiểu'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final fade = Tween<double>(begin: 0, end: 1).animate(curved);
      final scale = Tween<double>(begin: 0.94, end: 1).animate(curved);
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.035),
        end: Offset.zero,
      ).animate(curved);

      return FadeTransition(
        opacity: fade,
        child: SlideTransition(
          position: slide,
          child: ScaleTransition(
            scale: scale,
            child: child,
          ),
        ),
      );
    },
  );
}
