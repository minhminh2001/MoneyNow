import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/app_notice_dialog.dart';
import '../../models/uploaded_document.dart';
import '../../providers/app_providers.dart';

class DocumentUploadScreen extends ConsumerStatefulWidget {
  const DocumentUploadScreen({super.key});

  @override
  ConsumerState<DocumentUploadScreen> createState() =>
      _DocumentUploadScreenState();
}

class _DocumentUploadScreenState extends ConsumerState<DocumentUploadScreen> {
  final ImagePicker _picker = ImagePicker();
  String? _uploadingType;

  static const List<_DocumentType> _types = [
    _DocumentType(key: 'id_front', label: 'CCCD mặt trước'),
    _DocumentType(key: 'id_back', label: 'CCCD mặt sau'),
    _DocumentType(key: 'selfie', label: 'Ảnh selfie cầm CCCD'),
  ];

  Future<void> _upload(_DocumentType type) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final source = await _pickImageSource(type);
    if (source == null) return;

    final file = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (file == null) return;

    setState(() => _uploadingType = type.key);

    try {
      final uploaded =
          await ref.read(storageRepositoryProvider).uploadUserDocument(
                uid: user.uid,
                type: type.key,
                file: file,
              );

      await ref.read(profileRepositoryProvider).saveUploadedDocument(
            uid: user.uid,
            document: uploaded,
          );

      _clearUploadingState();

      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Tải lên thành công',
        message: 'Đã tải lên ${type.label}.',
      );
    } catch (error) {
      _clearUploadingState();

      if (!mounted) return;
      final message = _buildUploadErrorMessage(error);
      await showAppNoticeDialog(
        context,
        title: 'Tải lên thất bại',
        message: message,
        isError: true,
      );
    } finally {
      _clearUploadingState();
    }
  }

  void _clearUploadingState() {
    if (!mounted || _uploadingType == null) return;
    setState(() => _uploadingType = null);
  }

  Future<ImageSource?> _pickImageSource(_DocumentType type) async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chọn nguồn ảnh',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  'Tải ${type.label.toLowerCase()} bằng camera hoặc chọn từ thư viện ảnh.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF5B6B7E),
                      ),
                ),
                const SizedBox(height: 18),
                _SourceActionTile(
                  icon: Icons.camera_alt_rounded,
                  title: 'Chụp ảnh',
                  subtitle: 'Mở camera để chụp trực tiếp',
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
                const SizedBox(height: 10),
                _SourceActionTile(
                  icon: Icons.photo_library_rounded,
                  title: 'Chọn từ thư viện',
                  subtitle: 'Dùng ảnh đã có trong máy',
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _buildUploadErrorMessage(Object error) {
    if (error is FirebaseException) {
      if (error.plugin == 'firebase_storage' &&
          error.code == 'unauthorized') {
        return 'Tài khoản hiện tại chưa có quyền tải tài liệu lên Firebase Storage. '
            'Nếu bạn vừa đổi cấu hình Firebase hoặc vừa đăng nhập, hãy đăng xuất rồi đăng nhập lại. '
            'Nếu vẫn lỗi, cần kiểm tra và deploy lại Storage Rules cho bucket production.';
      }

      if (error.plugin == 'firebase_auth' &&
          error.code == 'auth-required') {
        return error.message ??
            'Phiên đăng nhập đã hết. Vui lòng đăng nhập lại rồi thử tải CCCD.';
      }

      return error.message ?? error.toString();
    }

    return 'Tải lên thất bại: $error';
  }

  Future<void> _openPreview(UploadedDocument document) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Xem tài liệu',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      document.fileName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: const Color(0xFF5B6B7E),
                          ),
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: AspectRatio(
                        aspectRatio: 0.72,
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 4,
                          child: Image.network(
                            document.downloadUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    'Không thể hiển thị ảnh. Vui lòng thử lại sau.',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final documentsAsync = ref.watch(userDocumentsProvider);
    final documents = documentsAsync.value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Tải tài liệu KYC')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Bạn cần tải đủ 3 ảnh để hệ thống có thể xử lý hồ sơ vay.',
          ),
          const SizedBox(height: 12),
          ..._types.map((type) {
            final matches = documents.where((doc) => doc.type == type.key);
            final latest = matches.isEmpty ? null : matches.first;
            final isUploading = _uploadingType == type.key;

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: latest == null ? null : () => _openPreview(latest),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          width: 72,
                          height: 72,
                          color: const Color(0xFFF3F7FA),
                          alignment: Alignment.center,
                          child: latest == null
                              ? const Icon(Icons.image_outlined, size: 34)
                              : Image.network(
                                  latest.downloadUrl,
                                  fit: BoxFit.cover,
                                  width: 72,
                                  height: 72,
                                  errorBuilder:
                                      (context, error, stackTrace) {
                                    return const Icon(
                                      Icons.image_outlined,
                                      size: 34,
                                    );
                                  },
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(type.label),
                          const SizedBox(height: 6),
                          Text(
                            latest == null ? 'Chưa có tệp' : latest.fileName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: const Color(0xFF5B6B7E)),
                          ),
                          if (latest != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              AppFormatters.dateTime(latest.createdAt),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: const Color(0xFF7A8A9A),
                                  ),
                            ),
                            const SizedBox(height: 10),
                            TextButton.icon(
                              onPressed: () => _openPreview(latest),
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('Xem ảnh'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed:
                          _uploadingType == null ? () => _upload(type) : null,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isUploading) ...[
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(isUploading ? 'Đang tải...' : 'Tải ảnh'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _DocumentType {
  const _DocumentType({
    required this.key,
    required this.label,
  });

  final String key;
  final String label;
}

class _SourceActionTile extends StatelessWidget {
  const _SourceActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF6FAFB),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE1EEF2)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF5B6B7E),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
