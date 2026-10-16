import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/reef_fish_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({required this.onComplete, super.key});

  final void Function(BuildContext context) onComplete;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) widget.onComplete(context);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: ReefishColors.canvas,
      body: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _SplashMark(),
            Text(
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
    );
  }
}

class _SplashMark extends StatelessWidget {
  const _SplashMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 57,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: 11.64,
            top: 6.82,
            width: 57.15,
            height: 49.24,
            child: SvgPicture.asset(
              'assets/icons/splash-Vector-87923120-9b27-4600-81c2-92942eaadada.svg',
              fit: BoxFit.contain,
            ),
          ),
          Positioned(
            left: 4.27,
            top: 25.65,
            width: 10.93,
            height: 16.63,
            child: SvgPicture.asset(
              'assets/icons/splash-Vector1-fa8c122e-eea0-43e3-b5ae-a633def9f934.svg',
              fit: BoxFit.contain,
            ),
          ),
          Positioned(
            left: 29.69,
            top: 18.76,
            width: 18.53,
            height: 24.70,
            child: SvgPicture.asset(
              'assets/icons/splash-Vector2-1a90cab9-dad5-4eb8-8a07-f6d7d17f8afa.svg',
              fit: BoxFit.contain,
            ),
          ),
          Positioned(
            left: 55.77,
            top: 23.99,
            width: 3.32,
            height: 3.31,
            child: SvgPicture.asset(
              'assets/icons/splash-Vector3-39527e75-760d-4b29-828d-06818568e8ea.svg',
              fit: BoxFit.contain,
            ),
          ),
        ],
      ),
    );
  }
}
