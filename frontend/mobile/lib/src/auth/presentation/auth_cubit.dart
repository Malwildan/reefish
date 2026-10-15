import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';
import '../domain/indonesian_phone_number.dart';

enum AuthStatus { idle, submitting, succeeded, failed }

enum AuthOperation { createAccount, login }

typedef AuthenticatedCallback = void Function(AuthOperation operation);

class AuthState {
  const AuthState({this.status = AuthStatus.idle, this.message});

  final AuthStatus status;
  final String? message;

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
        await _repository.createAccount(
          phoneE164: normalized.e164!,
          password: password,
        );
      } else {
        await _repository.login(
          phoneE164: normalized.e164!,
          password: password,
        );
      }
      if (isClosed) return;
      emit(const AuthState(status: AuthStatus.succeeded));
    } on AuthFailure catch (failure) {
      if (isClosed) return;
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

  void clearMessage() {
    if (state.status == AuthStatus.failed) emit(const AuthState());
  }

  String _messageFor(AuthFailureCode code) => switch (code) {
        AuthFailureCode.invalidCredentials =>
          'Nomor ponsel atau kata sandi tidak sesuai.',
        AuthFailureCode.phoneAlreadyRegistered =>
          'Nomor ponsel sudah terdaftar. Silakan masuk.',
        AuthFailureCode.notConfigured =>
          'Layanan akun belum terhubung. Coba lagi nanti.',
        AuthFailureCode.unknown => 'Terjadi kendala. Coba lagi sebentar.',
      };
}
