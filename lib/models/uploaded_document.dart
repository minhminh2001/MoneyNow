import '../core/utils/firestore_value.dart';

class UploadedDocument {
  const UploadedDocument({
    required this.id,
    required this.type,
    required this.fileName,
    required this.storagePath,
    required this.downloadUrl,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String fileName;
  final String storagePath;
  final String downloadUrl;
  final String status;
  final DateTime? createdAt;

  factory UploadedDocument.fromMap(String id, Map<String, dynamic> map) {
    return UploadedDocument(
      id: id,
      type: readString(map['type']),
      fileName: readString(map['fileName']),
      storagePath: readString(map['storagePath']),
      downloadUrl: readString(map['downloadUrl']),
      status: readString(map['status']).isEmpty
          ? 'uploaded'
          : readString(map['status']),
      createdAt: readDateTime(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'fileName': fileName,
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
      'status': status,
      'createdAt': createdAt,
    };
  }
}
