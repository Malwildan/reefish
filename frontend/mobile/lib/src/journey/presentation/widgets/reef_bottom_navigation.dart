import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../theme/reef_fish_theme.dart';

enum ReefTab { home, profile }

class ReefBottomNavigation extends StatelessWidget {
  const ReefBottomNavigation({
    this.active = ReefTab.profile,
    this.onHome,
    this.onProfile,
    this.onSail,
    super.key,
  });
  final ReefTab active;
  final VoidCallback? onHome;
  final VoidCallback? onProfile;
  final VoidCallback? onSail;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = math.min(428.0, constraints.maxWidth);
      return SizedBox(
        height: 107,
        child: Center(
          child: SizedBox(
            width: width,
            height: 107,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: SvgPicture.asset(
                    'assets/journey/bottom-nav.svg',
                    fit: BoxFit.fill,
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _tab(
                        'Beranda',
                        active == ReefTab.home
                            ? Icons.home
                            : Icons.home_outlined,
                        active == ReefTab.home,
                        onHome,
                      ),
                      _tab(
                        'Profil',
                        active == ReefTab.profile
                            ? Icons.person
                            : Icons.person_outline,
                        active == ReefTab.profile,
                        onProfile,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: width / 2 - 27.5,
                  top: 10,
                  child: Semantics(
                    label: 'Mulai Berlayar',
                    button: true,
                    child: Material(
                      color: ReefishColors.brand,
                      shape: const CircleBorder(),
                      elevation: 5,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onSail,
                        child: SizedBox(
                          width: 55,
                          height: 55,
                          child: Center(
                            child: SvgPicture.asset(
                              'assets/journey/boat.svg',
                              width: 24,
                              height: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _tab(
    String label,
    IconData icon,
    bool selected,
    VoidCallback? action,
  ) => Semantics(
    label: label,
    button: true,
    selected: selected,
    child: SizedBox(
      width: 70,
      height: 75,
      child: InkWell(
        onTap: action,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (label == 'Beranda' && selected)
              SvgPicture.asset('assets/journey/home.svg', width: 24, height: 24)
            else if (label == 'Profil' && !selected)
              SvgPicture.asset('assets/journey/user.svg', width: 24, height: 24)
            else
              Icon(icon, size: 28, color: ReefishColors.textPrimary),
            const SizedBox(height: 5),
            SizedBox(
              height: 16,
              child: selected
                  ? Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    ),
  );
}
