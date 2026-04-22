import 'package:firebase_auth/firebase_auth.dart';

class AuthRepository {
  AuthRepository(this._auth);

  final FirebaseAuth _auth;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await credential.user?.reload();
    await credential.user?.getIdToken(true);
    return credential;
  }

  Future<UserCredential> register({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await credential.user?.reload();
    await credential.user?.getIdToken(true);
    return credential;
  }

  Future<void> signOut() => _auth.signOut();
}

String translateAuthError(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-email':
        return 'Email không đúng định dạng.';
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Email hoặc mật khẩu không chính xác.';
      case 'email-already-in-use':
        return 'Email này đã được sử dụng.';
      case 'weak-password':
        return 'Mật khẩu quá yếu. Vui lòng dùng mật khẩu mạnh hơn.';
      case 'network-request-failed':
        return 'Không thể kết nối mạng. Vui lòng kiểm tra Internet và thử lại.';
      case 'internal-error':
        final raw = (error.message ?? '').toUpperCase();
        if (raw.contains('CONFIGURATION_NOT_FOUND')) {
          return 'Firebase Authentication chưa được cấu hình đúng cho ứng dụng iPhone này. Hãy kiểm tra lại project Firebase, file GoogleService-Info.plist và bật Email/Password trong Authentication.';
        }
        return 'Hệ thống xác thực đang gặp lỗi nội bộ. Vui lòng thử lại sau.';
      default:
        final message = error.message?.trim();
        if (message != null && message.isNotEmpty) {
          return message;
        }
        return 'Không thể xác thực tài khoản lúc này. Vui lòng thử lại.';
    }
  }

  final text = error.toString();
  if (text.toUpperCase().contains('CONFIGURATION_NOT_FOUND')) {
    return 'Firebase Authentication chưa được cấu hình đúng cho ứng dụng iPhone này. Hãy kiểm tra lại project Firebase, file GoogleService-Info.plist và bật Email/Password trong Authentication.';
  }

  return 'Không thể xác thực tài khoản lúc này. Vui lòng thử lại.';
}
