import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/reef_fish_theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    required this.onCreateAccount,
    required this.onLogin,
    super.key,
  });

  final void Function(BuildContext context) onCreateAccount;
  final void Function(BuildContext context) onLogin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final scale = _coverScale(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              const Positioned.fill(
                child: ColoredBox(color: ReefishColors.canvas),
              ),
              Positioned(
                left: -46 * scale,
                top: -17 * scale,
                width: 645 * scale,
                height: 966 * scale,
                child: Image.asset(
                  'assets/images/welcome-UnsplashUzqHVFnIO-ef4dbcb7-f722-4b67-a17e-c2dfa54adb07.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  excludeFromSemantics: true,
                ),
              ),
              Positioned(
                left: -80 * scale,
                top: 607 * scale,
                width: 627 * scale,
                height: 582 * scale,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: 200 * scale,
                    sigmaY: 200 * scale,
                  ),
                  child: const ColoredBox(color: ReefishColors.textPrimary),
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, safeConstraints) => Stack(
                    children: [
                      Positioned(
                        left: safeConstraints.maxWidth * 0.25 + 17.5,
                        top: 31,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 76,
                              height: 57,
                              child: SvgPicture.asset(
                                'assets/icons/welcome-ReefishMarkColorAtoll-1f38123a-7217-4060-9e43-d358271b84a7.svg',
                                fit: BoxFit.contain,
                              ),
                            ),
                            const Text(
                              'Reefish',
                              style: TextStyle(
                                color: ReefishColors.textPrimary,
                                fontSize: 32,
                                height: 40 / 32,
                                letterSpacing: -0.8,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 24,
                        right: 24,
                        bottom: 0,
                        child: _WelcomeMessage(
                          onCreateAccount: () => onCreateAccount(context),
                          onLogin: () => onLogin(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _coverScale(double width, double height) =>
      (width / 430).clamp(height / 932, double.infinity).toDouble();
}

class _WelcomeMessage extends StatelessWidget {
  const _WelcomeMessage({required this.onCreateAccount, required this.onLogin});

  final VoidCallback onCreateAccount;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Catat Perjalanan dengan Caramu!',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            height: 40 / 32,
            letterSpacing: -0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Catat perjalanan saat melaut atau setelah kembali ke darat, lalu lihat perkiraan biaya BBM dan pendapatanmu.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 14, height: 22 / 14),
        ),
        const SizedBox(height: 20),
        _PrimaryAction(label: 'Mulai', onPressed: onCreateAccount),
        const SizedBox(height: 20),
        Semantics(
          button: true,
          label: 'Sudah Punya Akun? Masuk',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onLogin,
            child: const SizedBox(
              width: 332,
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    height: 22 / 14,
                  ),
                  children: [
                    TextSpan(text: 'Sudah Punya Akun? '),
                    TextSpan(
                      text: 'Masuk',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: ReefishColors.primaryAction,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(32),
              side: const BorderSide(color: ReefishColors.brand, width: 2),
            ),
          ),
          onPressed: onPressed,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              height: 24 / 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
}
