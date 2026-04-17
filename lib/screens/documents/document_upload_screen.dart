import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/utils/formatters.dart';
import '../../core/widgets/app_notice_dialog.dart';
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

    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
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

      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Tải lên thành công',
        message: 'Đã tải lên ${type.label}.',
      );
    } catch (error) {
      if (!mounted) return;
      await showAppNoticeDialog(
        context,
        title: 'Tải lên thất bại',
        message: 'Tải lên thất bại: $error',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingType = null);
      }
    }
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

            return Card(
              child: ListTile(
                leading: const Icon(Icons.image_outlined),
                title: Text(type.label),
                subtitle: Text(
                  latest == null
                      ? 'Chưa có tệp'
                      : 'Đã tải lên: ${latest.fileName}\n${AppFormatters.dateTime(latest.createdAt)}',
                ),
                isThreeLine: latest != null,
                trailing: FilledButton.tonal(
                  onPressed:
                      _uploadingType == null ? () => _upload(type) : null,
                  child: Text(
                    _uploadingType == type.key ? 'Đang tải...' : 'Chọn ảnh',
                  ),
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
