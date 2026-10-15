import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/reef_fish_theme.dart';
import '../domain/auth_repository.dart';
import 'auth_cubit.dart';

class AuthScreen extends StatelessWidget {
  const AuthScreen({
    required this.operation,
    required this.authRepository,
    required this.onAuthenticated,
    required this.onBack,
    this.onLoginFromSignup,
    super.key,
  });

  final AuthOperation operation;
  final AuthRepository authRepository;
  final AuthenticatedCallback? onAuthenticated;
  final void Function(BuildContext context) onBack;
  final void Function(BuildContext context)? onLoginFromSignup;

  bool get _isSignup => operation == AuthOperation.createAccount;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AuthCubit(authRepository),
      child: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, state) => switch (state.status) {
          AuthStatus.verificationRequired ||
          AuthStatus.verifying => _PhoneVerificationForm(
            onAuthenticated: onAuthenticated,
            operation: operation,
            onBack: onBack,
            onLogin: onLoginFromSignup,
          ),
          _ => _AuthForm(
            operation: operation,
            onAuthenticated: onAuthenticated,
            onBack: onBack,
            onLoginFromSignup: onLoginFromSignup,
            isSignup: _isSignup,
          ),
        },
      ),
    );
  }
}

class _AuthForm extends StatefulWidget {
  const _AuthForm({
    required this.operation,
    required this.onAuthenticated,
    required this.onBack,
    required this.onLoginFromSignup,
    required this.isSignup,
  });

  final AuthOperation operation;
  final AuthenticatedCallback? onAuthenticated;
  final void Function(BuildContext context) onBack;
  final void Function(BuildContext context)? onLoginFromSignup;
  final bool isSignup;

  @override
  State<_AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<_AuthForm> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocusNode = FocusNode();
  bool _passwordVisible = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ReefishColors.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => BlocConsumer<AuthCubit, AuthState>(
            listenWhen: (previous, current) =>
                previous.status != current.status &&
                current.status == AuthStatus.succeeded,
            listener: (context, state) {
              final callback = widget.onAuthenticated;
              if (callback != null) {
                callback(context, widget.operation);
                return;
              }
              final message = widget.isSignup
                  ? 'Pendaftaran berhasil.'
                  : 'Berhasil masuk.';
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(content: Text(message)));
            },
            builder: (context, state) => Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(24, 21, 24, 24),
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _BackControl(
                            isSignup: widget.isSignup,
                            onPressed: () => _goBack(context),
                          ),
                          SizedBox(
                            height: constraints.maxHeight < 700 ? 24 : 32,
                          ),
                          _AuthHeading(isSignup: widget.isSignup),
                          SizedBox(
                            height: constraints.maxHeight < 700 ? 24 : 32,
                          ),
                          _PhoneField(
                            controller: _phoneController,
                            isSignup: widget.isSignup,
                            onChanged: (_) =>
                                context.read<AuthCubit>().clearMessage(),
                            focusNode: null,
                            onSubmitted: (_) =>
                                _passwordFocusNode.requestFocus(),
                          ),
                          const SizedBox(height: 20),
                          _PasswordField(
                            controller: _passwordController,
                            focusNode: _passwordFocusNode,
                            visible: _passwordVisible,
                            isSignup: widget.isSignup,
                            onToggleVisible: () => setState(
                              () => _passwordVisible = !_passwordVisible,
                            ),
                            onChanged: (_) =>
                                context.read<AuthCubit>().clearMessage(),
                            onSubmitted: (_) => _submit(context),
                          ),
                          if (state.message case final message?) ...[
                            const SizedBox(height: 7),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                message,
                                style: const TextStyle(
                                  color: ReefishColors.signupAccent,
                                  fontSize: 12,
                                  height: 18 / 12,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _BottomActions(
                    isSignup: widget.isSignup,
                    isSubmitting: state.isSubmitting,
                    onSubmit: () => _submit(context),
                    onLogin: widget.onLoginFromSignup == null
                        ? null
                        : () => widget.onLoginFromSignup!(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submit(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    context.read<AuthCubit>().submit(
      operation: widget.operation,
      phone: _phoneController.text,
      password: _passwordController.text,
    );
  }

  void _goBack(BuildContext context) {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      widget.onBack(context);
    }
  }
}

class _BackControl extends StatelessWidget {
  const _BackControl({required this.isSignup, required this.onPressed});

  final bool isSignup;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Kembali',
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        width: 38,
        height: 38,
        child: SvgPicture.asset(
          isSignup
              ? 'assets/icons/signup-AkarIconsArrowLeft-a2c42192-1dc6-4d2e-8be8-ce409ab5a130.svg'
              : 'assets/icons/login-AkarIconsArrowLeft-b559ec96-131a-4c84-b0d4-8c5f220aab8d.svg',
          fit: BoxFit.contain,
        ),
      ),
    ),
  );
}

