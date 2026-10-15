import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/widgets.dart';

import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';
import '../domain/indonesian_phone_number.dart';

enum AuthStatus {
  idle,
  submitting,
  verificationRequired,
  verifying,
  succeeded,
  failed,
}

enum AuthOperation { createAccount, login }

typedef AuthenticatedCallback =
    void Function(BuildContext context, AuthOperation operation);

class AuthState {
  const AuthState({
    this.status = AuthStatus.idle,
    this.message,
    this.phoneE164,
    this.canResendImmediately = false,
  });

  final AuthStatus status;
  final String? message;
  final String? phoneE164;
  final bool canResendImmediately;

  bool get isSubmitting => status == AuthStatus.submitting;
}

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this._repository) : super(const AuthState());

  final AuthRepository _repository;

  Future<void> submit({
    required AuthOperation operation,
    required String phone,
    required String password,
  }) async {
    if (state.isSubmitting || state.status == AuthStatus.succeeded) return;

    final normalized = IndonesianPhoneNumber.normalize(phone);
    if (!normalized.isValid) {
      emit(AuthState(status: AuthStatus.failed, message: normalized.error));
      return;
    }
    if (password.length < 8) {
      emit(
        const AuthState(
          status: AuthStatus.failed,
          message: 'Kata sandi minimal 8 karakter.',
        ),
      );
      return;
    }

    emit(const AuthState(status: AuthStatus.submitting));
    try {
      if (operation == AuthOperation.createAccount) {
        final result = await _repository.createAccount(
          phoneE164: normalized.e164!,
          password: password,
        );
        if (result == AuthResult.verificationRequired) {
          if (isClosed) return;
          emit(
            AuthState(
              status: AuthStatus.verificationRequired,
              phoneE164: normalized.e164,
            ),
          );
          return;
        }
      } else {
        final result = await _repository.login(
          phoneE164: normalized.e164!,
          password: password,
        );
        if (result == AuthResult.verificationRequired) {
          if (isClosed) return;
          emit(
            AuthState(
              status: AuthStatus.verificationRequired,
              phoneE164: normalized.e164,
              canResendImmediately: true,
            ),
          );
          return;
        }
      }
      if (isClosed) return;
      emit(const AuthState(status: AuthStatus.succeeded));
    } on AuthFailure catch (failure) {
      if (isClosed) return;
      if (failure.code == AuthFailureCode.phoneVerificationRequired) {
        emit(
          AuthState(
            status: AuthStatus.verificationRequired,
            phoneE164: normalized.e164,
            canResendImmediately: true,
          ),
        );
        return;
      }
      emit(
        AuthState(
          status: AuthStatus.failed,
          message: _messageFor(failure.code),
        ),
      );
    } catch (_) {
      if (isClosed) return;
      emit(
        const AuthState(
          status: AuthStatus.failed,
          message: 'Terjadi kendala. Coba lagi sebentar.',
        ),
      );
    }
  }

  Future<void> verifyPhone(String otp) async {
    final phoneE164 = state.phoneE164;
    if (state.status == AuthStatus.verifying || phoneE164 == null) return;
    if (!RegExp(r'^\d{6}$').hasMatch(otp)) {
      emit(
        AuthState(
          status: AuthStatus.verificationRequired,
          phoneE164: phoneE164,
          message: 'Masukkan kode 6 digit.',
          canResendImmediately: state.canResendImmediately,
        ),
      );
      return;
    }
    emit(
      AuthState(
        status: AuthStatus.verifying,
        phoneE164: phoneE164,
        canResendImmediately: state.canResendImmediately,
      ),
    );
    try {
      await _repository.verifyPhone(phoneE164: phoneE164, otp: otp);
      if (!isClosed) emit(const AuthState(status: AuthStatus.succeeded));
    } on AuthFailure catch (failure) {
      if (!isClosed) {
        emit(
          AuthState(
            status: AuthStatus.verificationRequired,
            phoneE164: phoneE164,
            message: _messageFor(failure.code),
            canResendImmediately: state.canResendImmediately,
          ),
        );
      }
    } catch (_) {
      if (!isClosed) {
        emit(
          AuthState(
            status: AuthStatus.verificationRequired,
            phoneE164: phoneE164,
            message: 'Terjadi kendala. Coba lagi sebentar.',
            canResendImmediately: state.canResendImmediately,
          ),
        );
      }
    }
  }

  Future<void> resendPhoneOtp() async {
    final phoneE164 = state.phoneE164;
    if (state.status == AuthStatus.verifying || phoneE164 == null) return;
    emit(
      AuthState(
        status: AuthStatus.verifying,
        phoneE164: phoneE164,
        canResendImmediately: state.canResendImmediately,
      ),
    );
    try {
      await _repository.resendPhoneOtp(phoneE164: phoneE164);
      if (!isClosed) {
        emit(
          AuthState(
            status: AuthStatus.verificationRequired,
            phoneE164: phoneE164,
            message: 'Kode baru sudah diminta.',
            canResendImmediately: false,
          ),
        );
      }
    } on AuthFailure catch (failure) {
      if (!isClosed) {
        emit(
          AuthState(
            status: AuthStatus.verificationRequired,
            phoneE164: phoneE164,
            message: _messageFor(failure.code),
            canResendImmediately: state.canResendImmediately,
          ),
        );
      }
    } catch (_) {
      if (!isClosed) {
        emit(
          AuthState(
            status: AuthStatus.verificationRequired,
            phoneE164: phoneE164,
            message: 'Terjadi kendala. Coba lagi sebentar.',
            canResendImmediately: state.canResendImmediately,
          ),
        );
      }
    }
  }

  void clearMessage() {
    if (state.status == AuthStatus.failed) emit(const AuthState());
  }

  String _messageFor(AuthFailureCode code) => switch (code) {
    AuthFailureCode.invalidCredentials =>
      'Nomor ponsel atau kata sandi tidak sesuai.',
    AuthFailureCode.phoneAlreadyRegistered =>
      'Nomor ponsel sudah terdaftar. Silakan masuk.',
    AuthFailureCode.phoneVerificationRequired =>
      'Nomor ponsel perlu diverifikasi. Masukkan kode 6 digit untuk melanjutkan.',
    AuthFailureCode.invalidOtp =>
      'Kode verifikasi tidak sesuai atau sudah kedaluwarsa.',
    AuthFailureCode.tooManyRequests =>
      'Terlalu banyak permintaan. Tunggu sekitar 60 detik sebelum mencoba lagi.',
    AuthFailureCode.phoneProviderDisabled =>
      'Login nomor ponsel belum diaktifkan. Coba lagi nanti.',
    AuthFailureCode.notConfigured =>
      'Layanan akun belum terhubung. Coba lagi nanti.',
    AuthFailureCode.unknown => 'Terjadi kendala. Coba lagi sebentar.',
  };
}
