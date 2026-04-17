import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/uploaded_document.dart';

class StorageRepository {
  StorageRepository(this._storage, this._auth);

  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  final Uuid _uuid = const Uuid();

  Future<UploadedDocument> uploadUserDocument({
    required String uid,
    required String type,
    required XFile file,
  }) async {
    final authUser = _auth.currentUser;
    if (authUser == null) {
      throw FirebaseException(
        plugin: 'firebase_auth',
        code: 'auth-required',
        message: 'Phiên đăng nhập đã hết. Vui lòng đăng nhập lại rồi thử tải CCCD.',
      );
    }

    if (authUser.uid != uid) {
      throw FirebaseException(
        plugin: 'firebase_storage',
        code: 'unauthorized',
        message: 'Phiên đăng nhập không khớp với hồ sơ hiện tại.',
      );
    }

    await authUser.getIdToken(true);

    final extension = _fileExtension(file.name);
    final id = _uuid.v4();
    final safeExtension = extension.isEmpty ? 'jpg' : extension;
    final storagePath = 'users/$uid/documents/${DateTime.now().millisecondsSinceEpoch}_${type}_$id.$safeExtension';
    final ref = _storage.ref(storagePath);

    final bytes = await file.readAsBytes();

    final metadata = SettableMetadata(
      contentType: _contentTypeForExtension(safeExtension),
      customMetadata: {
        'uid': uid,
        'type': type,
      },
    );

    await ref.putData(bytes, metadata);
    final downloadUrl = await ref.getDownloadURL();

    return UploadedDocument(
      id: id,
      type: type,
      fileName: file.name,
      storagePath: storagePath,
      downloadUrl: downloadUrl,
      status: 'uploaded',
      createdAt: DateTime.now(),
    );
  }

  String _fileExtension(String fileName) {
    final index = fileName.lastIndexOf('.');
    if (index == -1 || index == fileName.length - 1) {
      return '';
    }
    return fileName.substring(index + 1).toLowerCase();
  }

  String _contentTypeForExtension(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpeg':
      case 'jpg':
      default:
        return 'image/jpeg';
    }
  }
}