class _AuthHeading extends StatelessWidget {
  const _AuthHeading({required this.isSignup});

  final bool isSignup;

  @override
  Widget build(BuildContext context) {
    final mark = isSignup
        ? 'assets/icons/signup-ReefishMarkColorAtoll-a5dd5d6f-2280-41e2-b67d-b4f0ffd8a92d.svg'
        : 'assets/icons/login-ReefishMarkColorAtoll-fc2ecd40-eb81-448f-a0b0-ab29c7974c23.svg';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SvgPicture.asset(mark, width: 56, height: 42, fit: BoxFit.contain),
        const SizedBox(height: 4),
        Text(
          isSignup
              ? 'Mari Mulai Berlayar Bersama Reefish!'
              : 'Mari Masuk Kembali bersama Reefish!',
          style: const TextStyle(
            color: ReefishColors.textPrimary,
            fontSize: 24,
            height: 32 / 24,
            letterSpacing: -0.4,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isSignup
              ? 'Simpan catatan perjalanan melautmu dan persiapkan perjalanan berikutnya.'
              : 'Masuk untuk menyimpan catatan perjalanan melaut dan merencanakan perjalanan berikutnya.',
          style: const TextStyle(
            color: ReefishColors.textPrimary,
            fontSize: 14,
            height: 22 / 14,
          ),
        ),
      ],
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({
    required this.controller,
    required this.isSignup,
    required this.onChanged,
    required this.onSubmitted,
    required this.focusNode,
  });

  final TextEditingController controller;
  final bool isSignup;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final chipScale = textScale < 1 ? 1.0 : textScale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Nomor Telepon',
          style: TextStyle(
            color: ReefishColors.textPrimary,
            fontSize: 14,
            height: 20 / 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: ReefishColors.field,
            border: Border.all(color: ReefishColors.border, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Semantics(
                label: 'Kode negara Indonesia +62',
                child: Container(
                  width: 65 * chipScale,
                  height: 30 * chipScale,
                  decoration: BoxDecoration(
                    color: ReefishColors.reef,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        isSignup
                            ? 'assets/icons/signup-Vector-c7370e3f-12e0-4ab1-bbf1-7959986e2119.svg'
                            : 'assets/icons/login-Vector-13adb4ef-0314-48b9-85c4-d48b7741f519.svg',
                        width: 8 * chipScale,
                        height: 6 * chipScale,
                        fit: BoxFit.contain,
                      ),
                      SizedBox(width: 8 * chipScale),
                      const Text(
                        '+62',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 22 / 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumberNational],
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s().-]')),
                  ],
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  style: const TextStyle(
                    color: ReefishColors.textPrimary,
                    fontSize: 14,
                    height: 22 / 14,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Nomor Telepon',
                    hintStyle: TextStyle(color: ReefishColors.textSecondary),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.isSignup,
    required this.focusNode,
    required this.visible,
    required this.onToggleVisible,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool isSignup;
  final FocusNode focusNode;
  final bool visible;
  final VoidCallback onToggleVisible;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Kata Sandi',
        style: TextStyle(
          color: ReefishColors.textPrimary,
          fontSize: 14,
          height: 20 / 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 7),
      Container(
        height: 48,
        padding: const EdgeInsets.only(left: 12, right: 8),
        decoration: BoxDecoration(
          color: ReefishColors.field,
          border: Border.all(color: ReefishColors.border, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                obscureText: !visible,
                textInputAction: TextInputAction.done,
                autofillHints: isSignup
                    ? const [AutofillHints.newPassword]
                    : const [AutofillHints.password],
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                style: const TextStyle(
                  color: ReefishColors.textPrimary,
                  fontSize: 14,
                  height: 22 / 14,
                ),
                decoration: const InputDecoration(
                  hintText: 'Kata Sandi',
                  hintStyle: TextStyle(color: ReefishColors.textSecondary),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            Semantics(
              button: true,
              label: visible
                  ? 'Sembunyikan kata sandi'
                  : 'Tampilkan kata sandi',
              child: IconButton(
                onPressed: onToggleVisible,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 40,
                ),
                tooltip: visible
                    ? 'Sembunyikan kata sandi'
                    : 'Tampilkan kata sandi',
                icon: SvgPicture.asset(
                  isSignup
                      ? 'assets/icons/signup-AkarIconsEyeClosed-a105019c-9f87-4f96-b945-a418dcf66627.svg'
                      : 'assets/icons/login-AkarIconsEyeClosed-a13ace8a-5f75-41fc-9904-49491ac6ab2c.svg',
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 7),
      const Text(
        'Minimal 8 karakter',
        style: TextStyle(
          color: ReefishColors.info,
          fontSize: 12,
          height: 18 / 12,
          letterSpacing: 0.1,
        ),
      ),
    ],
  );
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.isSignup,
    required this.isSubmitting,
    required this.onSubmit,
    required this.onLogin,
  });

  final bool isSignup;
  final bool isSubmitting;
  final VoidCallback onSubmit;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        height: 48,
        width: double.infinity,
        child: ElevatedButton(
          onPressed: isSubmitting ? null : onSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: ReefishColors.primaryAction,
            foregroundColor: Colors.white,
            disabledBackgroundColor: ReefishColors.primaryAction.withValues(
              alpha: 0.65,
            ),
            elevation: 2,
            shadowColor: Colors.black.withValues(alpha: 0.28),
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(32),
              side: const BorderSide(color: ReefishColors.brand, width: 2),
            ),
          ),
          child: isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  isSignup ? 'Daftar' : 'Masuk',
                  style: const TextStyle(
                    fontSize: 16,
                    height: 24 / 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
      if (isSignup) ...[
        const SizedBox(height: 12),
        Semantics(
          button: true,
          label: 'Sudah Punya Akun? Masuk',
          child: GestureDetector(
            onTap: onLogin,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(
              width: double.infinity,
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    color: ReefishColors.textPrimary,
                    fontSize: 14,
                    height: 22 / 14,
                  ),
                  children: [
                    TextSpan(text: 'Sudah Punya Akun? '),
                    TextSpan(
                      text: 'Masuk',
                      style: TextStyle(
                        color: ReefishColors.signupAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

class _PhoneVerificationForm extends StatefulWidget {
  const _PhoneVerificationForm({
    required this.operation,
    required this.onAuthenticated,
    required this.onBack,
    required this.onLogin,
  });

  final AuthOperation operation;
  final AuthenticatedCallback? onAuthenticated;
  final void Function(BuildContext context) onBack;
  final void Function(BuildContext context)? onLogin;

  @override
  State<_PhoneVerificationForm> createState() => _PhoneVerificationFormState();
}

class _PhoneVerificationFormState extends State<_PhoneVerificationForm> {
  final _otpController = TextEditingController();
  Timer? _cooldownTimer;
  int _secondsUntilResend = 60;

  @override
  void initState() {
    super.initState();
    _secondsUntilResend = context.read<AuthCubit>().state.canResendImmediately
        ? 0
        : 60;
    if (_secondsUntilResend > 0) _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: ReefishColors.canvas,
    body: SafeArea(
      minimum: const EdgeInsets.only(bottom: 34),
      child: BlocConsumer<AuthCubit, AuthState>(
        listenWhen: (previous, current) =>
            previous.status != current.status &&
            current.status == AuthStatus.succeeded,
        listener: (context, state) =>
            widget.onAuthenticated?.call(context, widget.operation),
        builder: (context, state) => Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 21, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      button: true,
                      label: 'Kembali',
                      child: TextButton.icon(
                        onPressed: () => widget.onBack(context),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('Kembali'),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Verifikasi nomor ponsel',
                      style: TextStyle(
                        color: ReefishColors.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Masukkan kode verifikasi 6 digit untuk nomor ponselmu.',
                      style: TextStyle(
                        color: ReefishColors.textPrimary,
                        fontSize: 14,
                        height: 22 / 14,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      maxLength: 6,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Kode verifikasi',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _verify(context),
                    ),
                    if (state.message case final message?) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: ReefishColors.signupAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed:
                          state.status == AuthStatus.verifying ||
                              _secondsUntilResend > 0
                          ? null
                          : () async {
                              final cubit = context.read<AuthCubit>();
                              await cubit.resendPhoneOtp();
                              if (!mounted) return;
                              setState(() => _secondsUntilResend = 60);
                              _startCooldown();
                            },
                      child: Text(
                        _secondsUntilResend > 0
                            ? 'Kirim ulang dalam $_secondsUntilResend detik'
                            : 'Kirim ulang kode',
                      ),
                    ),
                    if (widget.operation == AuthOperation.createAccount &&
                        widget.onLogin != null)
                      TextButton(
                        onPressed: () => widget.onLogin!(context),
                        child: const Text('Sudah punya akun? Masuk'),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
              child: SizedBox(
                height: 48,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: state.status == AuthStatus.verifying
                      ? null
                      : () => _verify(context),
                  child: state.status == AuthStatus.verifying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verifikasi'),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  void _verify(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
    context.read<AuthCubit>().verifyPhone(_otpController.text.trim());
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _secondsUntilResend--;
        if (_secondsUntilResend <= 0) timer.cancel();
      });
    });
  }
}
