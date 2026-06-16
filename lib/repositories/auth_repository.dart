import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class PhoneOtpRequestResult {
  const PhoneOtpRequestResult._({
    required this.verificationId,
    required this.resendToken,
    required this.autoVerifiedCredential,
  });

  const PhoneOtpRequestResult.codeSent({
    required String verificationId,
    int? resendToken,
  }) : this._(
          verificationId: verificationId,
          resendToken: resendToken,
          autoVerifiedCredential: null,
        );

  const PhoneOtpRequestResult.autoVerified(UserCredential credential)
      : this._(
          verificationId: '',
          resendToken: null,
          autoVerifiedCredential: credential,
        );

  final String verificationId;
  final int? resendToken;
  final UserCredential? autoVerifiedCredential;

  bool get isAutoVerified => autoVerifiedCredential != null;
}

class AuthRepository {
  AuthRepository(this._auth);

  final FirebaseAuth _auth;
  static const _phonePasswordEmailDomain = 'auth.moneynow.local';

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  String credentialEmailForPhone(String phoneNumber) {
    final digits = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    return 'phone_$digits@$_phonePasswordEmailDomain';
  }

  Future<PhoneOtpRequestResult> requestPhoneOtp({
    required String phoneNumber,
    int? forceResendingToken,
  }) async {
    if (kIsWeb) {
      throw FirebaseAuthException(
        code: 'unsupported-platform',
        message:
            'Luồng OTP số điện thoại trong app này hiện chỉ được cấu hình cho Android và iOS.',
      );
    }

    final completer = Completer<PhoneOtpRequestResult>();

    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      forceResendingToken: forceResendingToken,
      verificationCompleted: (credential) async {
        if (completer.isCompleted) return;
        try {
          final userCredential = await _auth.signInWithCredential(credential);
          await userCredential.user?.reload();
          await userCredential.user?.getIdToken(true);
          completer
              .complete(PhoneOtpRequestResult.autoVerified(userCredential));
        } catch (error) {
          completer.completeError(error);
        }
      },
      verificationFailed: (error) {
        if (!completer.isCompleted) {
          completer.completeError(error);
        }
      },
      codeSent: (verificationId, resendToken) {
        if (!completer.isCompleted) {
          completer.complete(
            PhoneOtpRequestResult.codeSent(
              verificationId: verificationId,
              resendToken: resendToken,
            ),
          );
        }
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (!completer.isCompleted) {
          completer.complete(
            PhoneOtpRequestResult.codeSent(verificationId: verificationId),
          );
        }
      },
    );

    return completer.future;
  }

  Future<UserCredential> verifyPhoneOtp({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = await _auth.signInWithCredential(
      PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      ),
    );
    await credential.user?.reload();
    await credential.user?.getIdToken(true);
    return credential;
  }

  Future<UserCredential> signInWithPhoneAndPassword({
    required String phoneNumber,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: credentialEmailForPhone(phoneNumber),
      password: password,
    );
    await credential.user?.reload();
    await credential.user?.getIdToken(true);
    return credential;
  }

  Future<void> linkPasswordToCurrentPhoneUser({
    required String phoneNumber,
    required String password,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'auth-required',
        message: 'Phiên xác thực đã hết. Vui lòng xác minh OTP lại từ đầu.',
      );
    }

    final emailCredential = EmailAuthProvider.credential(
      email: credentialEmailForPhone(phoneNumber),
      password: password,
    );

    await user.linkWithCredential(emailCredential);
    await user.reload();
    await user.getIdToken(true);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _auth.authStateChanges().firstWhere((user) => user == null);
  }
}

String translateAuthError(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-phone-number':
        return 'Số điện thoại không đúng định dạng. Hãy dùng số Việt Nam như 0912345678 hoặc +84912345678.';
      case 'auth-required':
        return error.message ??
            'Phiên xác thực đã hết. Vui lòng thực hiện lại từ đầu.';
      case 'invalid-verification-code':
        return 'Mã OTP không chính xác.';
      case 'session-expired':
        return 'Mã OTP đã hết hạn. Vui lòng yêu cầu gửi lại mã.';
      case 'too-many-requests':
        return 'Thiết bị đang gửi yêu cầu OTP quá nhiều lần. Vui lòng chờ một lúc rồi thử lại.';
      case 'quota-exceeded':
        return 'Hạn mức gửi OTP của Firebase Authentication đã chạm ngưỡng.';
      case 'unsupported-platform':
        return error.message ??
            'Nền tảng hiện tại chưa được cấu hình cho đăng nhập bằng số điện thoại.';
      case 'invalid-app-credential':
      case 'captcha-check-failed':
        return 'Xác minh ứng dụng thất bại. Hãy kiểm tra cấu hình Phone Auth trên Firebase cho app này.';
      case 'wrong-password':
      case 'user-not-found':
        return 'Số điện thoại hoặc mật khẩu không chính xác.';
      case 'email-already-in-use':
        return 'Số điện thoại này đã được đăng ký. Hãy chuyển sang đăng nhập.';
      case 'weak-password':
        return 'Mật khẩu quá yếu. Vui lòng dùng ít nhất 6 ký tự.';
      case 'provider-already-linked':
        return 'Tài khoản này đã có mật khẩu. Hãy chuyển sang đăng nhập.';
      case 'credential-already-in-use':
        return 'Số điện thoại này đã được dùng cho tài khoản khác.';
      case 'invalid-credential':
        return 'Phiên xác thực hoặc thông tin đăng nhập không hợp lệ. Vui lòng thử lại từ đầu.';
      case 'network-request-failed':
        return 'Không thể kết nối mạng. Vui lòng kiểm tra Internet và thử lại.';
      case 'internal-error':
        final raw = (error.message ?? '').toUpperCase();
        if (raw.contains('CONFIGURATION_NOT_FOUND')) {
          return 'Firebase Authentication chưa được cấu hình đúng cho ứng dụng này. Hãy kiểm tra lại project Firebase và bật Phone trong Authentication.';
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
    return 'Firebase Authentication chưa được cấu hình đúng cho ứng dụng này. Hãy kiểm tra lại project Firebase và bật Phone trong Authentication.';
  }

  return 'Không thể xác thực tài khoản lúc này. Vui lòng thử lại.';
}
